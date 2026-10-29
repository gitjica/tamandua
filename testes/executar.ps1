<#
.SYNOPSIS
    Roda lint e testes do Tamanduá. Sai com código diferente de 0 se algo falhar.
.EXAMPLE
    .\testes\executar.ps1
    .\testes\executar.ps1 -Rapido
    .\testes\executar.ps1 -Modulo limpar
#>
[CmdletBinding()]
param(
    [switch]$Rapido,
    [string]$Modulo
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$raiz = Split-Path -Parent $PSScriptRoot
$falhou = $false

if (-not $Rapido) {
    if (Get-Module -ListAvailable -Name PSScriptAnalyzer) {
        $regras = Import-PowerShellDataFile -LiteralPath (Join-Path $PSScriptRoot 'PSScriptAnalyzerSettings.psd1')
        # Nos testes, variáveis criadas em BeforeAll/BeforeEach são usadas em outro bloco; o analisador não enxerga isso.
        $regrasTestes = $regras.Clone()
        # Mocks que guardam estado (serviço/tarefa falsos) precisam de variável global.
        $regrasTestes.ExcludeRules = @($regras.ExcludeRules) + 'PSUseDeclaredVarsMoreThanAssignments' + 'PSAvoidGlobalVars'
        $codigo = Get-ChildItem -LiteralPath $raiz | Where-Object {
            $_.Name -ne 'testes' -and ($_.PSIsContainer -or $_.Extension -in '.ps1', '.psm1', '.psd1')
        }
        $achados = @(
            foreach ($item in $codigo) { Invoke-ScriptAnalyzer -Path $item.FullName -Recurse:$item.PSIsContainer -Settings $regras }
            Invoke-ScriptAnalyzer -Path $PSScriptRoot -Recurse -Settings $regrasTestes
        )
        if ($achados.Count -gt 0) {
            $achados | Format-Table -AutoSize RuleName, Severity, ScriptName, Line, Message | Out-Host
            Write-Host "Lint: $($achados.Count) problema(s)." -ForegroundColor Red
            $falhou = $true
        }
        else {
            Write-Host 'Lint: ok' -ForegroundColor Green
        }
    }
    else {
        Write-Host 'PSScriptAnalyzer não instalado. Instale com: Install-Module PSScriptAnalyzer -Scope CurrentUser' -ForegroundColor Red
        $falhou = $true
    }
}

$pester = Get-Module -ListAvailable -Name Pester | Where-Object { $_.Version.Major -ge 5 } |
    Sort-Object Version -Descending | Select-Object -First 1
if (-not $pester) {
    Write-Host 'Pester 5+ não instalado. Instale com: Install-Module Pester -Scope CurrentUser -Force -SkipPublisherCheck' -ForegroundColor Red
    exit 1
}
Import-Module $pester -Force

$config = New-PesterConfiguration
$config.Run.Path = if ($Modulo) {
    @((Join-Path $PSScriptRoot 'contrato'), (Join-Path $PSScriptRoot "modulos\$Modulo"))
}
else {
    @($PSScriptRoot)
}
$config.Run.PassThru = $true
$config.Output.Verbosity = 'Detailed'
$resultado = Invoke-Pester -Configuration $config
if ($resultado.Result -ne 'Passed') { $falhou = $true }

if ($falhou) {
    Write-Host 'FALHOU' -ForegroundColor Red
    exit 1
}
Write-Host 'Tudo verde.' -ForegroundColor Green
exit 0
