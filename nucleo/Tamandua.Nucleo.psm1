Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$script:Versao = '0.1.0'
$script:ContratoAtual = 1
$script:RaizPadrao = Split-Path -Parent $PSScriptRoot

foreach ($parte in 'Config', 'Elevacao', 'Seguranca', 'Remocao', 'Estado', 'MotorAjustes', 'Registro', 'Carregador', 'Saida', 'Cli') {
    . (Join-Path $PSScriptRoot "$parte.ps1")
}

function Get-TmdVersao {
    [CmdletBinding()]
    param()
    $script:Versao
}

Export-ModuleMember -Function @(
    'Get-TmdVersao'
    'Get-TmdCatalogo'
    'Get-TmdModulo'
    'Write-TmdModulos'
    'Write-TmdAlvos'
    'Format-TmdTamanho'
    'Invoke-TmdCli'
    'Get-TmdPastaConfig'
    'Get-TmdPastaDados'
    'Get-TmdListaProtecao'
    'Test-TmdCaminhoSeguro'
    'Remove-TmdItem'
    'Measure-TmdTamanho'
    'Get-TmdHistorico'
    'Write-TmdOperacao'
    'New-TmdArquivoTemporario'
    'Remove-TmdArquivoTemporario'
    'Confirm-TmdExecucao'
    'Test-TmdAdministrador'
    'Invoke-TmdAcaoModulo'
    'Undo-TmdAjusteComAdmin'
    'Test-TmdDesfazerPrecisaAdmin'
    'Invoke-TmdPrograma'
    'Set-TmdAjuste'
    'Undo-TmdAjuste'
    'Get-TmdEstadoAjuste'
    'Test-TmdAjusteReversivel'
)
