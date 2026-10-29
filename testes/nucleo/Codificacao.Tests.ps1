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
        $temBom | Should -BeTrue
    }

    It 'é válido no parser do PowerShell 5.1' {
        $tokens = $null
        $erros = $null
        [System.Management.Automation.Language.Parser]::ParseFile($Caminho, [ref]$tokens, [ref]$erros) | Out-Null
        $erros | Should -BeNullOrEmpty
    }
}
