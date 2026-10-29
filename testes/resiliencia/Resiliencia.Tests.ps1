# Roda o programa de verdade (processo separado) com partes faltando ou quebradas.

BeforeAll {
    . (Join-Path $PSScriptRoot '..\Ajudantes.ps1')
    $nomesCatalogo = @((Import-PowerShellDataFile (Join-Path $script:RaizProjeto 'nucleo\catalogo.psd1')).Modulos |
            ForEach-Object { $_['Nome'] })
}

Describe 'Programa sem nenhum módulo' {
    BeforeAll {
        $raiz = New-ProjetoFalso -Pai $TestDrive
    }

    It 'tamandua modulos funciona e mostra todos os módulos como faltando' {
        $r = Invoke-Tamandua -Raiz $raiz -Argumentos 'modulos'
        $r.Codigo | Should -Be 0
        foreach ($nome in $nomesCatalogo) {
            $r.Saida | Should -Match "$nome\s+faltando"
        }
        $r.Saida | Should -Match "0 de $($nomesCatalogo.Count) módulos disponíveis"
    }

    It 'sem interface, abre o menu de texto em vez de falhar' {
        $r = Invoke-Tamandua -Raiz $raiz
        $r.Codigo | Should -Be 0
        $r.Saida | Should -Match 'Interface gráfica indisponível: pasta interface não encontrada'
        $r.Saida | Should -Match 'menu de texto'
    }

    It 'comando de módulo faltando sai com código 2 e explica, sem stack trace' {
        $r = Invoke-Tamandua -Raiz $raiz -Argumentos 'limpar'
        $r.Codigo | Should -Be 2
        $r.Saida | Should -Match "módulo 'limpar' está faltando"
        $r.Tudo | Should -Not -Match 'At line|CategoryInfo|FullyQualifiedErrorId'
    }

    It 'comando desconhecido sai com código 1 e mostra a ajuda' {
        $r = Invoke-Tamandua -Raiz $raiz -Argumentos 'voar'
        $r.Codigo | Should -Be 1
        $r.Saida | Should -Match 'Comando desconhecido: voar'
        $r.Saida | Should -Match 'Uso: tamandua'
    }

    It 'ajuda e versao funcionam' {
        (Invoke-Tamandua -Raiz $raiz -Argumentos 'ajuda').Codigo | Should -Be 0
        (Invoke-Tamandua -Raiz $raiz -Argumentos 'versao').Saida | Should -Match 'Tamanduá \d+\.\d+\.\d+'
    }

    It 'opção ainda não suportada sai com código 1, sem fazer nada' {
        $r = Invoke-Tamandua -Raiz $raiz -Argumentos 'modulos', 'extra'
        $r.Codigo | Should -Be 1
        $r.Saida | Should -Match 'Opções ainda não suportadas'
    }
}

Describe 'Programa com módulos bons e ruins misturados' {
    BeforeAll {
        $raiz = New-ProjetoFalso -Pai $TestDrive -Catalogo 'bom', 'explode', 'semrequisito'
        New-ModuloFalso -Raiz $raiz -Nome 'bom' -Codigo @'
function Test-Requisitos { @{ Ok = $true; Motivo = '' } }
function Find-Alvos { [pscustomobject]@{ Id = 'item-um'; Nome = 'Item um' } }
'@ | Out-Null
        New-ModuloFalso -Raiz $raiz -Nome 'explode' -Codigo "throw 'bum'" | Out-Null
        New-ModuloFalso -Raiz $raiz -Nome 'semrequisito' -Codigo @'
function Test-Requisitos { @{ Ok = $false; Motivo = 'precisa de algo' } }
function Find-Alvos { @() }
'@ | Out-Null
    }

    It 'lista cada um com o estado certo' {
        $r = Invoke-Tamandua -Raiz $raiz -Argumentos 'modulos'
        $r.Codigo | Should -Be 0
        $r.Saida | Should -Match 'bom\s+ok'
        $r.Saida | Should -Match 'explode\s+quebrado\s+erro ao carregar: bum'
        $r.Saida | Should -Match 'semrequisito\s+indisponível\s+precisa de algo'
        $r.Saida | Should -Match '1 de 3 módulos disponíveis'
    }

    It 'o módulo bom roda mesmo com os outros quebrados' {
        $r = Invoke-Tamandua -Raiz $raiz -Argumentos 'bom'
        $r.Codigo | Should -Be 0
        $r.Saida | Should -Match 'item-um'
    }

    It 'módulo indisponível sai com código 2' {
        (Invoke-Tamandua -Raiz $raiz -Argumentos 'semrequisito').Codigo | Should -Be 2
    }

    It 'módulo cujo Find-Alvos falha sai com código 1, sem stack trace' {
        New-ModuloFalso -Raiz $raiz -Nome 'falhaalvos' -Codigo @'
function Test-Requisitos { @{ Ok = $true } }
function Find-Alvos { throw 'disco sumiu' }
'@ | Out-Null
        $r = Invoke-Tamandua -Raiz $raiz -Argumentos 'falhaalvos'
        $r.Codigo | Should -Be 1
        $r.Saida | Should -Match "módulo 'falhaalvos' falhou: disco sumiu"
        $r.Tudo | Should -Not -Match 'At line|CategoryInfo'
    }
}

Describe 'Partes do programa corrompidas' {
    It 'catálogo corrompido: avisa e continua com os módulos extras' {
        $raiz = New-ProjetoFalso -Pai $TestDrive
        Set-Content -LiteralPath (Join-Path $raiz 'nucleo\catalogo.psd1') -Value 'isso não é psd1 {' -Encoding UTF8
        New-ModuloFalso -Raiz $raiz -Nome 'extra' | Out-Null
        $r = Invoke-Tamandua -Raiz $raiz -Argumentos 'modulos'
        $r.Codigo | Should -Be 0
        $r.Tudo | Should -Match 'catálogo inválido'
        $r.Saida | Should -Match 'extra\s+ok'
    }

    It 'interface quebrada: cai para o menu de texto com o motivo' {
        $raiz = New-ProjetoFalso -Pai $TestDrive
        New-Item -ItemType Directory -Path (Join-Path $raiz 'interface') | Out-Null
        Set-Content -LiteralPath (Join-Path $raiz 'interface\Interface.psm1') -Value "throw 'xaml corrompido'" -Encoding UTF8
        $r = Invoke-Tamandua -Raiz $raiz
        $r.Codigo | Should -Be 0
        $r.Saida | Should -Match 'Interface gráfica indisponível: erro ao abrir: xaml corrompido'
        $r.Saida | Should -Match 'menu de texto'
    }

    It 'sem o núcleo: explica e sai com código 1' {
        $raiz = New-ProjetoFalso -Pai $TestDrive
        Remove-Item -LiteralPath (Join-Path $raiz 'nucleo') -Recurse -Force
        $r = Invoke-Tamandua -Raiz $raiz -Argumentos 'modulos'
        $r.Codigo | Should -Be 1
        $r.Erro | Should -Match 'núcleo não encontrado'
    }
}
