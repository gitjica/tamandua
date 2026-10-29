# Política do Windows Update: quando e o que atualizar, sem nunca desligar as atualizações.
# Cada política é um ajuste (atualizacoes.json) entregue ao motor do núcleo: guarda o valor de antes e dá para desfazer
# pelo Histórico. São chaves de política em HKLM, então o núcleo roda a aplicação num processo de administrador.

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$script:ArquivoCatalogo = Join-Path $PSScriptRoot 'atualizacoes.json'

# Testes: TAMANDUA_REGISTRO_TESTE redireciona o registro (só vale em HKCU:\Software\TamanduaTestes).
function Get-RaizRegistroPadrao {
    $r = $env:TAMANDUA_REGISTRO_TESTE
    if ($r -and $r -like 'HKCU:\Software\TamanduaTestes\*') { return $r }
    ''
}

function Test-Requisitos {
    try {
        if (@(Get-CatalogoPoliticas).Count -eq 0) { return @{ Ok = $false; Motivo = 'atualizacoes.json está vazio' } }
        @{ Ok = $true; Motivo = '' }
    }
    catch { @{ Ok = $false; Motivo = "não foi possível ler atualizacoes.json: $($_.Exception.Message)" } }
}

function Get-CatalogoPoliticas {
    param([string]$Arquivo = $script:ArquivoCatalogo)
    foreach ($p in ([IO.File]::ReadAllText($Arquivo, [Text.Encoding]::UTF8) | ConvertFrom-Json)) { $p }
}

# Windows Home ignora estas políticas: avisa em vez de fingir que funcionam.
function Test-EdicaoHome {
    try { [string](Get-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion' -Name EditionID -ErrorAction Stop).EditionID -like 'Core*' }
    catch { $false }
}

function Find-Alvos {
    param([string]$Catalogo = $script:ArquivoCatalogo, [string]$RaizRegistro = (Get-RaizRegistroPadrao))
    # Não "$home": é a variável automática $HOME do PowerShell.
    $edicaoHome = Test-EdicaoHome
    foreach ($p in Get-CatalogoPoliticas -Arquivo $Catalogo) {
        $detalhe = $p.descricao
        if ($edicaoHome) { $detalhe += ' (O Windows Home ignora esta política.)' }
        [pscustomobject]@{
            Id = $p.id; Nome = $p.nome; Categoria = $p.categoria; Caminho = ''; Tamanho = [int64]0
            Estado = Get-TmdEstadoAjuste -Ajuste $p -RaizRegistro $RaizRegistro; Detalhe = $detalhe; Nivel = 'Normal'; Valor = $null
            Risco = $p.risco; Selecionado = $false; Destino = 'NaoSeAplica'; RequerAdmin = [bool]$p.requerAdmin; Reversivel = $true
            Presets = @($p.presets)
            Mudancas = @($p.mudancas | ForEach-Object { "$($_.caminho)\$($_.nome) = $($_.valor) (padrão do Windows: não existe)" })
        }
    }
}

# Aplica pela definição do catálogo, achada pelo Id.
function Invoke-Acao {
    param(
        [Parameter(Mandatory)][AllowEmptyCollection()][object[]]$Alvos,
        [switch]$Simular,
        [string]$Catalogo = $script:ArquivoCatalogo,
        [string]$RaizRegistro = (Get-RaizRegistroPadrao)
    )
    $definicoes = @{}
    foreach ($p in Get-CatalogoPoliticas -Arquivo $Catalogo) { $definicoes[$p.id] = $p }
    foreach ($a in $Alvos) {
        $id = [string]$a.Id
        if (-not $definicoes.ContainsKey($id)) {
            [pscustomobject]@{ Id = $id; Status = 'Erro'; Liberado = [int64]0; Motivo = 'política desconhecida'; Mudancas = @() }
            continue
        }
        Set-TmdAjuste -Ajuste $definicoes[$id] -Simular:$Simular -RaizRegistro $RaizRegistro -Modulo 'atualizacoes'
    }
}

Export-ModuleMember -Function Test-Requisitos, Find-Alvos, Invoke-Acao
