# Módulo instaladores. Downloads é sempre uma pasta da sandbox (-Pasta ou TAMANDUA_DOWNLOADS_TESTE)
# e a Lixeira é uma pasta da sandbox (TAMANDUA_LIXEIRA_TESTE): nada vai para a Lixeira real.

BeforeAll {
    . (Join-Path $PSScriptRoot '..\..\Ajudantes.ps1')
    Import-Module (Join-Path $script:RaizProjeto 'nucleo\Tamandua.Nucleo.psm1') -Force -DisableNameChecking -Global
    Import-Module (Join-Path $script:RaizProjeto 'modulos\instaladores\instaladores.psm1') -Force -DisableNameChecking

    function New-Downloads {
        $base = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
        $pasta = New-ArvoreFalsa -Pasta (Join-Path $base 'Downloads') -Arquivos @{
            'setup-velho.exe'        = ('e' * 3000)
            'pacote.msi'             = ('m' * 2000)
            'ubuntu.iso'             = ('i' * 5000)
            'fotos.zip'              = ('z' * 1000)
            'recente.exe'            = ('r' * 100)
            'contrato.pdf'           = ('p' * 900)
            'Programas\ferramenta.exe' = ('f' * 400)
            'a\b\c\fundo-demais.exe' = ('x' * 10)
        }
        foreach ($n in 'setup-velho.exe', 'pacote.msi', 'ubuntu.iso', 'fotos.zip', 'contrato.pdf', 'Programas\ferramenta.exe') { Set-Idade "$pasta\$n" (24 * 30) }
        Set-Idade "$pasta\recente.exe" 48
        [pscustomobject]@{ Base = $base; Pasta = $pasta; Lixeira = Join-Path $base 'Lixeira' }
    }
}

Describe 'Find-Alvos' {
    BeforeEach { $d = New-Downloads }

    It 'acha só instaladores, imagens e compactados, agrupados por tipo e do maior para o menor, até 3 níveis' {
        $alvos = @(Find-Alvos -Pasta $d.Pasta)
        ($alvos | ForEach-Object Nome) -join ',' | Should -Be 'setup-velho.exe,pacote.msi,ferramenta.exe,recente.exe,ubuntu.iso,fotos.zip'
        ($alvos | Where-Object Nome -eq 'ferramenta.exe').Detalhe | Should -Match 'em Programas\\'
        ($alvos | Where-Object Nome -eq 'ubuntu.iso').Categoria | Should -Be 'Imagens de disco'
    }

    It 'marca só risco baixo baixado há 7 dias ou mais' {
        $alvos = @(Find-Alvos -Pasta $d.Pasta)
        ($alvos | Where-Object Selecionado | ForEach-Object Nome | Sort-Object) -join ',' | Should -Be 'ferramenta.exe,pacote.msi,setup-velho.exe,ubuntu.iso'
        ($alvos | Where-Object Nome -eq 'fotos.zip').Risco | Should -Be 'Medio'
        ($alvos | Where-Object Nome -eq 'recente.exe').Detalhe | Should -Match 'baixado há 2 dias'
    }

    It '.exe numa pasta com .dll (programa portátil extraído) fica com risco médio e desmarcado' {
        New-ArvoreFalsa -Pasta "$($d.Pasta)\MeuApp" -Arquivos @{ 'app.exe' = 'a'; 'app.dll' = 'b'; 'LEIAME.txt' = 'c' } | Out-Null
        New-ArvoreFalsa -Pasta "$($d.Pasta)\SoInstalador" -Arquivos @{ 'setup.exe' = 's'; 'LEIAME.txt' = 'c' } | Out-Null
        Set-Idade "$($d.Pasta)\MeuApp\app.exe" (24 * 90)
        Set-Idade "$($d.Pasta)\SoInstalador\setup.exe" (24 * 90)
        $alvos = @(Find-Alvos -Pasta $d.Pasta)
        $app = $alvos | Where-Object Nome -eq 'app.exe'
        $app.Risco | Should -Be 'Medio'
        $app.Selecionado | Should -BeFalse
        $app.Detalhe | Should -Match 'programa portátil'
        ($alvos | Where-Object Nome -eq 'setup.exe').Selecionado | Should -BeTrue -Because 'um .txt ao lado não faz parecer portátil'
    }

    It 'não entra em links' {
        $fora = New-ArvoreFalsa -Pasta (Join-Path $d.Base 'Outro') -Arquivos @{ 'grande.iso' = 'x' }
        New-Item -ItemType Junction -Path "$($d.Pasta)\atalho" -Target $fora | Out-Null
        @(Find-Alvos -Pasta $d.Pasta | Where-Object Nome -eq 'grande.iso').Count | Should -Be 0
    }

    It 'pasta enorme: busca incompleta, nada vem marcado' {
        InModuleScope instaladores { $script:LimiteArquivos = 3 }
        try { $alvos = @(Find-Alvos -Pasta $d.Pasta) }
        finally { InModuleScope instaladores { $script:LimiteArquivos = 20000 } }
        @($alvos | Where-Object Selecionado).Count | Should -Be 0
        ($alvos | Where-Object Id -eq 'aviso-busca').Nivel | Should -Be 'Atencao'
    }
}

Describe 'Invoke-Acao' {
    BeforeEach {
        $d = New-Downloads
        $env:TAMANDUA_LIXEIRA_TESTE = $d.Lixeira
        $alvos = @(Find-Alvos -Pasta $d.Pasta)
    }
    AfterEach { Remove-Item Env:\TAMANDUA_LIXEIRA_TESTE -ErrorAction SilentlyContinue }

    It 'manda os escolhidos para a Lixeira e deixa o resto' {
        $r = @(Invoke-Acao -Alvos @($alvos | Where-Object Selecionado) -Pasta $d.Pasta)
        @($r | Where-Object Status -ne 'Feito').Count | Should -Be 0
        Test-Path "$($d.Pasta)\setup-velho.exe" | Should -BeFalse
        Test-Path "$($d.Pasta)\recente.exe" | Should -BeTrue
        Test-Path "$($d.Pasta)\contrato.pdf" | Should -BeTrue
        @(Get-ChildItem -LiteralPath $d.Lixeira).Count | Should -Be 4
    }

    It '-Simular não move nada' {
        $antes = Get-AssinaturaPasta $d.Pasta
        $r = @(Invoke-Acao -Alvos $alvos -Pasta $d.Pasta -Simular)
        @($r | ForEach-Object Status | Select-Object -Unique) | Should -Be 'Simulado'
        Get-AssinaturaPasta $d.Pasta | Should -Be $antes
    }

    It 'arquivo que mudou depois da busca não é mexido' {
        [IO.File]::AppendAllText("$($d.Pasta)\setup-velho.exe", 'mais')
        $r = Invoke-Acao -Alvos @($alvos | Where-Object Nome -eq 'setup-velho.exe') -Pasta $d.Pasta
        $r.Status | Should -Be 'Ignorado'
        $r.Motivo | Should -Match 'mudou desde a busca'
        Test-Path "$($d.Pasta)\setup-velho.exe" | Should -BeTrue
    }

    It 'não aceita alvo forjado: outra extensão, ..\ ou sem identidade' {
        $antes = Get-AssinaturaPasta $d.Base
        $forjados = @(
            [pscustomobject]@{ Id = 'arq:contrato.pdf'; Tamanho = 900; Modificado = (Get-Item "$($d.Pasta)\contrato.pdf").LastWriteTimeUtc.Ticks }
            [pscustomobject]@{ Id = 'arq:..\fora.exe'; Tamanho = 1; Modificado = 1 }
            [pscustomobject]@{ Id = 'arq:pacote.msi'; Caminho = 'C:\Windows\notepad.exe' }
        )
        $r = @(Invoke-Acao -Alvos $forjados -Pasta $d.Pasta)
        @($r | ForEach-Object Status | Select-Object -Unique) | Should -Be 'Ignorado'
        Get-AssinaturaPasta $d.Base | Should -Be $antes
    }
}

Describe 'Pela linha de comando' {
    BeforeEach {
        $d = New-Downloads
        $ambiente = @{ TAMANDUA_DOWNLOADS_TESTE = $d.Pasta; TAMANDUA_LIXEIRA_TESTE = $d.Lixeira }
        $projeto = New-ProjetoFalso -Pai $TestDrive -ModulosReais 'instaladores'
    }

    It '-Simular lista e não move; sem -Sim cancela; com -Sim manda os marcados para a Lixeira' {
        $s = Invoke-Tamandua -Raiz $projeto -Argumentos 'instaladores', '-Simular' -Ambiente $ambiente
        $s.Codigo | Should -Be 0
        $s.Saida | Should -Match '\[x\] ubuntu.iso'
        $s.Saida | Should -Match '\[ \] fotos.zip'
        Test-Path "$($d.Pasta)\ubuntu.iso" | Should -BeTrue

        (Invoke-Tamandua -Raiz $projeto -Argumentos 'instaladores' -Ambiente $ambiente).Codigo | Should -Be 3
        Test-Path "$($d.Pasta)\ubuntu.iso" | Should -BeTrue

        $r = Invoke-Tamandua -Raiz $projeto -Argumentos 'instaladores', '-Sim' -Ambiente $ambiente
        $r.Codigo | Should -Be 0
        Test-Path "$($d.Pasta)\ubuntu.iso" | Should -BeFalse
        Test-Path "$($d.Pasta)\fotos.zip" | Should -BeTrue
        @(Get-ChildItem -LiteralPath $d.Lixeira).Count | Should -Be 4
    }

    It 'Lixeira de teste fora do TEMP é recusada (não move nada)' {
        $ambiente.TAMANDUA_LIXEIRA_TESTE = 'C:\LixeiraFalsaForaDoTemp'
        $r = Invoke-Tamandua -Raiz $projeto -Argumentos 'instaladores', '-Sim' -Ambiente $ambiente
        $r.Saida | Should -Match 'pasta temporária'
        Test-Path "$($d.Pasta)\ubuntu.iso" | Should -BeTrue
        Test-Path 'C:\LixeiraFalsaForaDoTemp' | Should -BeFalse
    }
}

Describe 'Confirmação na interface' {
    It 'diz que vai para a Lixeira' {
        Import-Module (Join-Path $script:RaizProjeto 'interface\Interface.psm1') -Force -DisableNameChecking
        InModuleScope Interface {
            $alvos = @([pscustomobject]@{ Id = 'arq:a.exe'; Nome = 'a.exe'; Categoria = 'I'; Estado = 'NaoSeAplica'; Detalhe = ''; Tamanho = 10; Selecionado = $true; Destino = 'Lixeira'; Reversivel = $null })
            $resumo = Get-ResumoSelecao -Linhas (ConvertTo-LinhaAlvo -Alvos $alvos -Escreve)
            Get-AvisoConfirmacao -Resumo $resumo -Especial $false | Should -Be ' Vai para a Lixeira (dá para recuperar de lá).'
        }
    }
}
