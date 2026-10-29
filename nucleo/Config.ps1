# Onde o Tamanduá guarda configuração e dados do usuário, e a lista de proteção.
# TAMANDUA_CONFIG e TAMANDUA_DADOS trocam as pastas (usado pelos testes para nunca tocar nas pastas reais).

function Get-TmdPastaConfig {
    [CmdletBinding()]
    param()
    if ($env:TAMANDUA_CONFIG) { return $env:TAMANDUA_CONFIG }
    Join-Path ([Environment]::GetFolderPath('ApplicationData')) 'Tamandua'
}

function Get-TmdPastaDados {
    [CmdletBinding()]
    param()
    if ($env:TAMANDUA_DADOS) { return $env:TAMANDUA_DADOS }
    Join-Path ([Environment]::GetFolderPath('LocalApplicationData')) 'Tamandua'
}

function Get-TmdArquivoProtecaoUsuario {
    Join-Path (Get-TmdPastaConfig) 'protegidos.txt'
}

# Padrões da lista padrão + lista do usuário, com variáveis de ambiente expandidas.
# Se a lista do usuário existe mas não pode ser lida, lança: ninguém deve apagar nada sem saber o que o usuário protegeu.
function Get-TmdListaProtecao {
    [CmdletBinding()]
    param([string]$Raiz = $script:RaizPadrao)

    $arquivos = @(
        @{ Caminho = Join-Path $Raiz 'config\protegidos.padrao.txt'; Obrigatorio = $false }
        @{ Caminho = Get-TmdArquivoProtecaoUsuario; Obrigatorio = $true }
    )
    foreach ($a in $arquivos) {
        if (-not (Test-Path -LiteralPath $a.Caminho)) { continue }
        try {
            $linhas = [IO.File]::ReadAllLines($a.Caminho, [Text.Encoding]::UTF8)
        }
        catch {
            if ($a.Obrigatorio) { throw "não foi possível ler a lista de proteção $($a.Caminho): $($_.Exception.Message)" }
            continue
        }
        foreach ($l in $linhas) {
            $p = $l.Trim()
            if ($p -and -not $p.StartsWith('#')) { [Environment]::ExpandEnvironmentVariables($p) }
        }
    }
}
