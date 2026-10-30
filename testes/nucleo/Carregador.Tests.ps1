BeforeAll {
    . (Join-Path $PSScriptRoot '..\Ajudantes.ps1')
    Import-Module (Join-Path $script:RaizProjeto 'nucleo\Tamandua.Nucleo.psm1') -Force -DisableNameChecking
}

Describe 'Catálogo real' {
    It 'lista os 11 módulos do guia, sem nomes repetidos' {
        $catalogo = Get-TmdCatalogo -Raiz $script:RaizProjeto
        $catalogo.Erro | Should -BeNullOrEmpty
        $nomes = @($catalogo.Modulos | ForEach-Object { $_['Nome'] })
        $nomes.Count | Should -Be 11
        @($nomes | Select-Object -Unique).Count | Should -Be 11
    }

    It 'toda entrada tem Titulo, Grupo e Descricao' {
        foreach ($m in (Get-TmdCatalogo -Raiz $script:RaizProjeto).Modulos) {
            $m['Titulo'] | Should -Not -BeNullOrEmpty
            $m['Grupo'] | Should -Not -BeNullOrEmpty
            $m['Descricao'] | Should -Not -BeNullOrEmpty
        }
    }
}

Describe 'Get-TmdModulo' {
    BeforeEach {
        $raiz = New-ProjetoFalso -Pai $TestDrive -Catalogo 'alfa', 'beta'
    }

    It 'reaproveita o módulo já importado; importa de novo quando um arquivo da pasta muda' {
        $pasta = New-ModuloFalso -Raiz $raiz -Nome 'alfa'
        $primeiro = (Get-TmdModulo -Raiz $raiz -Nome 'alfa').Modulo
        (Get-TmdModulo -Raiz $raiz -Nome 'alfa').Modulo | Should -Be $primeiro
        $codigo = Get-ChildItem -LiteralPath $pasta -Filter '*.psm1' | Select-Object -First 1
        Add-Content -LiteralPath $codigo.FullName -Value '# mudou'
        (Get-TmdModulo -Raiz $raiz -Nome 'alfa').Modulo | Should -Not -Be $primeiro
    }

    It '-SemRequisitos pula o Test-Requisitos (a janela já conferiu)' {
        New-ModuloFalso -Raiz $raiz -Nome 'alfa' -Codigo @'
function Test-Requisitos { @{ Ok = $false; Motivo = 'não dá' } }
function Find-Alvos { }
'@ | Out-Null
        (Get-TmdModulo -Raiz $raiz -Nome 'alfa').Estado | Should -Be 'indisponivel'
        (Get-TmdModulo -Raiz $raiz -Nome 'alfa' -SemRequisitos).Estado | Should -Be 'ok'
    }

    It 'marca como faltando o módulo do catálogo sem pasta' {
        $m = Get-TmdModulo -Raiz $raiz -Nome 'alfa'
        $m.Estado | Should -Be 'faltando'
        $m.Motivo | Should -Match 'pasta modulos\\alfa não encontrada'
    }

    It 'marca como faltando quando não há modulo.psd1' {
        New-ModuloFalso -Raiz $raiz -Nome 'alfa' -SemManifesto | Out-Null
        $m = Get-TmdModulo -Raiz $raiz -Nome 'alfa'
        $m.Estado | Should -Be 'faltando'
        $m.Motivo | Should -Match 'modulo.psd1'
    }

    It 'marca como faltando quando o .psm1 do manifesto não existe' {
        New-ModuloFalso -Raiz $raiz -Nome 'alfa' -SemCodigo | Out-Null
        $m = Get-TmdModulo -Raiz $raiz -Nome 'alfa'
        $m.Estado | Should -Be 'faltando'
        $m.Motivo | Should -Match 'alfa.psm1 não encontrado'
    }

    It 'marca como quebrado um manifesto com sintaxe inválida' {
        New-ModuloFalso -Raiz $raiz -Nome 'alfa' -ManifestoBruto '@{ Nome = ' | Out-Null
        $m = Get-TmdModulo -Raiz $raiz -Nome 'alfa'
        $m.Estado | Should -Be 'quebrado'
        $m.Motivo | Should -Match 'manifesto inválido'
    }

    It 'marca como quebrado um manifesto sem o campo <Campo>' -ForEach @(
        @{ Campo = 'Nome' }, @{ Campo = 'Versao' }, @{ Campo = 'Descricao' }, @{ Campo = 'Arquivo' }
        @{ Campo = 'Escreve' }, @{ Campo = 'RequerAdmin' }, @{ Campo = 'ContratoMinimo' }
    ) {
        New-ModuloFalso -Raiz $raiz -Nome 'alfa' -Manifesto @{ $Campo = $null } | Out-Null
        $m = Get-TmdModulo -Raiz $raiz -Nome 'alfa'
        $m.Estado | Should -Be 'quebrado'
        $m.Motivo | Should -Match "falta o campo $Campo"
    }

    It 'marca como quebrado um campo com tipo errado' {
        New-ModuloFalso -Raiz $raiz -Nome 'alfa' -Manifesto @{ Escreve = 'sim' } | Out-Null
        (Get-TmdModulo -Raiz $raiz -Nome 'alfa').Motivo | Should -Match 'Escreve deveria ser Boolean'
    }

    It 'marca como quebrado quando Nome difere da pasta' {
        New-ModuloFalso -Raiz $raiz -Nome 'alfa' -Manifesto @{ Nome = 'outro' } | Out-Null
        (Get-TmdModulo -Raiz $raiz -Nome 'alfa').Motivo | Should -Match "diferente da pasta"
    }

    It 'marca como quebrado quando exige contrato mais novo que o núcleo' {
        New-ModuloFalso -Raiz $raiz -Nome 'alfa' -Manifesto @{ ContratoMinimo = 99 } | Out-Null
        (Get-TmdModulo -Raiz $raiz -Nome 'alfa').Motivo | Should -Match 'exige o contrato 99'
    }

    It 'recusa Arquivo que aponta para fora da pasta do módulo' {
        New-ModuloFalso -Raiz $raiz -Nome 'alfa' -Manifesto @{ Arquivo = '..\fora.psm1' } -SemCodigo | Out-Null
        $m = Get-TmdModulo -Raiz $raiz -Nome 'alfa'
        $m.Estado | Should -Be 'quebrado'
        $m.Motivo | Should -Match 'dentro da pasta do módulo'
    }

    It 'marca como quebrado o módulo que lança exceção ao carregar, e carrega os outros' {
        New-ModuloFalso -Raiz $raiz -Nome 'alfa' -Codigo "throw 'explodiu no import'" | Out-Null
        New-ModuloFalso -Raiz $raiz -Nome 'beta' | Out-Null
        $todos = @(Get-TmdModulo -Raiz $raiz)
        ($todos | Where-Object Nome -eq 'alfa').Estado | Should -Be 'quebrado'
        ($todos | Where-Object Nome -eq 'alfa').Motivo | Should -Match 'explodiu no import'
        ($todos | Where-Object Nome -eq 'beta').Estado | Should -Be 'ok'
    }

    It 'marca como quebrado quando falta Find-Alvos' {
        New-ModuloFalso -Raiz $raiz -Nome 'alfa' -Codigo 'function Test-Requisitos { @{ Ok = $true } }' | Out-Null
        (Get-TmdModulo -Raiz $raiz -Nome 'alfa').Motivo | Should -Match 'falta a função Find-Alvos'
    }

    It 'exige Invoke-Acao de módulo que escreve' {
        New-ModuloFalso -Raiz $raiz -Nome 'alfa' -Manifesto @{ Escreve = $true } | Out-Null
        (Get-TmdModulo -Raiz $raiz -Nome 'alfa').Motivo | Should -Match 'falta a função Invoke-Acao'
    }

    It 'marca como indisponível quando Test-Requisitos diz que não dá, com o motivo dele' {
        New-ModuloFalso -Raiz $raiz -Nome 'alfa' -Codigo @'
function Test-Requisitos { [pscustomobject]@{ Ok = $false; Motivo = 'winget não encontrado' } }
function Find-Alvos { @() }
'@ | Out-Null
        $m = Get-TmdModulo -Raiz $raiz -Nome 'alfa'
        $m.Estado | Should -Be 'indisponivel'
        $m.Motivo | Should -Be 'winget não encontrado'
    }

    It 'marca como indisponível quando Test-Requisitos lança exceção' {
        New-ModuloFalso -Raiz $raiz -Nome 'alfa' -Codigo @'
function Test-Requisitos { throw 'sem acesso ao CIM' }
function Find-Alvos { @() }
'@ | Out-Null
        $m = Get-TmdModulo -Raiz $raiz -Nome 'alfa'
        $m.Estado | Should -Be 'indisponivel'
        $m.Motivo | Should -Match 'sem acesso ao CIM'
    }

    It 'marca como indisponível quando Test-Requisitos trava, sem travar o carregador' {
        New-ModuloFalso -Raiz $raiz -Nome 'alfa' -Codigo @'
function Test-Requisitos { Start-Sleep -Seconds 60; @{ Ok = $true } }
function Find-Alvos { @() }
'@ | Out-Null
        New-ModuloFalso -Raiz $raiz -Nome 'beta' | Out-Null
        $tempo = Measure-Command { $todos = @(Get-TmdModulo -Raiz $raiz -TimeoutRequisitosSeg 1) }
        $tempo.TotalSeconds | Should -BeLessThan 10
        ($todos | Where-Object Nome -eq 'alfa').Estado | Should -Be 'indisponivel'
        ($todos | Where-Object Nome -eq 'alfa').Motivo | Should -Match 'não respondeu'
        ($todos | Where-Object Nome -eq 'beta').Estado | Should -Be 'ok'
    }

    It 'marca como quebrado quando Test-Requisitos devolve formato errado' {
        New-ModuloFalso -Raiz $raiz -Nome 'alfa' -Codigo @'
function Test-Requisitos { 'tudo certo' }
function Find-Alvos { @() }
'@ | Out-Null
        (Get-TmdModulo -Raiz $raiz -Nome 'alfa').Estado | Should -Be 'quebrado'
    }

    It 'carrega um módulo válido como ok, com o módulo pronto para uso' {
        New-ModuloFalso -Raiz $raiz -Nome 'alfa' | Out-Null
        $m = Get-TmdModulo -Raiz $raiz -Nome 'alfa'
        $m.Estado | Should -Be 'ok'
        $m.Modulo.ExportedFunctions.Keys | Should -Contain 'Find-Alvos'
    }

    It 'carrega pasta fora do catálogo como módulo extra' {
        New-ModuloFalso -Raiz $raiz -Nome 'gama' | Out-Null
        $m = Get-TmdModulo -Raiz $raiz -Nome 'gama'
        $m.Estado | Should -Be 'ok'
        $m.Grupo | Should -Be 'Extras'
        $m.NoCatalogo | Should -BeFalse
        $m.Descricao | Should -Be 'Módulo falso gama'
        $m.Titulo | Should -Be 'Gama'
    }

    It 'continua funcionando com catálogo corrompido, avisando' {
        Set-Content -LiteralPath (Join-Path $raiz 'nucleo\catalogo.psd1') -Value '@{ Modulos = ' -Encoding UTF8
        New-ModuloFalso -Raiz $raiz -Nome 'gama' | Out-Null
        $todos = @(Get-TmdModulo -Raiz $raiz -WarningVariable avisos -WarningAction SilentlyContinue)
        $avisos | Should -Match 'catálogo inválido'
        $todos.Count | Should -Be 1
        $todos[0].Estado | Should -Be 'ok'
    }

    It 'devolve nada para um nome que não existe' {
        Get-TmdModulo -Raiz $raiz -Nome 'zeta' | Should -BeNullOrEmpty
    }
}
