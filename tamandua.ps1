<#
.SYNOPSIS
    Tamanduá - limpeza, ajustes e manutenção para Windows.
.DESCRIPTION
    Sem argumentos abre a interface (ou o menu de texto, se ela faltar).
    Use "tamandua ajuda" para ver os comandos.
#>
[CmdletBinding()]
param(
    [Parameter(Position = 0)][string]$Comando,
    # Mostra o que seria feito, sem alterar nada.
    [switch]$Simular,
    # Confirma sem perguntar (para scripts).
    [switch]$Sim,
    [Parameter(ValueFromRemainingArguments = $true)][string[]]$Resto
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
try { [Console]::OutputEncoding = [Text.Encoding]::UTF8 } catch { Write-Verbose 'Console sem suporte a UTF-8.' }

# O núcleo é a única parte obrigatória; sem ele não há o que fazer.
$nucleo = Join-Path $PSScriptRoot 'nucleo\Tamandua.Nucleo.psm1'
if (-not (Test-Path -LiteralPath $nucleo -PathType Leaf)) {
    [Console]::Error.WriteLine("Tamanduá: núcleo não encontrado em $nucleo. Reinstale o programa.")
    exit 1
}
try {
    # -Global: os módulos usam funções exportadas do núcleo (ex.: Format-TmdTamanho).
    Import-Module -Name $nucleo -Force -DisableNameChecking -Global
    $codigo = Invoke-TmdCli -Comando $Comando -Argumentos $Resto -Raiz $PSScriptRoot -Simular:$Simular -Sim:$Sim
}
catch {
    [Console]::Error.WriteLine("Tamanduá: erro inesperado: $($_.Exception.Message)")
    $codigo = 1
}
exit $codigo
