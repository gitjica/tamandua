# Módulo ajustes. Todo registro vai para HKCU:\Software\TamanduaTestes (por -RaizRegistro no processo,
# ou TAMANDUA_REGISTRO_TESTE nos processos filhos); nada toca no registro real.

BeforeDiscovery {
    $raizProjeto = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))
    $texto = [IO.File]::ReadAllText((Join-Path $raizProjeto 'modulos\ajustes\ajustes.json'), [Text.Encoding]::UTF8)
    $ajustesCatalogo = @(foreach ($a in ($texto | ConvertFrom-Json)) { @{ Id = $a.id; Ajuste = $a } })
}

BeforeAll {
    . (Join-Path $PSScriptRoot '..\..\Ajudantes.ps1')
    Import-Module (Join-Path $script:RaizProjeto 'nucleo\Tamandua.Nucleo.psm1') -Force -DisableNameChecking -Global
    Import-Module (Join-Path $script:RaizProjeto 'modulos\ajustes\ajustes.psm1') -Force -DisableNameChecking
    $script:ChaveTestes = "HKCU:\Software\TamanduaTestes\ajustes-$([guid]::NewGuid().ToString('N'))"
    function New-RaizRegistro { "$script:ChaveTestes\$([guid]::NewGuid().ToString('N'))" }
    $catalogo = @(InModuleScope ajustes { Get-CatalogoAjustes })
}

AfterAll {
    if (Test-Path -LiteralPath $script:ChaveTestes) { Remove-Item -LiteralPath $script:ChaveTestes -Recurse -Force }
    $mae = 'HKCU:\Software\TamanduaTestes'
    if ((Test-Path -LiteralPath $mae) -and @(Get-ChildItem -LiteralPath $mae).Count -eq 0) { Remove-Item -LiteralPath $mae -Force }
}

Describe 'Regras do catálogo (seção 8 do guia)' {
    It 'ids únicos, minúsculos, com prefixo de categoria' {
        $ids = @($catalogo | ForEach-Object { $_.id })
        @($ids | Select-Object -Unique).Count | Should -Be $ids.Count
        foreach ($id in $ids) { $id | Should -MatchExactly '^[a-z]+-[a-z0-9-]+$' }
    }

    It 'todo ajuste tem nome, descrição, categoria, risco válido e presets' {
        foreach ($a in $catalogo) {
            $a.nome | Should -Not -BeNullOrEmpty
            $a.descricao | Should -Not -BeNullOrEmpty
            $a.categoria | Should -Not -BeNullOrEmpty
            $a.risco | Should -BeIn 'Baixo', 'Medio', 'Alto'
            $a.PSObject.Properties.Name | Should -Contain 'presets'
            $a.requerAdmin | Should -BeOfType [bool]
        }
    }

    It 'toda mudança de registro/serviço/tarefa declara padraoWindows; script tem desfazer' {
        foreach ($a in $catalogo) {
            foreach ($m in $a.mudancas) {
                if ($m.tipo -in 'Registro', 'Servico', 'Tarefa') { $m.PSObject.Properties.Name | Should -Contain 'padraoWindows' -Because $a.id }
                if ($m.tipo -eq 'Script') {
                    $m.desfazer | Should -Not -BeNullOrEmpty -Because $a.id
                    if (-not $m.verificar) { $a.risco | Should -BeIn 'Medio', 'Alto' -Because "$($a.id): script sem verificar" }
                }
                if ($m.tipo -eq 'Registro' -and $m.caminho -like 'HKLM:*') { $a.requerAdmin | Should -BeTrue -Because $a.id }
            }
        }
    }

    It 'nada que mexa em segurança (Defender, UAC, SmartScreen, firewall, BitLocker)' {
        $proibido = 'Defender|SmartScreen|EnableLUA|ConsentPrompt|PromptOnSecureDesktop|Firewall|FVE|BitLocker|MpSvc|WinDefend'
        foreach ($a in $catalogo) {
            ($a | ConvertTo-Json -Depth 5) | Should -Not -Match $proibido -Because $a.id
        }
    }

    It 'preset Essencial só tem risco baixo e todo preset tem pelo menos 2 itens' {
        foreach ($a in $catalogo | Where-Object { @($_.presets) -contains 'Essencial' }) { $a.risco | Should -Be 'Baixo' -Because $a.id }
        $presets = @($catalogo | ForEach-Object { @($_.presets) } | Where-Object { $_ } | Select-Object -Unique)
        foreach ($p in $presets) { @($catalogo | Where-Object { @($_.presets) -contains $p }).Count | Should -BeGreaterOrEqual 2 -Because $p }
    }

    It 'nesta etapa, todos os ajustes ficam em HKCU e não pedem admin' {
        foreach ($a in $catalogo) {
            $a.requerAdmin | Should -BeFalse -Because $a.id
            foreach ($m in $a.mudancas) { $m.caminho | Should -BeLike 'HKCU:\*' -Because $a.id }
        }
    }
}

Describe 'Ida e volta de <Id>' -ForEach $ajustesCatalogo {
    It 'aplica, fica Aplicado, desfaz e volta exatamente ao que era' {
        $env:TAMANDUA_DADOS = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
        $raiz = New-RaizRegistro
        Get-TmdEstadoAjuste -Ajuste $Ajuste -RaizRegistro $raiz | Should -Be 'NaoAplicado'
        $r = Set-TmdAjuste -Ajuste $Ajuste -RaizRegistro $raiz
        $r.Status | Should -Be 'Feito' -Because $r.Motivo
        Get-TmdEstadoAjuste -Ajuste $Ajuste -RaizRegistro $raiz | Should -Be 'Aplicado'
        (Undo-TmdAjuste -Id $Id -RaizRegistro $raiz).Status | Should -Be 'Feito'
        Get-TmdEstadoAjuste -Ajuste $Ajuste -RaizRegistro $raiz | Should -Be 'NaoAplicado'
        @(Get-ChildItem -LiteralPath $raiz -Recurse | ForEach-Object { $_.GetValueNames() } | Where-Object { $_ }).Count |
            Should -Be 0 -Because 'nenhum valor pode sobrar depois de desfazer'
    }
}

Describe 'Find-Alvos e Invoke-Acao' {
    BeforeEach {
        $env:TAMANDUA_DADOS = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
        $raiz = New-RaizRegistro
    }

    It 'um alvo por ajuste, nada marcado, com estado, presets e o que muda' {
        $alvos = @(Find-Alvos -RaizRegistro $raiz)
        $alvos.Count | Should -Be $catalogo.Count
        @($alvos | Where-Object Selecionado).Count | Should -Be 0
        @($alvos | ForEach-Object Estado | Select-Object -Unique) | Should -Be 'NaoAplicado'
        ($alvos | Where-Object Id -eq 'priv-id-anuncios').Presets | Should -Contain 'Essencial'
        ($alvos | Where-Object Id -eq 'expl-extensoes').Mudancas[0] | Should -Match 'HideFileExt = 0 \(padrão do Windows: 1\)'
    }

    It 'estado Parcial quando só parte do ajuste está aplicada' {
        $tema = $catalogo | Where-Object id -eq 'aparencia-tema-escuro'
        Set-TmdAjuste -Ajuste ([pscustomobject]@{ id = 'parte'; nome = 'parte'; requerAdmin = $false; mudancas = @($tema.mudancas[0]) }) -RaizRegistro $raiz | Out-Null
        (@(Find-Alvos -RaizRegistro $raiz) | Where-Object Id -eq 'aparencia-tema-escuro').Estado | Should -Be 'Parcial'
    }

    It 'aplica pela definição do catálogo, não pelo que vem no alvo' {
        $falso = [pscustomobject]@{ Id = 'expl-extensoes'; mudancas = @([pscustomobject]@{ tipo = 'Registro'; caminho = 'HKCU:\Software\Outra'; nome = 'X'; valor = 1; tipoValor = 'DWord' }) }
        $r = @(Invoke-Acao -Alvos @($falso) -RaizRegistro $raiz)
        $r[0].Status | Should -Be 'Feito'
        Test-Path -LiteralPath "$raiz\HKCU\Software\Outra" | Should -BeFalse
        (@(Find-Alvos -RaizRegistro $raiz) | Where-Object Id -eq 'expl-extensoes').Estado | Should -Be 'Aplicado'
    }

    It 'ajuste desconhecido vira erro' {
        (Invoke-Acao -Alvos @([pscustomobject]@{ Id = 'formatar-disco' }) -RaizRegistro $raiz).Status | Should -Be 'Erro'
    }

    It '-Simular não escreve nada' {
        $r = @(Invoke-Acao -Alvos @(Find-Alvos -RaizRegistro $raiz) -Simular -RaizRegistro $raiz)
        @($r | ForEach-Object Status | Select-Object -Unique) | Should -Be 'Simulado'
        Test-Path -LiteralPath $raiz | Should -BeFalse
    }

    It 'TAMANDUA_REGISTRO_TESTE fora da área de testes é ignorado' {
        $env:TAMANDUA_REGISTRO_TESTE = 'HKCU:\Software\Microsoft'
        try { InModuleScope ajustes { Get-RaizRegistroPadrao } | Should -Be '' }
        finally { Remove-Item Env:\TAMANDUA_REGISTRO_TESTE }
    }
}

Describe 'Pela linha de comando' {
    BeforeEach {
        $env:TAMANDUA_DADOS = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
        $raiz = New-RaizRegistro
        $ambiente = @{ TAMANDUA_REGISTRO_TESTE = $raiz }
        $projeto = New-ProjetoFalso -Pai $TestDrive -ModulosReais 'ajustes'
    }

    It '-Preset Essencial -Sim aplica só o preset; desfazer volta (tudo na chave de teste)' {
        $r = Invoke-Tamandua -Raiz $projeto -Argumentos 'ajustes', '-Preset', 'Essencial', '-Sim' -Ambiente $ambiente
        $r.Codigo | Should -Be 0
        $r.Saida | Should -Match '\[x\] Desativar o ID de anúncios'
        $r.Saida | Should -Match '\[ \] Mostrar arquivos ocultos'
        $r.Saida | Should -Match 'tamandua desfazer'
        $essencial = @($catalogo | Where-Object { @($_.presets) -contains 'Essencial' })
        foreach ($a in $essencial) { Get-TmdEstadoAjuste -Ajuste $a -RaizRegistro $raiz | Should -Be 'Aplicado' -Because $a.id }
        Get-TmdEstadoAjuste -Ajuste ($catalogo | Where-Object id -eq 'expl-ocultos') -RaizRegistro $raiz | Should -Be 'NaoAplicado'

        $lista = Invoke-Tamandua -Raiz $projeto -Argumentos 'ajustes', '-Simular' -Ambiente $ambiente
        $lista.Saida | Should -Match 'Desativar o ID de anúncios\s+aplicado'

        # O desfazer não recebe a chave de teste: ela vem do estado salvo.
        (Invoke-Tamandua -Raiz $projeto -Argumentos 'desfazer', 'priv-id-anuncios', '-Sim').Codigo | Should -Be 0
        Get-TmdEstadoAjuste -Ajuste ($catalogo | Where-Object id -eq 'priv-id-anuncios') -RaizRegistro $raiz | Should -Be 'NaoAplicado'
    }

    It '-Itens com -Simular mostra a mudança e não escreve' {
        $r = Invoke-Tamandua -Raiz $projeto -Argumentos 'ajustes', '-Itens', 'expl-extensoes', '-Simular' -Ambiente $ambiente
        $r.Codigo | Should -Be 0
        $r.Saida | Should -Match 'HideFileExt: não existe → 0'
        Test-Path -LiteralPath $raiz | Should -BeFalse
    }

    It '-Itens a,b (como chega pelo powershell -File) marca os dois' {
        $r = Invoke-Tamandua -Raiz $projeto -Argumentos 'ajustes', '-Itens', 'expl-extensoes,expl-ocultos', '-Simular' -Ambiente $ambiente
        $r.Codigo | Should -Be 0
        $r.Saida | Should -Match '\[x\] Mostrar extensões'
        $r.Saida | Should -Match '\[x\] Mostrar arquivos ocultos'
    }

    It 'preset ou item desconhecido, e -Preset em módulo de leitura, são erro' {
        (Invoke-Tamandua -Raiz $projeto -Argumentos 'ajustes', '-Preset', 'Turbo' -Ambiente $ambiente).Saida | Should -Match 'Disponíveis: Essencial'
        (Invoke-Tamandua -Raiz $projeto -Argumentos 'ajustes', '-Itens', 'nada' -Ambiente $ambiente).Codigo | Should -Be 1
        (Invoke-Tamandua -Raiz $projeto -Argumentos 'modulos', '-Preset', 'Essencial').Codigo | Should -Be 1
    }
}
