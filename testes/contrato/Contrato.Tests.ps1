# Regras que valem para TODO módulo em modulos\. Módulo novo entra aqui automaticamente.

BeforeDiscovery {
    $raizProjeto = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    $pastaModulos = Join-Path $raizProjeto 'modulos'
    $modulos = @()
    if (Test-Path -LiteralPath $pastaModulos) {
        $modulos = @(Get-ChildItem -LiteralPath $pastaModulos -Directory | ForEach-Object { @{ Nome = $_.Name } })
    }
}

BeforeAll {
    . (Join-Path $PSScriptRoot '..\Ajudantes.ps1')
    Import-Module (Join-Path $script:RaizProjeto 'nucleo\Tamandua.Nucleo.psm1') -Force -DisableNameChecking
}

Describe 'Módulo <Nome>' -ForEach $modulos -AllowNullOrEmptyForEach {
    It 'carrega como ok ou indisponível (nunca quebrado ou faltando)' {
        $m = Get-TmdModulo -Raiz $script:RaizProjeto -Nome $Nome
        $m.Estado | Should -BeIn 'ok', 'indisponivel' -Because $m.Motivo
    }
}

Describe 'Escrita no sistema só pelo núcleo' {
    It 'nenhum arquivo em modulos\ ou interface\ usa comandos que escrevem no sistema' {
        $achados = @(
            Find-EscritaProibida -Pasta (Join-Path $script:RaizProjeto 'modulos')
            Find-EscritaProibida -Pasta (Join-Path $script:RaizProjeto 'interface')
        )
        $achados | Should -BeNullOrEmpty -Because ($achados -join "`n")
    }

    It 'o verificador detecta comandos e chamadas .NET proibidos' {
        $pasta = Join-Path $TestDrive 'amostra'
        New-Item -ItemType Directory -Path $pasta | Out-Null
        Set-Content -LiteralPath (Join-Path $pasta 'ruim.psm1') -Encoding UTF8 -Value @'
function Find-Alvos {
    Remove-Item C:\x
    [System.IO.File]::Delete('C:\y')
    reg add HKCU\Software\X
    Write-Host 'oi'
}
'@
        $achados = @(Find-EscritaProibida -Pasta $pasta)
        $achados.Count | Should -Be 4
    }
}
