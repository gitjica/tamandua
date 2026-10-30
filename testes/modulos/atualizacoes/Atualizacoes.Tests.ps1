# Módulo atualizações. Registro sempre em HKCU:\Software\TamanduaTestes (o HKLM das políticas é redirecionado);
# administrador simulado por Mock no processo; a CLI só simula (nunca pede o UAC).

BeforeDiscovery {
    $raizProjeto = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))
    $texto = [IO.File]::ReadAllText((Join-Path $raizProjeto 'modulos\atualizacoes\atualizacoes.json'), [Text.Encoding]::UTF8)
    $politicas = @(foreach ($p in ($texto | ConvertFrom-Json)) { @{ Id = $p.id; Ajuste = $p } })
}

BeforeAll {
    . (Join-Path $PSScriptRoot '..\..\Ajudantes.ps1')
    Import-Module (Join-Path $script:RaizProjeto 'nucleo\Tamandua.Nucleo.psm1') -Force -DisableNameChecking -Global
    Import-Module (Join-Path $script:RaizProjeto 'modulos\atualizacoes\atualizacoes.psm1') -Force -DisableNameChecking
    $script:ChaveTestes = "HKCU:\Software\TamanduaTestes\wu-$([guid]::NewGuid().ToString('N'))"
    function New-RaizRegistro { "$script:ChaveTestes\$([guid]::NewGuid().ToString('N'))" }
    $catalogo = @(InModuleScope atualizacoes { Get-CatalogoPoliticas })
}

AfterAll {
    if (Test-Path -LiteralPath $script:ChaveTestes) { Remove-Item -LiteralPath $script:ChaveTestes -Recurse -Force }
    $mae = 'HKCU:\Software\TamanduaTestes'
    if ((Test-Path -LiteralPath $mae) -and @(Get-ChildItem -LiteralPath $mae).Count -eq 0) { Remove-Item -LiteralPath $mae -Force }
}

Describe 'Regras do catálogo' {
    It 'nunca desliga o Windows Update' {
        # NoAutoUpdate, AUOptions=1, desativar o serviço, bloquear o servidor: nada disso pode estar no catálogo.
        $proibido = 'NoAutoUpdate|AUOptions|wuauserv|UsoSvc|WaaSMedicSvc|DisableWindowsUpdateAccess|WUServer|SetDisableUXWUAccess|"Servico"'
        foreach ($p in $catalogo) { ($p | ConvertTo-Json -Depth 5) | Should -Not -Match $proibido -Because $p.id }
    }

    It 'toda política tem classificação; Atenção diz o que pode dar errado e como resolver' {
        foreach ($p in $catalogo) {
            $p.classificacao | Should -BeIn @('Recomendado', 'Opcional', 'Atencao', 'Arriscado') -Because $p.id
            if ($p.classificacao -in 'Atencao', 'Arriscado') {
                $p.contratempo | Should -Not -BeNullOrEmpty -Because $p.id
                $p.seAcontecer | Should -Not -BeNullOrEmpty -Because $p.id
            }
        }
    }

    It 'tudo em HKLM com requerAdmin, padraoWindows declarado, ids com prefixo wu-' {
        foreach ($p in $catalogo) {
            $p.id | Should -MatchExactly '^wu-[a-z0-9-]+$'
            $p.requerAdmin | Should -BeTrue
            foreach ($m in $p.mudancas) {
                $m.caminho | Should -BeLike 'HKLM:\SOFTWARE\Policies\*'
                $m.PSObject.Properties.Name | Should -Contain 'padraoWindows'
            }
        }
    }
}

Describe 'Ida e volta de <Id>' -ForEach $politicas {
    It 'aplica, fica Aplicado, desfaz e não sobra valor' {
        $env:TAMANDUA_DADOS = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
        Mock Test-TmdAdministrador -ModuleName Tamandua.Nucleo { $true }
        $raiz = New-RaizRegistro
        (Set-TmdAjuste -Ajuste $Ajuste -RaizRegistro $raiz).Status | Should -Be 'Feito'
        Get-TmdEstadoAjuste -Ajuste $Ajuste -RaizRegistro $raiz | Should -Be 'Aplicado'
        Test-TmdDesfazerPrecisaAdmin -Id $Id | Should -BeFalse -Because 'na chave de teste não precisa de admin para voltar'
        (Undo-TmdAjuste -Id $Id).Status | Should -Be 'Feito'
        @(Get-ChildItem -LiteralPath $raiz -Recurse | ForEach-Object { $_.GetValueNames() } | Where-Object { $_ }).Count | Should -Be 0
    }
}

Describe 'Find-Alvos e Invoke-Acao' {
    BeforeEach {
        $env:TAMANDUA_DADOS = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
        $raiz = New-RaizRegistro
    }

    It 'estado real por política, nada marcado, tudo pede admin e é reversível' {
        $alvos = @(Find-Alvos -RaizRegistro $raiz)
        $alvos.Count | Should -Be $catalogo.Count
        @($alvos | ForEach-Object Estado | Select-Object -Unique) | Should -Be 'NaoAplicado'
        @($alvos | Where-Object Selecionado).Count | Should -Be 0
        @($alvos | Where-Object { -not $_.RequerAdmin -or -not $_.Reversivel }).Count | Should -Be 0
        ($alvos | Where-Object Id -eq 'wu-adiar-recursos').Presets | Should -Contain 'Equilibrado'
    }

    It 'sem admin, a aplicação é ignorada (o núcleo é quem eleva) e nada é escrito' {
        Mock Test-TmdAdministrador -ModuleName Tamandua.Nucleo { $false }
        $r = Invoke-Acao -Alvos @([pscustomobject]@{ Id = 'wu-sem-drivers' }) -RaizRegistro $raiz
        $r.Status | Should -Be 'Ignorado'
        Test-Path -LiteralPath $raiz | Should -BeFalse
    }

    It 'aplica pela definição do catálogo; política desconhecida é erro' {
        Mock Test-TmdAdministrador -ModuleName Tamandua.Nucleo { $true }
        (Invoke-Acao -Alvos @([pscustomobject]@{ Id = 'wu-sem-drivers'; mudancas = @('NoAutoUpdate') }) -RaizRegistro $raiz).Status | Should -Be 'Feito'
        (Invoke-Acao -Alvos @([pscustomobject]@{ Id = 'wu-desligar-tudo' }) -RaizRegistro $raiz).Status | Should -Be 'Erro'
        (@(Find-Alvos -RaizRegistro $raiz) | Where-Object Id -eq 'wu-sem-drivers').Estado | Should -Be 'Aplicado'
    }
}

Describe 'Desfazer que precisa de admin' {
    It 'snapshot com HKLM de verdade (sem chave de teste) precisa de admin para voltar' {
        $env:TAMANDUA_DADOS = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
        InModuleScope Tamandua.Nucleo {
            Save-TmdSnapshot -Id 'wu-falso' -Entradas @([pscustomobject]@{
                    Chave = 'x'; Tipo = 'Registro'; Indice = 1; RaizRegistro = ''; Caminho = 'HKLM:\SOFTWARE\Policies\X'; Nome = 'Y'
                    Desfazer = ''; Existia = $false; Valor = $null; TipoValor = $null; Inicializacao = $null; Habilitada = $null
                })
        }
        Test-TmdDesfazerPrecisaAdmin -Id 'wu-falso' | Should -BeTrue
    }

    It 'Undo-TmdAjusteComAdmin manda para o processo elevado só o que precisa, e volta na ordem' {
        $env:TAMANDUA_DADOS = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
        Mock Test-TmdAdministrador -ModuleName Tamandua.Nucleo { $true }
        $raiz = New-RaizRegistro
        foreach ($p in $catalogo | Where-Object { $_.id -in 'wu-sem-drivers', 'wu-sem-reinicio-automatico' }) { Set-TmdAjuste -Ajuste $p -RaizRegistro $raiz | Out-Null }
        Mock Test-TmdAdministrador -ModuleName Tamandua.Nucleo { $false }
        # Finge que só o primeiro precisa de admin; o "processo elevado" é um powershell comum rodando "__elevado".
        Mock Test-TmdDesfazerPrecisaAdmin -ModuleName Tamandua.Nucleo { $Id -eq 'wu-sem-drivers' }
        Mock Start-TmdProcessoElevado -ModuleName Tamandua.Nucleo {
            $argumentos = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', "`"$Script`"", '__elevado', "`"$Pedido`"")
            Start-Process -FilePath 'powershell.exe' -ArgumentList $argumentos -WindowStyle Hidden -PassThru
        }
        $r = @(Undo-TmdAjusteComAdmin -Ids 'wu-sem-drivers', 'wu-sem-reinicio-automatico' -Raiz $script:RaizProjeto)
        ($r | ForEach-Object Id) -join ',' | Should -Be 'wu-sem-drivers,wu-sem-reinicio-automatico'
        @($r | Where-Object Status -ne 'Feito').Count | Should -Be 0
        Should -Invoke Start-TmdProcessoElevado -ModuleName Tamandua.Nucleo -Times 1 -Exactly
        @(Get-ChildItem -LiteralPath $raiz -Recurse | ForEach-Object { $_.GetValueNames() } | Where-Object { $_ }).Count | Should -Be 0
    }
}

Describe 'Pela linha de comando (só simulando)' {
    It '-Preset Equilibrado -Simular mostra o que mudaria, sem pedir admin nem escrever' {
        $raiz = New-RaizRegistro
        $projeto = New-ProjetoFalso -Pai $TestDrive -ModulosReais 'atualizacoes'
        $r = Invoke-Tamandua -Raiz $projeto -Argumentos 'atualizacoes', '-Preset', 'Equilibrado', '-Simular' -Ambiente @{ TAMANDUA_REGISTRO_TESTE = $raiz }
        $r.Codigo | Should -Be 0
        # O terminal corta nomes longos com "…".
        $r.Saida | Should -Match '\[x\] Adiar atualizações de rec'
        $r.Saida | Should -Match '\[ \] Não instalar drivers'
        $r.Saida | Should -Match 'DeferFeatureUpdatesPeriodInDays: não existe → 365'
        Test-Path -LiteralPath $raiz | Should -BeFalse
    }
}
