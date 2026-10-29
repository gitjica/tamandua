# Módulo desinstalar. Lista de programas e desinstalador são simulados (Mock): nenhum teste desinstala nada.
# Restos ficam em AppData/ProgramData falsos da sandbox (variáveis de ambiente trocadas só durante o teste).

BeforeAll {
    . (Join-Path $PSScriptRoot '..\..\Ajudantes.ps1')
    Import-Module (Join-Path $script:RaizProjeto 'nucleo\Tamandua.Nucleo.psm1') -Force -DisableNameChecking -Global
    Import-Module (Join-Path $script:RaizProjeto 'modulos\desinstalar\desinstalar.psm1') -Force -DisableNameChecking
    InModuleScope desinstalar { $script:EsperaMaximaSeg = 0 }

    function New-ProgramaFalso([string]$Id, [string]$Nome, [string]$Desinstalador, [string]$Editor = 'Acme', [bool]$ParaTodos = $true) {
        [pscustomobject]@{ Id = $Id; Nome = $Nome; Editor = $Editor; Versao = '1.2.3'; TamanhoKB = 2048; Instalado = '20260115'; Desinstalador = $Desinstalador; ParaTodos = $ParaTodos }
    }

    function Set-SistemaFalso {
        param([int]$Codigo = 0, [switch]$NaoRemove)
        $global:TmdTesteProgramas = [System.Collections.Generic.List[object]]::new()
        $global:TmdTesteProgramas.Add((New-ProgramaFalso 'prog:HKLM64:Acme' 'Acme Editor 1.2.3 (x64)' '"C:\Program Files\Acme\uninstall.exe" /S'))
        $global:TmdTesteProgramas.Add((New-ProgramaFalso 'prog:HKLM64:{11111111-2222-3333-4444-555555555555}' 'Ferramenta MSI' 'MsiExec.exe /I{11111111-2222-3333-4444-555555555555}'))
        $global:TmdTesteProgramas.Add((New-ProgramaFalso 'prog:HKLM64:VC' 'Microsoft Visual C++ 2015-2022 Redistributable (x64)' 'C:\ProgramData\Package Cache\vc.exe /uninstall' 'Microsoft Corporation'))
        $global:TmdTesteChamadas = [System.Collections.Generic.List[string]]::new()
        $global:TmdTesteCodigo = $Codigo
        $global:TmdTesteNaoRemove = $NaoRemove.IsPresent
        Mock Get-RegistroPrograma -ModuleName desinstalar { $global:TmdTesteProgramas.ToArray() }
        Mock Start-Desinstalador -ModuleName desinstalar {
            $global:TmdTesteChamadas.Add("$Arquivo|$Argumentos")
            if (-not $global:TmdTesteNaoRemove) {
                # Parênteses: no PowerShell -and e -or têm a mesma precedência.
                $alvo = @($global:TmdTesteProgramas | Where-Object { ($Arquivo -like '*uninstall.exe' -and $_.Id -eq 'prog:HKLM64:Acme') -or ($Arquivo -eq 'msiexec.exe' -and $_.Nome -eq 'Ferramenta MSI') })
                foreach ($p in $alvo) { [void]$global:TmdTesteProgramas.Remove($p) }
            }
            $global:TmdTesteCodigo
        }
    }

    function Use-PastasFalsas {
        $base = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
        $pastas = @{ APPDATA = "$base\Roaming"; LOCALAPPDATA = "$base\Local"; ProgramData = "$base\ProgramData" }
        New-ArvoreFalsa -Pasta $base -Arquivos @{
            'Roaming\Acme Editor\config.json' = '{}'
            'Local\Acme\Acme Editor\cache.bin' = ('c' * 300)
            'ProgramData\Outra Coisa\x.txt'    = 'não é resto'
        } | Out-Null
        $script:EnvOriginal = @{ APPDATA = $env:APPDATA; LOCALAPPDATA = $env:LOCALAPPDATA; ProgramData = $env:ProgramData }
        foreach ($k in $pastas.Keys) { Set-Item "Env:\$k" $pastas[$k] }
        $base
    }
    function Restore-PastasReais { foreach ($k in $script:EnvOriginal.Keys) { Set-Item "Env:\$k" $script:EnvOriginal[$k] } }
}

AfterAll {
    Remove-Variable -Name TmdTesteProgramas, TmdTesteChamadas, TmdTesteCodigo, TmdTesteNaoRemove -Scope Global -ErrorAction SilentlyContinue
}

Describe 'Entender o comando de desinstalação' {
    It '<Linha> -> <Arquivo> | <Argumentos>' -ForEach @(
        @{ Linha = '"C:\Program Files\Acme\uninstall.exe" /S'; Arquivo = 'C:\Program Files\Acme\uninstall.exe'; Argumentos = '/S' }
        @{ Linha = 'C:\Apps\x\unins000.exe'; Arquivo = 'C:\Apps\x\unins000.exe'; Argumentos = '' }
        @{ Linha = 'C:\Program Files\Y\remove.exe --mode uninstall'; Arquivo = 'C:\Program Files\Y\remove.exe'; Argumentos = '--mode uninstall' }
        @{ Linha = 'MsiExec.exe /I{11111111-2222-3333-4444-555555555555}'; Arquivo = 'msiexec.exe'; Argumentos = '/x {11111111-2222-3333-4444-555555555555}' }
    ) {
        $c = InModuleScope desinstalar -Parameters @{ L = $Linha } { param($L) Get-ComandoDesinstalar -Linha $L }
        $c.Arquivo | Should -Be $Arquivo
        $c.Argumentos | Should -Be $Argumentos
    }

    It 'comando sem executável reconhecível ou MSI sem código: não roda nada' {
        InModuleScope desinstalar { Get-ComandoDesinstalar -Linha 'rundll32 algo' } | Should -BeNullOrEmpty
        InModuleScope desinstalar { Get-ComandoDesinstalar -Linha 'MsiExec.exe /X' } | Should -BeNullOrEmpty
    }
}

Describe 'Find-Alvos' {
    BeforeEach {
        $env:TAMANDUA_DADOS = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
        Set-SistemaFalso
    }

    It 'lista os programas, nada marcado, runtimes e redistribuíveis com risco alto' {
        $alvos = @(Find-Alvos)
        $alvos.Count | Should -Be 3
        @($alvos | Where-Object Selecionado).Count | Should -Be 0
        ($alvos | Where-Object Id -eq 'prog:HKLM64:VC').Risco | Should -Be 'Alto'
        ($alvos | Where-Object Id -eq 'prog:HKLM64:Acme').Risco | Should -Be 'Medio'
        ($alvos | Where-Object Id -eq 'prog:HKLM64:Acme').Detalhe | Should -Match 'Acme · versão 1.2.3 · 2[,.]0 MB · instalado em 15/01/2026'
        ($alvos | Where-Object Id -eq 'prog:HKLM64:Acme').Reversivel | Should -BeFalse
    }

    It 'agrupa "para todos" antes de "só seu usuário" e ignora data de instalação inválida' {
        $global:TmdTesteProgramas.Add((New-ProgramaFalso 'prog:HKCU:Zed' 'Aaa do usuário' 'C:\x\u.exe' -ParaTodos $false))
        $global:TmdTesteProgramas[0].Instalado = '20265322'
        $alvos = @(Find-Alvos)
        ($alvos | ForEach-Object Categoria | Select-Object -Unique) -join '|' | Should -Be 'Programas (para todos os usuários)|Programas (só seu usuário)'
        ($alvos | Where-Object Id -eq 'prog:HKLM64:Acme').Detalhe | Should -Not -Match 'instalado em'
    }

    It 'lê o registro real sem quebrar (só leitura)' {
        $reais = @(InModuleScope desinstalar { & (Get-Module desinstalar) { Get-RegistroPrograma } })
        $reais.Count | Should -BeGreaterThan 0
        @($reais | Where-Object { -not $_.Nome -or -not $_.Desinstalador }).Count | Should -Be 0
    }
}

Describe 'Desinstalar' {
    BeforeEach {
        $env:TAMANDUA_DADOS = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
        $base = Use-PastasFalsas
    }
    AfterEach { Restore-PastasReais }

    It 'roda o desinstalador, confere que saiu da lista e guarda os restos com o nome exato' {
        Set-SistemaFalso
        $r = Invoke-Acao -Alvos @([pscustomobject]@{ Id = 'prog:HKLM64:Acme' })
        $r.Status | Should -Be 'Feito'
        $r.Motivo | Should -Match '2 pasta\(s\) de resto'
        $global:TmdTesteChamadas[0] | Should -Be 'C:\Program Files\Acme\uninstall.exe|/S'
        $restos = @(Find-Alvos | Where-Object { $_.Id -like 'resto:*' })
        ($restos | ForEach-Object Caminho | Sort-Object) -join ',' | Should -Be "$base\Local\Acme\Acme Editor,$base\Roaming\Acme Editor"
        @($restos | Where-Object Selecionado).Count | Should -Be 0
        # Padrão específico: a própria sandbox fica em ...\AppData\Local\Temp.
        ($restos | Where-Object { $_.Caminho -like '*\Local\Acme\*' }).Tamanho | Should -Be 300
    }

    It 'MSI é desinstalado com /x (e não /I, que abriria o reparo)' {
        Set-SistemaFalso
        (Invoke-Acao -Alvos @([pscustomobject]@{ Id = 'prog:HKLM64:{11111111-2222-3333-4444-555555555555}' })).Status | Should -Be 'Feito'
        $global:TmdTesteChamadas[0] | Should -Be 'msiexec.exe|/x {11111111-2222-3333-4444-555555555555}'
    }

    It 'desinstalador que termina e o programa continua na lista: erro, sem restos' {
        Set-SistemaFalso -NaoRemove
        $r = Invoke-Acao -Alvos @([pscustomobject]@{ Id = 'prog:HKLM64:Acme' })
        $r.Status | Should -Be 'Erro'
        $r.Motivo | Should -Match 'continua na lista'
        @(Find-Alvos | Where-Object { $_.Id -like 'resto:*' }).Count | Should -Be 0
    }

    It 'cancelado no desinstalador (1602): ignorado' {
        Set-SistemaFalso -Codigo 1602 -NaoRemove
        (Invoke-Acao -Alvos @([pscustomobject]@{ Id = 'prog:HKLM64:Acme' })).Motivo | Should -Be 'cancelado no desinstalador'
    }

    It '-Simular não roda o desinstalador e mostra o comando' {
        Set-SistemaFalso
        $r = Invoke-Acao -Alvos @([pscustomobject]@{ Id = 'prog:HKLM64:Acme' }) -Simular
        $r.Status | Should -Be 'Simulado'
        $r.Mudancas[0] | Should -Be 'executa: C:\Program Files\Acme\uninstall.exe /S'
        $global:TmdTesteChamadas.Count | Should -Be 0
    }

    It 'o comando vem do registro, não do alvo; programa que não está mais instalado é ignorado' {
        Set-SistemaFalso
        $r = @(Invoke-Acao -Alvos @(
                [pscustomobject]@{ Id = 'prog:HKLM64:Sumiu'; Mudancas = @('format C:') }
            ))
        $r[0].Status | Should -Be 'Ignorado'
        $global:TmdTesteChamadas.Count | Should -Be 0
    }

    It 'restos vão para a Lixeira; resto que não foi guardado pelo Tamanduá é recusado' {
        Set-SistemaFalso
        $env:TAMANDUA_LIXEIRA_TESTE = Join-Path $base 'Lixeira'
        try {
            Invoke-Acao -Alvos @([pscustomobject]@{ Id = 'prog:HKLM64:Acme' }) | Out-Null
            $restos = @(Find-Alvos | Where-Object { $_.Id -like 'resto:*' })
            $r = @(Invoke-Acao -Alvos ($restos + [pscustomobject]@{ Id = "resto:$base\ProgramData\Outra Coisa" }))
            @($r | Where-Object Status -eq 'Feito').Count | Should -Be 2
            ($r | Where-Object { $_.Id -like '*Outra Coisa' }).Motivo | Should -Match 'não é um resto guardado'
            Test-Path "$base\Roaming\Acme Editor" | Should -BeFalse
            Test-Path "$base\ProgramData\Outra Coisa\x.txt" | Should -BeTrue
            @(Get-ChildItem -LiteralPath (Join-Path $base 'Lixeira')).Count | Should -Be 2
            @(Find-Alvos | Where-Object { $_.Id -like 'resto:*' }).Count | Should -Be 0 -Because 'os restos removidos saem da lista'
        }
        finally { Remove-Item Env:\TAMANDUA_LIXEIRA_TESTE -ErrorAction SilentlyContinue }
    }

    It 'nome limpo: tira versão, arquitetura e sufixo de empresa' {
        InModuleScope desinstalar {
            Get-NomeLimpo -Nome 'Obsidian 1.14.4 (x64)' | Should -Be 'Obsidian'
            Get-NomeLimpo -Nome 'Acme Software, Inc.' | Should -Be 'Acme Software'
            Get-NomeLimpo -Nome 'Notepad++ (64-bit x64)' | Should -Be 'Notepad++ (64-bit x64)'
        }
    }
}
