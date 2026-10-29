BeforeAll {
    . (Join-Path $PSScriptRoot '..\Ajudantes.ps1')
    Import-Module (Join-Path $script:RaizProjeto 'nucleo\Tamandua.Nucleo.psm1') -Force -DisableNameChecking -Global
}

Describe 'Log de operações' {
    BeforeEach {
        $env:TAMANDUA_DADOS = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
    }

    It 'grava e lê de volta, da mais nova para a mais antiga' {
        InModuleScope Tamandua.Nucleo {
            Write-TmdOperacao -Modulo 'limpar' -Acao 'remover' -Caminho 'C:\a' -Status 'Feito' -Liberado 10
            Write-TmdOperacao -Modulo 'limpar' -Acao 'remover' -Caminho 'C:\b' -Status 'Parcial' -Motivo '1 em uso'
        }
        $h = @(Get-TmdHistorico)
        $h.Count | Should -Be 2
        $h[0].Caminho | Should -Be 'C:\b'
        $h[0].Motivo | Should -Be '1 em uso'
        $h[1].Liberado | Should -Be 10
    }

    It 'ignora linhas corrompidas e respeita -Ultimos' {
        $log = Join-Path $env:TAMANDUA_DADOS 'logs\operacoes.jsonl'
        [void][IO.Directory]::CreateDirectory((Split-Path $log))
        Set-Content -LiteralPath $log -Value '{"Status":"Feito","Caminho":"1"}', 'isso não é json', '{"Status":"Feito","Caminho":"2"}', '{"Status":"Feito","Caminho":"3"}'
        $h = @(Get-TmdHistorico -Ultimos 2)
        ($h | ForEach-Object Caminho) -join ',' | Should -Be '3,2'
        @(Get-TmdHistorico).Count | Should -Be 3
    }

    It 'sem log ainda, histórico vazio' {
        Get-TmdHistorico | Should -BeNullOrEmpty
    }

    It 'tamandua historico mostra as operações' {
        InModuleScope Tamandua.Nucleo {
            Write-TmdOperacao -Modulo 'limpar' -Acao 'remover' -Caminho 'C:\Temp\coisa' -Status 'Feito' -Liberado 2048
        }
        $r = Invoke-Tamandua -Raiz $script:RaizProjeto -Argumentos 'historico'
        $r.Codigo | Should -Be 0
        $r.Saida | Should -Match 'Feito\s+limpar\s+2[,.]0 KB\s+C:\\Temp\\coisa'
    }

    It 'tamandua historico sem nada registrado' {
        (Invoke-Tamandua -Raiz $script:RaizProjeto -Argumentos 'historico').Saida | Should -Match 'Nenhuma operação'
    }
}

Describe 'Confirmação' {
    It 'com -Sim confirma sem perguntar' {
        Mock Read-Host -ModuleName Tamandua.Nucleo { throw 'não devia perguntar' }
        Confirm-TmdExecucao -Pergunta 'Apagar?' -Sim | Should -BeTrue
    }

    It 'sem console interativo e sem -Sim, nunca confirma' {
        Mock Test-TmdInterativo -ModuleName Tamandua.Nucleo { $false }
        Mock Read-Host -ModuleName Tamandua.Nucleo { 's' }
        Confirm-TmdExecucao -Pergunta 'Apagar?' 6>$null | Should -BeFalse
        Should -Invoke Read-Host -ModuleName Tamandua.Nucleo -Times 0 -Exactly
    }

    It 'no console, só "<Resposta>" <Resultado>' -ForEach @(
        @{ Resposta = 's'; Esperado = $true; Resultado = 'confirma' }
        @{ Resposta = 'Sim'; Esperado = $true; Resultado = 'confirma' }
        @{ Resposta = ''; Esperado = $false; Resultado = 'não confirma' }
        @{ Resposta = 'n'; Esperado = $false; Resultado = 'não confirma' }
        @{ Resposta = 'talvez'; Esperado = $false; Resultado = 'não confirma' }
    ) {
        Mock Test-TmdInterativo -ModuleName Tamandua.Nucleo { $true }
        Mock Read-Host -ModuleName Tamandua.Nucleo -MockWith ([scriptblock]::Create("'$Resposta'"))
        Confirm-TmdExecucao -Pergunta 'Apagar?' | Should -Be $Esperado
    }
}

Describe 'tamandua protegidos' {
    It 'cria a lista do usuário com instruções e mostra onde está' {
        $env:TAMANDUA_CONFIG = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
        $r = Invoke-Tamandua -Raiz $script:RaizProjeto -Argumentos 'protegidos'
        $r.Codigo | Should -Be 0
        $arquivo = Join-Path $env:TAMANDUA_CONFIG 'protegidos.txt'
        $r.Saida | Should -Match ([regex]::Escape($arquivo))
        Get-Content -LiteralPath $arquivo -Encoding UTF8 -Raw | Should -Match 'nunca apaga'
        @(Get-TmdListaProtecao | Where-Object { $_ -like '#*' }).Count | Should -Be 0
    }
}
