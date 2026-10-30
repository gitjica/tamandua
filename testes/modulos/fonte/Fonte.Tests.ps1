# Módulo fonte. O registro é falso (HKCU:\Software\TamanduaTestes) e a pasta de fontes também (cópias da Segoe UI e da
# Arial no TestDrive): nenhuma fonte do Windows é tocada. As fontes de verdade só são lidas, para servir de modelo.

BeforeAll {
    . (Join-Path $PSScriptRoot '..\..\Ajudantes.ps1')
    Import-Module (Join-Path $script:RaizProjeto 'nucleo\Tamandua.Nucleo.psm1') -Force -DisableNameChecking -Global
    Import-Module (Join-Path $script:RaizProjeto 'modulos\fonte\fonte.psm1') -Force -DisableNameChecking
    $script:ChaveTestes = "HKCU:\Software\TamanduaTestes\fonte-$([guid]::NewGuid().ToString('N'))"
    $script:Windows = Join-Path $env:WINDIR 'Fonts'

    # Pasta de fontes falsa com 3 arquivos da Segoe UI e a Arial (Regular, Bold, Italic), registrados como no Windows.
    function New-WindowsFalso {
        $raiz = "$script:ChaveTestes\$([guid]::NewGuid().ToString('N'))"
        $pasta = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
        [void][IO.Directory]::CreateDirectory($pasta)
        $chave = "$raiz\HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Fonts"
        New-Item -Path $chave -Force | Out-Null
        $arquivos = [ordered]@{
            'Segoe UI (TrueType)' = 'segoeui.ttf'; 'Segoe UI Bold (TrueType)' = 'segoeuib.ttf'; 'Segoe UI Variable (TrueType)' = 'SegUIVar.ttf'
            'Arial (TrueType)' = 'arial.ttf'; 'Arial Bold (TrueType)' = 'arialbd.ttf'; 'Arial Italic (TrueType)' = 'ariali.ttf'
            # Só negrito: não pode ocupar a Regular, fica de fora da lista.
            'Verdana Bold (TrueType)' = 'verdanab.ttf'
        }
        foreach ($n in $arquivos.Keys) {
            [IO.File]::Copy((Join-Path $script:Windows $arquivos[$n]), (Join-Path $pasta $arquivos[$n]))
            New-ItemProperty -LiteralPath $chave -Name $n -Value $arquivos[$n] -PropertyType String -Force | Out-Null
        }
        $env:TAMANDUA_REGISTRO_TESTE = $raiz
        $env:TAMANDUA_FONTES_TESTE = $pasta
        [pscustomobject]@{ Raiz = $raiz; Pasta = $pasta; Chave = $chave }
    }
    function Get-ValorFonte([string]$Chave, [string]$Nome) { (Get-ItemProperty -LiteralPath $Chave).$Nome }
    function Get-NomeInterno([string]$Arquivo) { Initialize-TmdFontKit; ([Sfnt]::Load($Arquivo)).Name(1) }
}

AfterAll {
    Remove-Item Env:\TAMANDUA_REGISTRO_TESTE, Env:\TAMANDUA_FONTES_TESTE -ErrorAction SilentlyContinue
    if (Test-Path -LiteralPath $script:ChaveTestes) { Remove-Item -LiteralPath $script:ChaveTestes -Recurse -Force }
    $mae = 'HKCU:\Software\TamanduaTestes'
    if ((Test-Path -LiteralPath $mae) -and @(Get-ChildItem -LiteralPath $mae).Count -eq 0) { Remove-Item -LiteralPath $mae -Force }
}

Describe 'Nomes e pesos' {
    It 'família e estilo pelo nome do registro, inclusive com hífen e CamelCase' {
        InModuleScope fonte {
            $casos = @{
                'Inter Semi Bold Italic (TrueType)' = 'Inter|Semi Bold Italic'
                'Rubik-BoldItalic (TrueType)'       = 'Rubik|Bold Italic'
                'Arial Black (TrueType)'            = 'Arial|Black'
                'Black Ops One (TrueType)'          = 'Black Ops One|Regular'
                'Noto Sans (OpenType)'              = 'Noto Sans|Regular'
            }
            foreach ($c in $casos.Keys) {
                $n = Get-NomeFamilia -NomeRegistro $c
                "$($n.Familia)|$($n.Estilo)" | Should -Be $casos[$c] -Because $c
            }
        }
    }

    It 'cada vaga da Segoe UI fica com o peso mais parecido, com itálico só se a família tiver' {
        InModuleScope fonte {
            $e = @(
                [pscustomobject]@{ Arquivo = 'R'; Peso = 400; Largura = 5; Italico = $false }
                [pscustomobject]@{ Arquivo = 'B'; Peso = 700; Largura = 5; Italico = $false }
                [pscustomobject]@{ Arquivo = 'I'; Peso = 400; Largura = 5; Italico = $true }
                [pscustomobject]@{ Arquivo = 'Rc'; Peso = 400; Largura = 3; Italico = $false }
            )
            (Select-ArquivoVaga -Estilos $e -Peso 400 -Italico $false).Arquivo | Should -Be 'R' -Because 'condensada nunca no lugar da Regular'
            (Select-ArquivoVaga -Estilos $e -Peso 300 -Italico $false).Arquivo | Should -Be 'R'
            (Select-ArquivoVaga -Estilos $e -Peso 600 -Italico $false).Arquivo | Should -Be 'B'
            (Select-ArquivoVaga -Estilos $e -Peso 900 -Italico $false).Arquivo | Should -Be 'B'
            (Select-ArquivoVaga -Estilos $e -Peso 700 -Italico $true).Arquivo | Should -Be 'I' -Because 'itálico certo vem antes do peso'
            (Select-ArquivoVaga -Estilos @($e[0], $e[1]) -Peso 400 -Italico $true).Arquivo | Should -Be 'R' -Because 'sem itálico, usa a reta'
        }
    }
}

Describe 'Fonte do sistema' {
    BeforeEach {
        $env:TAMANDUA_DADOS = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
        Mock Test-TmdAdministrador -ModuleName Tamandua.Nucleo { $true }
        $script:W = New-WindowsFalso
    }

    It 'lista as famílias instaladas (sem a Segoe) e diz que a Segoe UI original está em uso' {
        $alvos = @(Find-Alvos)
        $arial = $alvos | Where-Object Id -eq 'fam-arial'
        $arial.Nome | Should -Be 'Arial'
        $arial.Detalhe | Should -Be 'Regular, Bold, Italic'
        @($alvos | Where-Object { $_.Nome -like 'Segoe*' -and $_.Categoria -eq 'Fontes instaladas' }).Count | Should -Be 0
        @($alvos | Where-Object Id -eq 'fam-verdana').Count | Should -Be 0 -Because 'só tem negrito'
        ($alvos | Where-Object Id -eq 'segoe-original').Estado | Should -Be 'Aplicado'
        ($alvos | Where-Object Id -eq 'limpar-copias').Selecionavel | Should -BeFalse
        @($alvos | Where-Object Categoria -eq 'Tamanho do texto').Count | Should -Be 6
    }

    It 'simular não gera, não copia e não muda o registro' {
        $r = @(Invoke-Acao -Alvos @([pscustomobject]@{ Id = 'fam-arial' }) -Simular)
        $r[0].Status | Should -Be 'Simulado'
        $r[0].Mudancas -join "`n" | Should -Match 'Segoe UI Bold \(TrueType\) ← arialbd\.ttf'
        Get-ValorFonte $W.Chave 'Segoe UI (TrueType)' | Should -Be 'segoeui.ttf'
        @(Get-ChildItem -LiteralPath $W.Pasta -Filter '*_*').Count | Should -Be 0
    }

    It 'aplica: cópias com o nome da Segoe UI, registro apontado, tamanho escolhido; desfazer e limpar voltam tudo' {
        $r = @(Invoke-Acao -Alvos @([pscustomobject]@{ Id = 'fam-arial' }, [pscustomobject]@{ Id = 'tam-95' }))
        $r.Count | Should -Be 2
        $r[0].Status | Should -Be 'Feito' -Because $r[0].Motivo
        $r[1].Id | Should -Be 'tam-95'

        $novo = Get-ValorFonte $W.Chave 'Segoe UI Bold (TrueType)'
        $novo | Should -Match '^segoeuib_tmd\d{12}\.ttf$'
        $arquivo = Join-Path $W.Pasta $novo
        [IO.File]::Exists($arquivo) | Should -BeTrue
        Get-NomeInterno $arquivo | Should -Be 'Segoe UI'
        $upm = [Sfnt]::U16(([Sfnt]::Load($arquivo)).Get('head'), 18)
        $upm | Should -Be ([int][math]::Round(2048 * 100 / 95)) -Because 'Arial tem 2048 unidades; a 95% o mesmo desenho ocupa menos'
        (Get-ValorFonte $W.Chave 'Segoe UI Variable (TrueType)') | Should -Match '^SegUIVar_tmd'
        # As fontes de verdade da pasta continuam iguais.
        Get-ValorFonte $W.Chave 'Arial (TrueType)' | Should -Be 'arial.ttf'

        $alvos = @(Find-Alvos)
        ($alvos | Where-Object Id -eq 'fam-arial').Estado | Should -Be 'Aplicado'
        ($alvos | Where-Object Id -eq 'tam-95').Estado | Should -Be 'Aplicado'
        ($alvos | Where-Object Id -eq 'segoe-original').Estado | Should -Be 'NaoAplicado'

        (Undo-TmdAjuste -Id 'fonte-sistema').Status | Should -Be 'Feito'
        Get-ValorFonte $W.Chave 'Segoe UI Bold (TrueType)' | Should -Be 'segoeuib.ttf'

        $limpar = @(Find-Alvos | Where-Object Id -eq 'limpar-copias')[0]
        $limpar.Selecionavel | Should -BeTrue
        $l = @(Invoke-Acao -Alvos @($limpar))
        $l[0].Status | Should -Be 'Feito' -Because $l[0].Motivo
        $l[0].Liberado | Should -BeGreaterThan 0
        @(Get-ChildItem -LiteralPath $W.Pasta -Filter '*_*').Count | Should -Be 0
        [IO.File]::Exists((Join-Path $W.Pasta 'segoeuib.ttf')) | Should -BeTrue
    }

    It 'só o tamanho regera a fonte que o Tamanduá pôs; Segoe UI original volta os arquivos de fábrica' {
        (@(Invoke-Acao -Alvos @([pscustomobject]@{ Id = 'fam-arial' }))[0]).Status | Should -Be 'Feito'
        $antes = Get-ValorFonte $W.Chave 'Segoe UI (TrueType)'
        Start-Sleep -Seconds 1
        $r = @(Invoke-Acao -Alvos @([pscustomobject]@{ Id = 'tam-110' }))
        $r[0].Status | Should -Be 'Feito' -Because $r[0].Motivo
        $r[0].Motivo | Should -Match 'Arial a 110%'
        Get-ValorFonte $W.Chave 'Segoe UI (TrueType)' | Should -Not -Be $antes

        (@(Invoke-Acao -Alvos @([pscustomobject]@{ Id = 'segoe-original' }))[0]).Status | Should -Be 'Feito'
        Get-ValorFonte $W.Chave 'Segoe UI (TrueType)' | Should -Be 'segoeui.ttf'
        Get-ValorFonte $W.Chave 'Segoe UI Variable (TrueType)' | Should -Be 'SegUIVar.ttf'
        (@(Find-Alvos) | Where-Object Id -eq 'fam-arial').Estado | Should -Be 'NaoAplicado'
    }

    It 'combinações sem sentido não mudam nada' {
        $duas = @(Invoke-Acao -Alvos @([pscustomobject]@{ Id = 'fam-arial' }, [pscustomobject]@{ Id = 'fam-outra' }))
        $duas | ForEach-Object { $_.Status | Should -Be 'Erro' }
        $duas[0].Motivo | Should -Match 'só uma fonte'
        $soTamanho = @(Invoke-Acao -Alvos @([pscustomobject]@{ Id = 'tam-90' }))
        $soTamanho[0].Status | Should -Be 'Erro'
        $soTamanho[0].Motivo | Should -Match 'marque também a fonte'
        Get-ValorFonte $W.Chave 'Segoe UI (TrueType)' | Should -Be 'segoeui.ttf'
    }
}

Describe 'Núcleo: arquivos de fonte' {
    It 'só entram e saem cópias com nome de cópia da Segoe UI, sem sobrescrever' {
        $pasta = Join-Path $TestDrive 'fontes-nucleo'
        [void][IO.Directory]::CreateDirectory($pasta)
        $origem = Join-Path $TestDrive 'arial.ttf'
        [IO.File]::Copy((Join-Path $script:Windows 'arial.ttf'), $origem, $true)
        { Install-TmdArquivoFonte -Origem $origem -Pasta $pasta } | Should -Throw '*não permitido*'
        $copia = Join-Path $TestDrive 'segoeui_teste1.ttf'
        [IO.File]::Copy($origem, $copia, $true)
        Install-TmdArquivoFonte -Origem $copia -Pasta $pasta | Should -Be 'segoeui_teste1.ttf'
        { Install-TmdArquivoFonte -Origem $copia -Pasta $pasta } | Should -Throw '*já existe*'

        [IO.File]::Copy($origem, (Join-Path $pasta 'arial.ttf'))
        (Remove-TmdCopiaFonte -Caminho (Join-Path $pasta 'arial.ttf')).Status | Should -Be 'Ignorado'
        [IO.File]::Exists((Join-Path $pasta 'arial.ttf')) | Should -BeTrue
        (Remove-TmdCopiaFonte -Caminho (Join-Path $pasta 'segoeui_teste1.ttf')).Status | Should -Be 'Feito'
    }
}
