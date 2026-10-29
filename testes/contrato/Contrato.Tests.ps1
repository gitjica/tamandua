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
    Import-Module (Join-Path $script:RaizProjeto 'nucleo\Tamandua.Nucleo.psm1') -Force -DisableNameChecking -Global
    $script:EstadosValidos = 'Aplicado', 'NaoAplicado', 'Parcial', 'Desconhecido', 'NaoSeAplica'
}

Describe 'Módulo <Nome>' -ForEach $modulos -AllowNullOrEmptyForEach {
    BeforeAll {
        $m = Get-TmdModulo -Raiz $script:RaizProjeto -Nome $Nome
    }

    It 'carrega como ok ou indisponível (nunca quebrado ou faltando)' {
        $m.Estado | Should -BeIn 'ok', 'indisponivel' -Because $m.Motivo
    }

    It 'tem testes próprios em testes\modulos\<Nome>' {
        $pasta = Join-Path $script:RaizProjeto "testes\modulos\$Nome"
        @(Get-ChildItem -LiteralPath $pasta -Filter '*.Tests.ps1' -ErrorAction SilentlyContinue).Count | Should -BeGreaterThan 0
    }

    # Find-Alvos só lê, então roda contra o sistema real em todo módulo disponível. Invoke-Acao nunca roda aqui.
    It 'Find-Alvos devolve objetos no formato do contrato' {
        if ($m.Estado -ne 'ok') {
            Set-ItResult -Skipped -Because 'módulo indisponível nesta máquina'
            return
        }
        $escreve = [bool]$m.Manifesto['Escreve']
        $obrigatorias = @('Id', 'Nome', 'Categoria', 'Estado', 'Detalhe')
        if ($escreve) { $obrigatorias += 'Caminho', 'Tamanho', 'Risco', 'Selecionado', 'Destino', 'RequerAdmin', 'Reversivel', 'Mudancas' }
        $alvos = @(& $m.Modulo.ExportedFunctions['Find-Alvos'])
        foreach ($a in $alvos) {
            $nomes = $a.PSObject.Properties.Name
            foreach ($p in $obrigatorias) { $nomes | Should -Contain $p -Because "alvo $($a.Id)" }
            $a.Estado | Should -BeIn $script:EstadosValidos
            if ($escreve) {
                $a.Risco | Should -BeIn 'Baixo', 'Medio', 'Alto'
                $a.Destino | Should -BeIn 'Permanente', 'Lixeira', 'NaoSeAplica'
                if ($a.Risco -eq 'Alto') { $a.Selecionado | Should -BeFalse -Because 'risco alto nunca vem marcado' }
            }
        }
        # ForEach-Object em vez de $alvos.Id: lista vazia não tem a propriedade em StrictMode.
        @($alvos | ForEach-Object { $_.Id } | Select-Object -Unique).Count | Should -Be $alvos.Count -Because 'Id precisa ser único'
    }

    It 'Invoke-Acao aceita -Alvos e -Simular' {
        if ($m.Estado -ne 'ok' -or -not $m.Manifesto['Escreve']) {
            Set-ItResult -Skipped -Because 'só módulos que escrevem'
            return
        }
        $parametros = $m.Modulo.ExportedFunctions['Invoke-Acao'].Parameters
        $parametros.Keys | Should -Contain 'Alvos'
        $parametros.Keys | Should -Contain 'Simular'
        $parametros['Simular'].ParameterType | Should -Be ([switch])
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
    $chave.SetValue('x', 1)
}
'@
        $achados = @(Find-EscritaProibida -Pasta $pasta)
        $achados.Count | Should -Be 5
    }
}
