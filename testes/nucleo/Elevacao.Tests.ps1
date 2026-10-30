# Elevação por lote. O UAC nunca é pedido de verdade: Start-TmdProcessoElevado é trocado por um processo comum
# que roda o mesmo "tamandua.ps1 __elevado", então o caminho todo (pedido -> processo -> resposta) é testado.

BeforeAll {
    . (Join-Path $PSScriptRoot '..\Ajudantes.ps1')
    Import-Module (Join-Path $script:RaizProjeto 'nucleo\Tamandua.Nucleo.psm1') -Force -DisableNameChecking -Global

    function New-ProjetoComAdmin {
        $raiz = New-ProjetoFalso -Pai $TestDrive -Catalogo 'precisa', 'comum', 'lento'
        $codigo = @'
function Test-Requisitos { @{ Ok = $true } }
function Find-Alvos { [pscustomobject]@{ Id = 'a'; Nome = 'A'; Categoria = 'C'; Estado = 'NaoSeAplica'; Detalhe = ''; Caminho = ''; Tamanho = [int64]0; Risco = 'Baixo'; Selecionado = $true; Destino = 'NaoSeAplica'; RequerAdmin = $true; Reversivel = $false; Mudancas = @() } }
function Invoke-Acao {
    param([object[]]$Alvos, [switch]$Simular)
    foreach ($a in $Alvos) { [pscustomobject]@{ Id = $a.Id; Status = $(if ($Simular) { 'Simulado' } else { 'Feito' }); Liberado = [int64]0; Motivo = "processo $PID"; Mudancas = @() } }
}
'@
        New-ModuloFalso -Raiz $raiz -Nome 'precisa' -Manifesto @{ Escreve = $true; RequerAdmin = $true } -Codigo $codigo | Out-Null
        New-ModuloFalso -Raiz $raiz -Nome 'comum' -Manifesto @{ Escreve = $true } -Codigo $codigo | Out-Null
        # Cada item demora, para dar tempo de o processo normal ver o progresso do elevado.
        New-ModuloFalso -Raiz $raiz -Nome 'lento' -Manifesto @{ Escreve = $true; RequerAdmin = $true } `
            -Codigo $codigo.Replace('foreach ($a in $Alvos) {', 'foreach ($a in $Alvos) { Start-Sleep -Milliseconds 900;') | Out-Null
        $raiz
    }
}

Describe 'Progresso item a item' {
    BeforeEach {
        $raiz = New-ProjetoComAdmin
        Mock Test-TmdAdministrador -ModuleName Tamandua.Nucleo { $false }
        $global:TmdTesteProgresso = [System.Collections.Generic.List[string]]::new()
        Mock Write-TmdProgresso -ModuleName Tamandua.Nucleo { $global:TmdTesteProgresso.Add("$Texto|$Atual|$Total") }
    }
    AfterEach { Remove-Variable -Name TmdTesteProgresso, TmdTestePedido -Scope Global -ErrorAction SilentlyContinue }

    It 'roda um alvo por vez e avisa cada um pelo nome (ou Id, sem nome)' {
        $info = Get-TmdModulo -Raiz $raiz -Nome 'comum'
        $r = @(Invoke-TmdAcaoModulo -Info $info -Raiz $raiz -Alvos @(
                [pscustomobject]@{ Id = 'a'; Nome = 'Primeiro' }
                [pscustomobject]@{ Id = 'b'; Nome = 'Segundo' }
                [pscustomobject]@{ Id = 'c' }
            ))
        ($r | ForEach-Object Id) -join ',' | Should -Be 'a,b,c'
        $global:TmdTesteProgresso -join ';' | Should -Be 'Primeiro|1|3;Segundo|2|3;c|3|3'
    }

    It 'simular não emite progresso (é rápido e vai de uma vez)' {
        $info = Get-TmdModulo -Raiz $raiz -Nome 'comum'
        [void](Invoke-TmdAcaoModulo -Info $info -Raiz $raiz -Simular -Alvos @([pscustomobject]@{ Id = 'a' }, [pscustomobject]@{ Id = 'b' }))
        $global:TmdTesteProgresso.Count | Should -Be 0
    }

    It 'o progresso do processo elevado chega aqui; o arquivo de progresso some no fim' {
        Mock Start-TmdProcessoElevado -ModuleName Tamandua.Nucleo {
            $global:TmdTestePedido = [IO.File]::ReadAllText($Pedido) | ConvertFrom-Json
            $argumentos = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', "`"$Script`"", '__elevado', "`"$Pedido`"")
            Start-Process -FilePath 'powershell.exe' -ArgumentList $argumentos -WindowStyle Hidden -PassThru
        }
        $info = Get-TmdModulo -Raiz $raiz -Nome 'lento'
        $r = @(Invoke-TmdAcaoModulo -Info $info -Raiz $raiz -Alvos @(
                [pscustomobject]@{ Id = 'sfc'; Nome = 'Verificar arquivos'; RequerAdmin = $true }
                [pscustomobject]@{ Id = 'dism'; Nome = 'Reparar imagem'; RequerAdmin = $true }
            ))
        @($r | Where-Object Status -eq 'Feito').Count | Should -Be 2
        $global:TmdTesteProgresso | Should -Contain 'Verificar arquivos|1|2'
        $global:TmdTesteProgresso | Should -Contain 'Reparar imagem|2|2'
        $global:TmdTestePedido.Progresso | Should -Match 'tamandua-.*\.json$'
        Test-Path -LiteralPath $global:TmdTestePedido.Progresso | Should -BeFalse
    }
}

Describe 'Invoke-TmdAcaoModulo' {
    BeforeEach {
        $raiz = New-ProjetoComAdmin
        Mock Test-TmdAdministrador -ModuleName Tamandua.Nucleo { $false }
    }

    It 'módulo sem RequerAdmin roda aqui mesmo' {
        Mock Start-TmdProcessoElevado -ModuleName Tamandua.Nucleo { throw 'não devia pedir admin' }
        $info = Get-TmdModulo -Raiz $raiz -Nome 'comum'
        $r = @(Invoke-TmdAcaoModulo -Info $info -Alvos @([pscustomobject]@{ Id = 'a' }) -Raiz $raiz)
        $r[0].Motivo | Should -Be "processo $PID"
    }

    It 'módulo com RequerAdmin: um processo à parte roda o lote e devolve os resultados; temporários somem' {
        Mock Start-TmdProcessoElevado -ModuleName Tamandua.Nucleo {
            $global:TmdTestePedido = $Pedido
            $argumentos = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', "`"$Script`"", '__elevado', "`"$Pedido`"")
            Start-Process -FilePath 'powershell.exe' -ArgumentList $argumentos -WindowStyle Hidden -PassThru
        }
        $info = Get-TmdModulo -Raiz $raiz -Nome 'precisa'
        $r = @(Invoke-TmdAcaoModulo -Info $info -Alvos @([pscustomobject]@{ Id = 'a'; RequerAdmin = $true }, [pscustomobject]@{ Id = 'b'; RequerAdmin = $true }) -Raiz $raiz)
        $r.Count | Should -Be 2
        ($r | ForEach-Object Id) -join ',' | Should -Be 'a,b'
        $r[0].Status | Should -Be 'Feito'
        $r[0].Motivo | Should -Match '^processo \d+$'
        $r[0].Motivo | Should -Not -Be "processo $PID" -Because 'rodou em outro processo'
        Should -Invoke Start-TmdProcessoElevado -ModuleName Tamandua.Nucleo -Times 1 -Exactly
        Test-Path -LiteralPath $global:TmdTestePedido | Should -BeFalse
    }

    It 'só os itens que pedem admin vão para o processo elevado; a ordem dos resultados é a dos alvos' {
        Mock Start-TmdProcessoElevado -ModuleName Tamandua.Nucleo {
            $argumentos = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', "`"$Script`"", '__elevado', "`"$Pedido`"")
            Start-Process -FilePath 'powershell.exe' -ArgumentList $argumentos -WindowStyle Hidden -PassThru
        }
        $info = Get-TmdModulo -Raiz $raiz -Nome 'precisa'
        $r = @(Invoke-TmdAcaoModulo -Info $info -Raiz $raiz -Alvos @(
                [pscustomobject]@{ Id = 'usuario1'; RequerAdmin = $false }
                [pscustomobject]@{ Id = 'admin'; RequerAdmin = $true }
                [pscustomobject]@{ Id = 'usuario2' }
            ))
        ($r | ForEach-Object Id) -join ',' | Should -Be 'usuario1,admin,usuario2'
        ($r | Where-Object Id -eq 'usuario1').Motivo | Should -Be "processo $PID"
        ($r | Where-Object Id -eq 'usuario2').Motivo | Should -Be "processo $PID"
        ($r | Where-Object Id -eq 'admin').Motivo | Should -Not -Be "processo $PID"
        Should -Invoke Start-TmdProcessoElevado -ModuleName Tamandua.Nucleo -Times 1 -Exactly
    }

    It 'simular nunca pede admin' {
        Mock Start-TmdProcessoElevado -ModuleName Tamandua.Nucleo { throw 'não devia pedir admin' }
        $info = Get-TmdModulo -Raiz $raiz -Nome 'precisa'
        (Invoke-TmdAcaoModulo -Info $info -Alvos @([pscustomobject]@{ Id = 'a' }) -Simular -Raiz $raiz).Status | Should -Be 'Simulado'
    }

    It 'UAC negado: tudo ignorado, com o motivo, sem exceção' {
        Mock Start-TmdProcessoElevado -ModuleName Tamandua.Nucleo { throw 'A operação foi cancelada pelo usuário' }
        $info = Get-TmdModulo -Raiz $raiz -Nome 'precisa'
        $r = @(Invoke-TmdAcaoModulo -Info $info -Alvos @([pscustomobject]@{ Id = 'a'; RequerAdmin = $true }) -Raiz $raiz)
        $r[0].Status | Should -Be 'Ignorado'
        $r[0].Motivo | Should -Match 'permissão de administrador negada'
    }

    It 'já sendo administrador, não abre outro processo' {
        Mock Test-TmdAdministrador -ModuleName Tamandua.Nucleo { $true }
        Mock Start-TmdProcessoElevado -ModuleName Tamandua.Nucleo { throw 'não devia pedir admin' }
        $info = Get-TmdModulo -Raiz $raiz -Nome 'precisa'
        (Invoke-TmdAcaoModulo -Info $info -Alvos @([pscustomobject]@{ Id = 'a' }) -Raiz $raiz).Motivo | Should -Be "processo $PID"
    }
}

Describe 'Pedir admin ao abrir' {
    BeforeEach {
        $global:TmdTesteReaberto = $null
        Mock Start-TmdReaberturaElevada -ModuleName Tamandua.Nucleo { $global:TmdTesteReaberto = $Script }
    }
    AfterEach {
        $env:TAMANDUA_NAO_ELEVAR = '1'
        Remove-Variable -Name TmdTesteReaberto -Scope Global -ErrorAction SilentlyContinue
    }

    It 'sem admin: abre outra cópia como administrador e esta termina' {
        Remove-Item Env:\TAMANDUA_NAO_ELEVAR
        Mock Test-TmdAdministrador -ModuleName Tamandua.Nucleo { $false }
        Request-TmdAdminAoAbrir -Script 'C:\x\tamandua.ps1' | Should -BeTrue
        $global:TmdTesteReaberto | Should -Be 'C:\x\tamandua.ps1'
    }

    It 'UAC recusado: continua sem admin, sem erro' {
        Remove-Item Env:\TAMANDUA_NAO_ELEVAR
        Mock Test-TmdAdministrador -ModuleName Tamandua.Nucleo { $false }
        Mock Start-TmdReaberturaElevada -ModuleName Tamandua.Nucleo { throw 'A operação foi cancelada pelo usuário' }
        Request-TmdAdminAoAbrir -Script 'C:\x\tamandua.ps1' | Should -BeFalse
    }

    It 'já é admin, ou TAMANDUA_NAO_ELEVAR: não pede' {
        Mock Test-TmdAdministrador -ModuleName Tamandua.Nucleo { $true }
        Remove-Item Env:\TAMANDUA_NAO_ELEVAR
        Request-TmdAdminAoAbrir -Script 'C:\x\tamandua.ps1' | Should -BeFalse
        Mock Test-TmdAdministrador -ModuleName Tamandua.Nucleo { $false }
        $env:TAMANDUA_NAO_ELEVAR = '1'
        Request-TmdAdminAoAbrir -Script 'C:\x\tamandua.ps1' | Should -BeFalse
        Should -Invoke Start-TmdReaberturaElevada -ModuleName Tamandua.Nucleo -Times 0 -Exactly
    }
}

Describe 'Comando interno __elevado' {
    It 'recusa pedido que não é um temporário do Tamanduá' {
        $raiz = New-ProjetoComAdmin
        $falso = Join-Path $TestDrive 'pedido.json'
        Set-Content -LiteralPath $falso -Value '{"Modulo":"precisa","Alvos":[],"Resposta":"C:\\Windows\\x.json"}'
        $r = Invoke-Tamandua -Raiz $raiz -Argumentos '__elevado', "`"$falso`""
        $r.Codigo | Should -Be 1
        $r.Erro | Should -Match 'pedido inválido'
    }

    It 'recusa resposta fora da pasta temporária' {
        $raiz = New-ProjetoComAdmin
        $pedido = New-TmdArquivoTemporario -Extensao '.json'
        Set-Content -LiteralPath $pedido -Value '{"Modulo":"precisa","Alvos":[{"Id":"a"}],"Resposta":"C:\\Users\\Public\\tamandua-x.json"}'
        try {
            $r = Invoke-Tamandua -Raiz $raiz -Argumentos '__elevado', "`"$pedido`""
            $r.Codigo | Should -Be 1
            Test-Path 'C:\Users\Public\tamandua-x.json' | Should -BeFalse
        }
        finally { Remove-TmdArquivoTemporario -Caminho $pedido }
    }
}

Describe 'Invoke-TmdPrograma' {
    It 'devolve código e saída, e registra no log' {
        $env:TAMANDUA_DADOS = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
        $r = Invoke-TmdPrograma -Arquivo 'cmd.exe' -Argumentos '/c echo ola & exit 3' -Modulo 'teste' -Id 'x'
        $r.Codigo | Should -Be 3
        $r.Saida | Should -Contain 'ola '
        $h = @(Get-TmdHistorico -Ultimos 1)[0]
        $h.Acao | Should -Be 'executar'
        $h.Status | Should -Be 'Erro'
        $h.Motivo | Should -Be 'código 3'
    }
}
