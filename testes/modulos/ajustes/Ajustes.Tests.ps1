# Módulo ajustes. Todo registro vai para HKCU:\Software\TamanduaTestes (por -RaizRegistro no processo,
# ou TAMANDUA_REGISTRO_TESTE nos processos filhos); nada toca no registro real.

BeforeDiscovery {
    $raizProjeto = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))
    $texto = [IO.File]::ReadAllText((Join-Path $raizProjeto 'modulos\ajustes\ajustes.json'), [Text.Encoding]::UTF8)
    # Ida e volta de verdade (na chave de teste) só para os ajustes que são só registro; serviços vão por Mock.
    $ajustesCatalogo = @(foreach ($a in ($texto | ConvertFrom-Json)) {
            if (-not $a.PSObject.Properties['acao'] -and @($a.mudancas | Where-Object { $_.tipo -ne 'Registro' }).Count -eq 0) { @{ Id = $a.id; Ajuste = $a } }
        })
}

BeforeAll {
    . (Join-Path $PSScriptRoot '..\..\Ajudantes.ps1')
    Import-Module (Join-Path $script:RaizProjeto 'nucleo\Tamandua.Nucleo.psm1') -Force -DisableNameChecking -Global
    Import-Module (Join-Path $script:RaizProjeto 'modulos\ajustes\ajustes.psm1') -Force -DisableNameChecking
    $script:ChaveTestes = "HKCU:\Software\TamanduaTestes\ajustes-$([guid]::NewGuid().ToString('N'))"
    function New-RaizRegistro { "$script:ChaveTestes\$([guid]::NewGuid().ToString('N'))" }
    $catalogo = @(InModuleScope ajustes { Get-CatalogoAjustes })
    # O que a área de testes mostra: só registro e sem admin (igual a Get-AjusteDisponivel).
    $soRegistro = @($catalogo | Where-Object { -not $_.PSObject.Properties['acao'] -and -not $_.requerAdmin -and @($_.mudancas | Where-Object { $_.tipo -ne 'Registro' }).Count -eq 0 })
    $script:Referencia = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'winutil-referencia.json') -Raw -Encoding UTF8 | ConvertFrom-Json
    $script:Categorias = 'Segurança', 'Limpeza (uma vez)', 'Privacidade', 'Sistema', 'Rede', 'Rede (DNS)', 'Apps do Windows (remover)', 'Explorador de Arquivos', 'Barra de tarefas e Iniciar', 'Aparência', 'Mouse e teclado',
    'Desempenho e jogos', 'Energia', 'Navegadores', 'Programas', 'Avançado (por sua conta e risco)'
    $script:Presets = 'Mínimo', 'Essencial', 'Avançado', 'Notebook', 'Desempenho', 'Privacidade', 'Explorador', 'Remover apps'
    function Get-IdsPreset { param($P) @($catalogo | Where-Object { @($_.presets) -contains $P } | ForEach-Object { $_.id }) }
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

    It 'toda mudança de registro/serviço/tarefa declara padraoWindows; script tem desfazer e compila' {
        foreach ($a in $catalogo) {
            foreach ($m in @(if ($a.PSObject.Properties['mudancas']) { $a.mudancas })) {
                if ($m.tipo -in 'Registro', 'Servico', 'Tarefa') { $m.PSObject.Properties.Name | Should -Contain 'padraoWindows' -Because $a.id }
                if ($m.tipo -eq 'Script') {
                    $m.desfazer | Should -Not -BeNullOrEmpty -Because $a.id
                    if (-not $m.verificar) { $a.risco | Should -BeIn 'Medio', 'Alto' -Because "$($a.id): script sem verificar" }
                    foreach ($parte in 'aplicar', 'desfazer', 'verificar') {
                        if (-not $m.$parte) { continue }
                        $erros = $null; $tokens = $null
                        [void][Management.Automation.Language.Parser]::ParseInput($m.$parte, [ref]$tokens, [ref]$erros)
                        @($erros).Count | Should -Be 0 -Because "$($a.id).$parte"
                    }
                }
                # Sistema (HKLM, HKU, serviço, tarefa) pede admin.
                if (($m.tipo -eq 'Registro' -and $m.caminho -match '^(HKLM|HKU):') -or $m.tipo -in 'Servico', 'Tarefa') { $a.requerAdmin | Should -BeTrue -Because $a.id }
            }
        }
    }

    It 'categorias e presets conhecidos' {
        foreach ($a in $catalogo) {
            $a.categoria | Should -BeIn $script:Categorias -Because $a.id
            foreach ($p in @($a.presets)) { $p | Should -BeIn $script:Presets -Because $a.id }
        }
    }

    It 'o que mexe em segurança (Defender, UAC, SmartScreen, firewall, BitLocker) só existe como Avançado: risco alto e fora dos presets' {
        $seguranca = 'Defender|SmartScreen|EnableLUA|ConsentPrompt|PromptOnSecureDesktop|Firewall|FVE|BitLocker|MpSvc|WinDefend|MpPreference'
        $achados = @($catalogo | Where-Object { ($_ | ConvertTo-Json -Depth 5) -match $seguranca })
        $achados.Count | Should -BeGreaterThan 0
        foreach ($a in $achados) {
            $a.categoria | Should -Be 'Avançado (por sua conta e risco)' -Because $a.id
            $a.risco | Should -Be 'Alto' -Because $a.id
            @($a.presets).Count | Should -Be 0 -Because $a.id
        }
        foreach ($a in $catalogo | Where-Object { $_.id -match '^(priv|sis)-' }) { ($a | ConvertTo-Json -Depth 5) | Should -Not -Match $seguranca -Because $a.id }
    }

    It 'tem TODOS os tweaks e apps do WinUtil (winutil-referencia.json), cada um com a chave original' {
        $temos = @($catalogo | ForEach-Object { if ($_.PSObject.Properties['winutil']) { @($_.winutil) } })
        foreach ($k in @($script:Referencia.tweaks) + @($script:Referencia.appx)) { $temos | Should -Contain $k -Because "o WinUtil tem $k" }
        foreach ($k in $temos | Select-Object -Unique) { @($script:Referencia.tweaks) + @($script:Referencia.appx) | Should -Contain $k -Because "chave $k não existe no WinUtil" }
    }

    It 'ajustes do Atlas OS dizem de onde vieram (arquivo do playbook e título original)' {
        $atlas = @($catalogo | Where-Object { $_.PSObject.Properties['atlas'] })
        $atlas.Count | Should -BeGreaterOrEqual 50
        foreach ($a in $atlas) {
            @($a.atlas)[0] | Should -Match '\.yml$' -Because $a.id
            $a.descricao | Should -Match '\(Atlas: .+\)$' -Because $a.id
        }
    }

    It 'os presets do WinUtil (Mínimo, Essencial = Standard, Avançado = Advanced, Remover apps = AppxDefault) estão inteiros nos nossos' {
        foreach ($p in $script:Referencia.presets.PSObject.Properties) {
            foreach ($k in @($p.Value)) {
                @($catalogo | Where-Object { $_.PSObject.Properties['winutil'] -and @($_.winutil) -contains $k -and @($_.presets) -contains $p.Name }).Count |
                    Should -BeGreaterThan 0 -Because "$k está no preset $($p.Name) do WinUtil"
            }
        }
    }

    It 'ações únicas: têm "executar" que compila, nenhuma mudança, e só o ponto de restauração vai primeiro' {
        $acoes = @($catalogo | Where-Object { $_.PSObject.Properties['acao'] })
        $acoes.Count | Should -BeGreaterOrEqual 4
        foreach ($a in $acoes) {
            $a.executar | Should -Not -BeNullOrEmpty -Because $a.id
            $a.PSObject.Properties.Name | Should -Not -Contain 'mudancas' -Because $a.id
            $erros = $null; $tokens = $null
            [void][Management.Automation.Language.Parser]::ParseInput($a.executar, [ref]$tokens, [ref]$erros)
            @($erros).Count | Should -Be 0 -Because $a.id
        }
        @($catalogo | Where-Object { $_.PSObject.Properties['primeiro'] } | ForEach-Object id) | Should -Be @('seg-ponto-restauracao')
        $catalogo[0].id | Should -Be 'seg-ponto-restauracao' -Because 'é o primeiro da página e define a ordem dos botões de preset'
    }

    It 'presets completos (clicar troca a seleção inteira): Mínimo ⊂ Essencial ⊂ Avançado e Desempenho; Notebook = Essencial sem localização + bateria' {
        $minimo = Get-IdsPreset 'Mínimo'; $essencial = Get-IdsPreset 'Essencial'
        foreach ($id in $minimo) { $essencial | Should -Contain $id -Because "$id está no Mínimo" }
        foreach ($p in 'Avançado', 'Desempenho') { $ids = Get-IdsPreset $p; foreach ($id in $essencial) { $ids | Should -Contain $id -Because "$id está no Essencial ($p)" } }
        $notebook = Get-IdsPreset 'Notebook'
        foreach ($id in $essencial | Where-Object { $_ -ne 'priv-localizacao' }) { $notebook | Should -Contain $id -Because "$id está no Essencial (Notebook)" }
        # Bastante coisa marcada: os presets são para usar, não de enfeite.
        $essencial.Count | Should -BeGreaterOrEqual 30
        (Get-IdsPreset 'Avançado').Count | Should -BeGreaterOrEqual 50
    }

    It 'Essencial é para qualquer um: risco baixo (fora o que o próprio WinUtil põe no Standard) e não tira apps do dia a dia' {
        $standard = @($script:Referencia.presets.'Essencial')
        foreach ($a in $catalogo | Where-Object { @($_.presets) -contains 'Essencial' }) {
            if ($a.risco -ne 'Baixo') { @($a.winutil | Where-Object { $_ -in $standard }).Count | Should -BeGreaterThan 0 -Because "$($a.id) é $($a.risco) e não vem do Standard" }
        }
        foreach ($p in 'Essencial', 'Notebook', 'Desempenho', 'Avançado') {
            $ids = Get-IdsPreset $p
            foreach ($app in 'app-windowscalculator', 'app-windowsalarms', 'app-windows-photos', 'app-windowsnotepad', 'app-paint', 'app-screensketch', 'app-windowscamera') {
                $ids | Should -Not -Contain $app -Because "$p não pode tirar $app"
            }
        }
        (Get-IdsPreset 'Desempenho') | Should -Not -Contain 'app-gamingapp' -Because 'quem joga usa o app Xbox'
    }

    It 'Mínimo só risco baixo; Notebook sem nada que gaste bateria nem mude o fuso automático' {
        foreach ($a in $catalogo | Where-Object { @($_.presets) -contains 'Mínimo' }) { $a.risco | Should -Be 'Baixo' -Because $a.id }
        foreach ($a in $catalogo | Where-Object { @($_.presets) -contains 'Notebook' }) { $a.risco | Should -BeIn 'Baixo', 'Medio' -Because $a.id }
        (Get-IdsPreset 'Notebook') | Should -Not -Contain 'priv-localizacao'
        foreach ($p in $script:Presets) { (Get-IdsPreset $p).Count | Should -BeGreaterOrEqual 2 -Because $p }
        # Notebook: nada que gaste bateria ou desligue a hibernação.
        (Get-IdsPreset 'Notebook') | Should -Not -Contain 'energia-desempenho-maximo'
        (Get-IdsPreset 'Notebook') | Should -Not -Contain 'energia-sem-hibernacao'
    }

    It 'escolhas exclusivas (IPv6, MPO, DNS): no máximo uma por preset; IPv6 em nenhum' {
        $grupos = @{
            IPv6 = @('avanc-ipv4-preferido', 'avanc-sem-teredo', 'avanc-sem-ipv6')
            MPO  = @('avanc-sem-mpo', 'avanc-sem-mpo-total')
            DNS  = @($catalogo | Where-Object id -like 'rede-dns-*' | ForEach-Object id)
        }
        foreach ($p in $script:Presets) {
            $ids = Get-IdsPreset $p
            foreach ($g in $grupos.Keys) { @($grupos[$g] | Where-Object { $_ -in $ids }).Count | Should -BeLessOrEqual 1 -Because "$p tem mais de um de $g" }
        }
        foreach ($id in $grupos.IPv6) { @(($catalogo | Where-Object id -eq $id).presets).Count | Should -Be 0 -Because $id }
    }
}

Describe 'Ida e volta de <Id>' -ForEach $ajustesCatalogo {
    # HKLM e HKU também vão para a chave de teste; "admin" é fingido para o motor deixar escrever lá.
    BeforeEach { Mock Test-TmdAdministrador -ModuleName Tamandua.Nucleo { $true } }

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

Describe 'Ajustes com serviços (serviços simulados por Mock)' {
    BeforeEach {
        $env:TAMANDUA_DADOS = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
        $global:TmdTesteServicos = @{ CscService = 'Manual'; MapsBroker = 'AutomaticDelayedStart'; StorSvc = 'Automatic'; SharedAccess = 'Manual' }
        Mock Test-TmdAdministrador -ModuleName Tamandua.Nucleo { $true }
        Mock Get-TmdServicoInicializacao -ModuleName Tamandua.Nucleo { $global:TmdTesteServicos[$Nome] }
        Mock Set-TmdServicoInicializacao -ModuleName Tamandua.Nucleo { $global:TmdTesteServicos[$Nome] = $Inicializacao }
    }
    AfterEach { Remove-Variable -Name TmdTesteServicos -Scope Global -ErrorAction SilentlyContinue }

    It 'serviços em manual: aplica só o que falta e desfazer volta cada um ao que era' {
        $a = $catalogo | Where-Object id -eq 'sis-servicos-manual'
        (Set-TmdAjuste -Ajuste $a).Status | Should -Be 'Feito'
        $global:TmdTesteServicos.CscService | Should -Be 'Disabled'
        $global:TmdTesteServicos.MapsBroker | Should -Be 'Manual'
        Get-TmdEstadoAjuste -Ajuste $a | Should -Be 'Aplicado'
        (Undo-TmdAjuste -Id 'sis-servicos-manual').Status | Should -Be 'Feito'
        $global:TmdTesteServicos.MapsBroker | Should -Be 'AutomaticDelayedStart'
        $global:TmdTesteServicos.StorSvc | Should -Be 'Automatic'
        Should -Invoke Set-TmdServicoInicializacao -ModuleName Tamandua.Nucleo -ParameterFilter { $Nome -eq 'SharedAccess' } -Times 0 -Exactly
    }

    It 'serviço que não existe nesta máquina conta como nada a fazer' {
        $global:TmdTesteServicos.Remove('CscService')
        (Set-TmdAjuste -Ajuste ($catalogo | Where-Object id -eq 'sis-servicos-manual')).Status | Should -Be 'Feito'
        $global:TmdTesteServicos.ContainsKey('CscService') | Should -BeFalse
    }
}

Describe 'Find-Alvos e Invoke-Acao' {
    BeforeEach {
        $env:TAMANDUA_DADOS = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
        $raiz = New-RaizRegistro
    }

    It 'na área de testes: só os ajustes que são só registro, nenhum pede admin, sem ponto de restauração' {
        $alvos = @(Find-Alvos -RaizRegistro $raiz)
        $alvos.Count | Should -Be $soRegistro.Count
        @($alvos | Where-Object RequerAdmin).Count | Should -Be 0
        $alvos.Id | Should -Not -Contain 'seg-ponto-restauracao'
    }

    It 'um alvo por ajuste, nada marcado, com estado, presets e o que muda' {
        $alvos = @(Find-Alvos -RaizRegistro $raiz)
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

    It 'ações vão pelo Invoke-TmdAcaoAjuste, e o ponto de restauração antes de tudo, em qualquer ordem que chegue' {
        Mock Invoke-TmdAcaoAjuste -ModuleName ajustes { [pscustomobject]@{ Id = $Ajuste.id; Status = 'Feito'; Liberado = [int64]0; Motivo = ''; Mudancas = @() } }
        $r = @(Invoke-Acao -RaizRegistro '' -Alvos @([pscustomobject]@{ Id = 'formatar-disco' }, [pscustomobject]@{ Id = 'acao-limpar-temporarios' }, [pscustomobject]@{ Id = 'seg-ponto-restauracao' }))
        ($r | ForEach-Object Id) -join ',' | Should -Be 'seg-ponto-restauracao,formatar-disco,acao-limpar-temporarios'
        Should -Invoke Invoke-TmdAcaoAjuste -ModuleName ajustes -Times 2 -Exactly
    }

    It 'na área de testes nenhuma ação aparece nem roda' {
        @(Find-Alvos -RaizRegistro $raiz | Where-Object { $_.Id -like 'acao-*' -or $_.Id -eq 'seg-ponto-restauracao' }).Count | Should -Be 0
        (Invoke-Acao -RaizRegistro $raiz -Alvos @([pscustomobject]@{ Id = 'acao-limpar-temporarios' })).Status | Should -Be 'Erro'
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
        $essencial = @($soRegistro | Where-Object { @($_.presets) -contains 'Essencial' })
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
        (Invoke-Tamandua -Raiz $projeto -Argumentos 'ajustes', '-Preset', 'Turbo' -Ambiente $ambiente).Saida | Should -Match 'Disponíveis: .*Essencial.*Notebook'
        (Invoke-Tamandua -Raiz $projeto -Argumentos 'ajustes', '-Itens', 'nada' -Ambiente $ambiente).Codigo | Should -Be 1
        (Invoke-Tamandua -Raiz $projeto -Argumentos 'modulos', '-Preset', 'Essencial').Codigo | Should -Be 1
    }
}
