# Snapshots para desfazer: o valor que estava na máquina ANTES do Tamanduá mexer, um arquivo por ajuste.
# Regra: um snapshot nunca é sobrescrito por um valor que o próprio Tamanduá escreveu.

function Get-TmdArquivoSnapshot {
    param([Parameter(Mandatory)][string]$Id)
    # O Id vira nome de arquivo: só letras minúsculas, números e hífen.
    if ($Id -notmatch '^[a-z0-9][a-z0-9-]{0,80}$') { throw "Id de ajuste inválido: '$Id'" }
    Join-Path (Get-TmdPastaDados) "estado\ajustes\$Id.json"
}

# Entradas salvas para o ajuste, ou @() se não há. Arquivo corrompido lança: desfazer com dado errado é pior que não desfazer.
function Read-TmdSnapshot {
    param([Parameter(Mandatory)][string]$Id)
    $arquivo = Get-TmdArquivoSnapshot -Id $Id
    if (-not (Test-Path -LiteralPath $arquivo)) { return , @() }
    try {
        $dados = [IO.File]::ReadAllText($arquivo, [Text.Encoding]::UTF8) | ConvertFrom-Json
    }
    catch {
        throw "o estado salvo do ajuste $Id está corrompido ($arquivo): $($_.Exception.Message)"
    }
    , @($dados.Entradas)
}

# Grava de forma atômica (arquivo temporário + troca), para um corte de energia não deixar meio arquivo.
function Save-TmdSnapshot {
    param([Parameter(Mandatory)][string]$Id, [Parameter(Mandatory)][AllowEmptyCollection()][object[]]$Entradas)
    $arquivo = Get-TmdArquivoSnapshot -Id $Id
    [void][IO.Directory]::CreateDirectory((Split-Path -Parent $arquivo))
    $json = [pscustomobject]@{ Id = $Id; Salvo = (Get-Date).ToString('o'); Entradas = $Entradas } | ConvertTo-Json -Depth 6
    $temporario = "$arquivo.tmp"
    [IO.File]::WriteAllText($temporario, $json, (New-Object Text.UTF8Encoding $false))
    # [NullString]: no 5.1, $null passado para um parâmetro string do .NET vira "" (e o Replace recusa como caminho inválido).
    if (Test-Path -LiteralPath $arquivo) { [IO.File]::Replace($temporario, $arquivo, [NullString]::Value) }
    else { [IO.File]::Move($temporario, $arquivo) }
}

function Remove-TmdSnapshot {
    param([Parameter(Mandatory)][string]$Id)
    $arquivo = Get-TmdArquivoSnapshot -Id $Id
    if (Test-Path -LiteralPath $arquivo) { [IO.File]::Delete($arquivo) }
}

# Há um estado salvo que permite desfazer este ajuste?
function Test-TmdAjusteReversivel {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Id)
    try { (Read-TmdSnapshot -Id $Id).Count -gt 0 } catch { $false }
}
