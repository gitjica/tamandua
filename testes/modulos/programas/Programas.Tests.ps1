# Módulo programas. O winget é sempre simulado (Mock de Invoke-Winget): nenhum teste instala ou atualiza nada de verdade.
# Só o teste de linha de comando lê o winget real, e com -Simular.

BeforeAll {
    . (Join-Path $PSScriptRoot '..\..\Ajudantes.ps1')
    Import-Module (Join-Path $script:RaizProjeto 'nucleo\Tamandua.Nucleo.psm1') -Force -DisableNameChecking -Global
    Import-Module (Join-Path $script:RaizProjeto 'modulos\programas\programas.psm1') -Force -DisableNameChecking
    $catalogo = @(InModuleScope programas { Get-CatalogoProgramas })

    # Saída real do "winget upgrade" em português (com uma linha de programa fora do catálogo).
    $script:TabelaUpgrade = @(
        'Nome                                     Id                                 Versão        Disponível'
        '---------------------------------------------------------------------------------------------------'
        'Microsoft Windows Desktop Runtime 10.0   Microsoft.DotNet.DesktopRuntime.10 10.0.10       10.0.14'
        'Obsidian                                 Obsidian.Obsidian                  1.14.4        1.14.5'
        '2 atualizações disponíveis.'
    )

    function Set-WingetFalso {
        param([string[]]$Instalados, [int]$Codigo = 0)
        $global:TmdTesteInstalados = $Instalados
        $global:TmdTesteUpgrade = $script:TabelaUpgrade
        $global:TmdTesteCodigo = $Codigo
        $global:TmdTesteChamadas = [System.Collections.Generic.List[string]]::new()
        Mock Invoke-Winget -ModuleName programas {
            $comando = $Argumentos -join ' '
            if ($Argumentos[0] -eq 'export') {
                $pacotes = @($global:TmdTesteInstalados | ForEach-Object { @{ PackageIdentifier = $_ } })
                @{ Sources = @(@{ Packages = $pacotes }) } | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $Argumentos[2] -Encoding UTF8
                return [pscustomobject]@{ Codigo = 0; Saida = @() }
            }
            if ($Argumentos[0] -eq 'upgrade' -and $Argumentos -notcontains '--id' -and $Argumentos -notcontains '--all') {
                return [pscustomobject]@{ Codigo = 0; Saida = $global:TmdTesteUpgrade }
            }
            $global:TmdTesteChamadas.Add($comando)
            [pscustomobject]@{ Codigo = $global:TmdTesteCodigo; Saida = @('Baixando...', 'Falha no instalador') }
        }
    }
}

AfterAll {
    Remove-Variable -Name TmdTesteInstalados, TmdTesteUpgrade, TmdTesteCodigo, TmdTesteChamadas -Scope Global -ErrorAction SilentlyContinue
}

Describe 'Catálogo' {
    It 'ids únicos, ID do winget no formato Editor.Programa, categoria e "livre"' {
        @($catalogo | ForEach-Object id | Select-Object -Unique).Count | Should -Be $catalogo.Count
        foreach ($p in $catalogo) {
            $p.id | Should -MatchExactly '^[a-z0-9-]+$'
            $p.wingetId | Should -Match '^[\w+-]+(\.[\w+-]+)+$' -Because $p.id
            $p.nome | Should -Not -BeNullOrEmpty
            $p.categoria | Should -Not -BeNullOrEmpty
            $p.livre | Should -BeOfType [bool]
        }
    }
}

Describe 'Find-Alvos' {
    BeforeEach { Set-WingetFalso -Instalados 'Mozilla.Firefox', 'Obsidian.Obsidian', 'Microsoft.DotNet.DesktopRuntime.10' }

    It 'mostra instalado, com atualização e não instalado; nada vem marcado' {
        $alvos = @(Find-Alvos)
        ($alvos | Where-Object Id -eq 'firefox').Estado | Should -Be 'Aplicado'
        ($alvos | Where-Object Id -eq 'firefox').Selo | Should -Be 'instalado'
        ($alvos | Where-Object Id -eq 'obsidian').Estado | Should -Be 'Parcial'
        ($alvos | Where-Object Id -eq 'obsidian').Selo | Should -Be 'atualizar para 1.14.5'
        ($alvos | Where-Object Id -eq 'vlc').Selo | Should -Be 'não instalado'
        ($alvos | Where-Object Id -eq 'vlc').Mudancas[0] | Should -Be 'winget install --id VideoLAN.VLC --exact --source winget'
        @($alvos | Where-Object Selecionado).Count | Should -Be 0
    }

    It '"Atualizar tudo" lista todas as atualizações, inclusive de fora do catálogo' {
        $tudo = @(Find-Alvos) | Where-Object Id -eq 'atualizar-tudo'
        $tudo.Nome | Should -Be 'Atualizar tudo (2)'
        $tudo.Detalhe | Should -Be 'Microsoft.DotNet.DesktopRuntime.10, Obsidian.Obsidian'
    }

    It 'sem atualizações, não há "Atualizar tudo"' {
        $global:TmdTesteUpgrade = @('Nenhum pacote instalado encontrado com atualização disponível.')
        @(Find-Alvos | Where-Object Id -eq 'atualizar-tudo').Count | Should -Be 0
    }
}

Describe 'Invoke-Acao' {
    BeforeEach {
        $env:TAMANDUA_DADOS = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
        Set-WingetFalso -Instalados 'Mozilla.Firefox', 'Obsidian.Obsidian'
    }

    It 'instala o que não está, atualiza o que tem atualização, não mexe no que está em dia' {
        $r = @(Invoke-Acao -Alvos @(
                [pscustomobject]@{ Id = 'vlc' }
                [pscustomobject]@{ Id = 'obsidian' }
                [pscustomobject]@{ Id = 'firefox' }
            ))
        @($r | ForEach-Object Status | Select-Object -Unique) | Should -Be 'Feito'
        ($r | Where-Object Id -eq 'firefox').Motivo | Should -Be 'já instalado e atualizado'
        $global:TmdTesteChamadas.Count | Should -Be 2
        $global:TmdTesteChamadas[0] | Should -Match '^install --id VideoLAN\.VLC --exact --source winget --silent .*--accept-package-agreements'
        $global:TmdTesteChamadas[1] | Should -Match '^upgrade --id Obsidian\.Obsidian --exact --source winget'
    }

    It 'o que fazer vem do catálogo, não do alvo; fora do catálogo é erro' {
        $r = @(Invoke-Acao -Alvos @(
                [pscustomobject]@{ Id = 'vlc'; Mudancas = @('winget install malware') }
                [pscustomobject]@{ Id = 'Malware.Inc' }
            ))
        $global:TmdTesteChamadas[0] | Should -Match 'VideoLAN\.VLC'
        ($r | Where-Object Id -eq 'Malware.Inc').Status | Should -Be 'Erro'
        $global:TmdTesteChamadas.Count | Should -Be 1
    }

    It '"Atualizar tudo" chama winget upgrade --all' {
        Invoke-Acao -Alvos @([pscustomobject]@{ Id = 'atualizar-tudo' }) | Out-Null
        $global:TmdTesteChamadas[0] | Should -Match '^upgrade --all --source winget'
    }

    It '-Simular não chama o winget para instalar e descreve o comando' {
        $r = Invoke-Acao -Alvos @([pscustomobject]@{ Id = 'vlc' }) -Simular
        $r.Status | Should -Be 'Simulado'
        $r.Mudancas[0] | Should -Match '^winget install --id VideoLAN\.VLC'
        $global:TmdTesteChamadas.Count | Should -Be 0
    }

    It 'código de "nenhuma atualização" é sucesso; outros códigos são erro com a última linha do winget' {
        $global:TmdTesteCodigo = -1978335189
        (Invoke-Acao -Alvos @([pscustomobject]@{ Id = 'obsidian' })).Motivo | Should -Be 'já estava atualizado'
        $global:TmdTesteCodigo = 1603
        $r = Invoke-Acao -Alvos @([pscustomobject]@{ Id = 'vlc' })
        $r.Status | Should -Be 'Erro'
        $r.Motivo | Should -Match 'código 1603: Falha no instalador'
    }

    It 'cada programa vai para o log' {
        Invoke-Acao -Alvos @([pscustomobject]@{ Id = 'vlc' }) | Out-Null
        $h = @(Get-TmdHistorico -Ultimos 1)[0]
        $h.Modulo | Should -Be 'programas'
        $h.Caminho | Should -Be 'VLC'
    }
}

Describe 'Requisitos' {
    It 'sem winget: indisponível, dizendo onde conseguir' {
        Mock Get-Command -ModuleName programas { $null }
        $r = InModuleScope programas { Test-Requisitos }
        $r.Ok | Should -BeFalse
        $r.Motivo | Should -Match 'Microsoft Store'
    }
}

Describe 'Pela linha de comando (winget real, só lendo)' {
    It 'lista o catálogo com o estado real e simula sem instalar' -Skip:(-not (Get-Command winget -ErrorAction SilentlyContinue)) {
        $projeto = New-ProjetoFalso -Pai $TestDrive -ModulosReais 'programas'
        $r = Invoke-Tamandua -Raiz $projeto -Argumentos 'programas', '-Itens', 'vlc', '-Simular'
        $r.Codigo | Should -Be 0
        $r.Saida | Should -Match 'Navegadores'
        $r.Saida | Should -Match 'Simulação'
        $r.Saida | Should -Match 'licenças' -Because 'o aviso do módulo só aparece na confirmação de verdade' -Not
    }
}
