# Regras de compatibilidade com o PowerShell 5.1 (seção 3 do guia).

BeforeDiscovery {
    $raizProjeto = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    $arquivos = @(Get-ChildItem -LiteralPath $raizProjeto -Recurse -File |
            Where-Object { $_.Extension -in '.ps1', '.psm1', '.psd1' } |
            ForEach-Object { @{ Caminho = $_.FullName; Relativo = $_.FullName.Substring($raizProjeto.Length + 1) } })
}

Describe '<Relativo>' -ForEach $arquivos {
    It 'está em UTF-8 com BOM (sem BOM o 5.1 lê acentos errado)' {
        $bytes = [System.IO.File]::ReadAllBytes($Caminho)
        $temBom = $bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF
        if ($Relativo -eq 'instalar.ps1') {
            # Exceção: roda por "irm ... | iex", e o iex não aceita o BOM. Por isso só ASCII (sem acentos), sem BOM.
            $temBom | Should -BeFalse
            @($bytes | Where-Object { $_ -gt 127 }).Count | Should -Be 0 -Because 'sem BOM, acento sairia errado'
        }
        else { $temBom | Should -BeTrue }
    }

    It 'é válido no parser do PowerShell 5.1' {
        $tokens = $null
        $erros = $null
        [System.Management.Automation.Language.Parser]::ParseFile($Caminho, [ref]$tokens, [ref]$erros) | Out-Null
        $erros | Should -BeNullOrEmpty
    }
}

Describe 'docs/index.html (página do GitHub Pages que também é o script do "irm gitjica.github.io/tamandua | iex")' {
    BeforeAll {
        $caminho = Join-Path (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) 'docs\index.html'
        $bytes = [System.IO.File]::ReadAllBytes($caminho)
    }

    It 'é só ASCII e sem BOM, como o instalar.ps1' {
        @($bytes | Where-Object { $_ -gt 127 }).Count | Should -Be 0
    }

    It 'para o PowerShell, o HTML é comentário e só sobra a linha que roda o instalar.ps1' {
        $tokens = $null
        $erros = $null
        $ast = [System.Management.Automation.Language.Parser]::ParseInput([Text.Encoding]::ASCII.GetString($bytes), [ref]$tokens, [ref]$erros)
        $erros | Should -BeNullOrEmpty
        @($ast.EndBlock.Statements | ForEach-Object { $_.Extent.Text }) |
            Should -Be @('irm https://raw.githubusercontent.com/gitjica/tamandua/main/instalar.ps1 | iex')
    }
}
