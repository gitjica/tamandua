# Log de operações em JSON Lines: uma linha por item removido, simulado, ignorado ou com erro.

$script:Sessao = [guid]::NewGuid().ToString('N').Substring(0, 8)

function Get-TmdArquivoLog {
    Join-Path (Get-TmdPastaDados) 'logs\operacoes.jsonl'
}

function Write-TmdOperacao {
    param(
        [string]$Modulo, [string]$Id, [Parameter(Mandatory)][string]$Acao, [string]$Caminho, [string]$Destino,
        [Parameter(Mandatory)][string]$Status, [int64]$Liberado = 0, [string]$Motivo = '', [bool]$Simulado = $false
    )

    $linha = [ordered]@{
        Data     = (Get-Date).ToString('o')
        Sessao   = $script:Sessao
        Modulo   = $Modulo
        Id       = $Id
        Acao     = $Acao
        Caminho  = $Caminho
        Destino  = $Destino
        Status   = $Status
        Liberado = $Liberado
        Motivo   = $Motivo
        Simulado = $Simulado
    } | ConvertTo-Json -Compress
    $arquivo = Get-TmdArquivoLog
    try {
        $pasta = Split-Path -Parent $arquivo
        if (-not (Test-Path -LiteralPath $pasta)) { [void][IO.Directory]::CreateDirectory($pasta) }
        [IO.File]::AppendAllText($arquivo, $linha + "`n", (New-Object Text.UTF8Encoding $false))
    }
    catch {
        # Falhar ao registrar não desfaz o que já foi feito; avisa e segue.
        Write-Warning "não foi possível registrar a operação no log: $($_.Exception.Message)"
    }
}

# Últimas N operações, da mais nova para a mais antiga. Linhas corrompidas são ignoradas.
# Cada uma ganha Reversivel: é o ajuste aplicado mais recente daquele Id, sem desfazer depois, e há estado salvo.
function Get-TmdHistorico {
    [CmdletBinding()]
    param([int]$Ultimos = 50)

    $arquivo = Get-TmdArquivoLog
    if (-not (Test-Path -LiteralPath $arquivo)) { return }
    $linhas = [IO.File]::ReadAllLines($arquivo, [Text.Encoding]::UTF8)
    $saida = [System.Collections.Generic.List[object]]::new()
    $vistos = @{}
    for ($i = $linhas.Count - 1; $i -ge 0 -and $saida.Count -lt $Ultimos; $i--) {
        if (-not $linhas[$i].Trim()) { continue }
        try { $op = $linhas[$i] | ConvertFrom-Json } catch { Write-Verbose "linha $($i + 1) do log ignorada"; continue }
        $reversivel = $false
        $acao = [string](Get-Propriedade -Objeto $op -Nome 'Acao')
        $idOp = [string](Get-Propriedade -Objeto $op -Nome 'Id')
        if ($acao -in 'ajustar', 'desfazer' -and $idOp -and -not (Get-Propriedade -Objeto $op -Nome 'Simulado') -and -not $vistos.ContainsKey($idOp)) {
            $vistos[$idOp] = $true
            $reversivel = $acao -eq 'ajustar' -and (Get-Propriedade -Objeto $op -Nome 'Status') -eq 'Feito' -and (Test-TmdAjusteReversivel -Id $idOp)
        }
        $op | Add-Member -NotePropertyName Reversivel -NotePropertyValue $reversivel -Force
        $saida.Add($op)
    }
    $saida.ToArray()
}
