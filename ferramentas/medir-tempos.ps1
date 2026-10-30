<#
.SYNOPSIS
    Mede, na janela de verdade, quanto o usuário espera: abrir o programa até o Status aparecer, abrir cada módulo
    e atualizar o Status. Só abre páginas (nada é aplicado). Repete e devolve a mediana de cada medida, em ms.
.EXAMPLE
    .\ferramentas\medir-tempos.ps1 -Vezes 3 -Saida C:\temp\antes.json
#>
[CmdletBinding()]
param(
    [int]$Vezes = 3,
    [string]$Saida,
    # Espera a leitura antecipada terminar antes de clicar nos módulos (ver medir-tempos-rodada.ps1).
    [switch]$Esperar
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$raiz = Split-Path -Parent $PSScriptRoot
$script = Join-Path $PSScriptRoot 'medir-tempos-rodada.ps1'

# Cada rodada é um processo novo, como o usuário abrindo o programa.
$resultados = foreach ($n in 1..$Vezes) {
    $arquivo = Join-Path ([IO.Path]::GetTempPath()) "tamandua-medida-$([guid]::NewGuid().ToString('N')).json"
    $argumentos = @('-NoProfile', '-STA', '-ExecutionPolicy', 'Bypass', '-File', "`"$script`"", '-Raiz', "`"$raiz`"", '-Arquivo', "`"$arquivo`"")
    if ($Esperar) { $argumentos += '-Esperar' }
    $p = Start-Process -FilePath 'powershell.exe' -ArgumentList $argumentos -Wait -PassThru
    if (-not (Test-Path -LiteralPath $arquivo)) { throw "rodada $n não gravou medidas (código $($p.ExitCode))" }
    Get-Content -LiteralPath $arquivo -Raw | ConvertFrom-Json
    Remove-Item -LiteralPath $arquivo
    Write-Verbose "rodada $n ok"
}

$mediana = [ordered]@{}
foreach ($nome in @($resultados | ForEach-Object { $_.PSObject.Properties.Name } | Select-Object -Unique)) {
    $valores = @($resultados | ForEach-Object { $_.$nome } | Where-Object { $null -ne $_ } | Sort-Object)
    $mediana[$nome] = $valores[[int][math]::Floor($valores.Count / 2)]
}
if ($Saida) { [IO.File]::WriteAllText([IO.Path]::GetFullPath($Saida), ($mediana | ConvertTo-Json)) }
[pscustomobject]$mediana
