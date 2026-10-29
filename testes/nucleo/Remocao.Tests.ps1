# Remoção (seção 7.2 e 12.3). Tudo dentro da sandbox; a Lixeira é simulada por mock.

BeforeAll {
    . (Join-Path $PSScriptRoot '..\Ajudantes.ps1')
    Import-Module (Join-Path $script:RaizProjeto 'nucleo\Tamandua.Nucleo.psm1') -Force -DisableNameChecking -Global
}

Describe 'Remove-TmdItem' {
    BeforeEach {
        $raiz = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
        New-ArvoreFalsa -Pasta $raiz -Arquivos @{
            'solto.tmp'          = '12345'
            'cache\a.bin'        = 'aaaaaaaaaa'
            'cache\sub\b.bin'    = 'bbbbbbbbbbbbbbbbbbbb'
            'cache\sub\fundo\c'  = 'c'
        } | Out-Null
    }

    It 'apaga um arquivo e informa o espaço liberado' {
        $r = Remove-TmdItem -Caminho "$raiz\solto.tmp" -Raizes $raiz -Id 'x'
        $r.Status | Should -Be 'Feito'
        $r.Liberado | Should -Be 5
        Test-Path "$raiz\solto.tmp" | Should -BeFalse
    }

    It 'apaga uma pasta inteira com subpastas' {
        $r = Remove-TmdItem -Caminho "$raiz\cache" -Raizes $raiz
        $r.Status | Should -Be 'Feito'
        $r.Liberado | Should -Be 31
        Test-Path "$raiz\cache" | Should -BeFalse
        Test-Path "$raiz\solto.tmp" | Should -BeTrue
    }

    It 'apaga arquivo somente leitura' {
        (Get-Item "$raiz\solto.tmp").Attributes = 'ReadOnly'
        (Remove-TmdItem -Caminho "$raiz\solto.tmp" -Raizes $raiz).Status | Should -Be 'Feito'
        Test-Path "$raiz\solto.tmp" | Should -BeFalse
    }

    It '-Simular não muda nenhum byte e diz quanto liberaria' {
        $antes = Get-AssinaturaPasta $raiz
        $r1 = Remove-TmdItem -Caminho "$raiz\cache" -Raizes $raiz -Simular
        $r2 = Remove-TmdItem -Caminho "$raiz\solto.tmp" -Raizes $raiz -Simular
        Get-AssinaturaPasta $raiz | Should -Be $antes
        $r1.Status | Should -Be 'Simulado'
        $r1.Liberado | Should -Be 31
        $r2.Liberado | Should -Be 5
    }

    It 'caminho recusado pela segurança não é tocado' {
        $fora = New-ArvoreFalsa -Pasta (Join-Path $TestDrive "fora-$([guid]::NewGuid().ToString('N'))") -Arquivos @{ 'x.txt' = 'x' }
        $antes = Get-AssinaturaPasta $fora
        $r = Remove-TmdItem -Caminho "$fora\x.txt" -Raizes $raiz
        $r.Status | Should -Be 'Ignorado'
        $r.Motivo | Should -Match 'fora das pastas permitidas'
        Get-AssinaturaPasta $fora | Should -Be $antes
    }

    It 'item que já não existe é ignorado' {
        $r = Remove-TmdItem -Caminho "$raiz\nao-existe.tmp" -Raizes $raiz
        $r.Status | Should -Be 'Ignorado'
        $r.Motivo | Should -Be 'não existe mais'
    }

    Context 'links' {
        BeforeEach {
            $fora = New-ArvoreFalsa -Pasta (Join-Path $TestDrive "importante-$([guid]::NewGuid().ToString('N'))") -Arquivos @{
                'contrato.docx' = 'não apague'; 'fotos\1.jpg' = 'foto'
            }
            $assinaturaFora = Get-AssinaturaPasta $fora
        }

        It 'junction dentro da pasta apagada: o destino fica intacto e o link é pulado' {
            New-Item -ItemType Junction -Path "$raiz\cache\sub\atalho" -Target $fora | Out-Null
            $r = Remove-TmdItem -Caminho "$raiz\cache" -Raizes $raiz
            Get-AssinaturaPasta $fora | Should -Be $assinaturaFora
            $r.Status | Should -Be 'Parcial'
            $r.Motivo | Should -Match '1 link\(s\) ignorado\(s\)'
            Test-Path "$raiz\cache\a.bin" | Should -BeFalse
        }

        It 'junction como alvo: recusado, destino intacto' {
            New-Item -ItemType Junction -Path "$raiz\atalho" -Target $fora | Out-Null
            $r = Remove-TmdItem -Caminho "$raiz\atalho" -Raizes $raiz
            $r.Status | Should -Be 'Ignorado'
            $r.Motivo | Should -Match 'link'
            Get-AssinaturaPasta $fora | Should -Be $assinaturaFora
            Test-Path "$raiz\atalho" | Should -BeTrue
        }

        It 'junction como alvo com -Simular também não mede o destino' {
            New-Item -ItemType Junction -Path "$raiz\atalho" -Target $fora | Out-Null
            (Remove-TmdItem -Caminho "$raiz\atalho" -Raizes $raiz -Simular).Liberado | Should -Be 0
        }
    }

    Context 'arquivos em uso' {
        It 'arquivo travado dentro da pasta: apaga o resto e devolve Parcial' {
            $trava = [IO.File]::Open("$raiz\cache\sub\b.bin", 'Open', 'Read', 'None')
            try {
                $r = Remove-TmdItem -Caminho "$raiz\cache" -Raizes $raiz
            }
            finally {
                $trava.Close()
            }
            $r.Status | Should -Be 'Parcial'
            $r.Motivo | Should -Match '1 em uso'
            Test-Path "$raiz\cache\sub\b.bin" | Should -BeTrue
            Test-Path "$raiz\cache\a.bin" | Should -BeFalse
            $r.Liberado | Should -Be 11
        }

        It 'arquivo travado como alvo: ignorado com motivo, sem exceção' {
            $trava = [IO.File]::Open("$raiz\solto.tmp", 'Open', 'Read', 'None')
            try {
                $r = Remove-TmdItem -Caminho "$raiz\solto.tmp" -Raizes $raiz
            }
            finally {
                $trava.Close()
            }
            $r.Status | Should -Be 'Ignorado'
            $r.Motivo | Should -Match 'em uso'
            Test-Path "$raiz\solto.tmp" | Should -BeTrue
        }
    }

    Context 'Lixeira' {
        It 'envia o caminho completo para a Lixeira e confere que saiu do lugar' {
            Mock Move-TmdParaLixeira -ModuleName Tamandua.Nucleo { [IO.File]::Delete($Caminho) }
            $r = Remove-TmdItem -Caminho "$raiz\cache\..\solto.tmp" -Raizes $raiz -Destino Lixeira
            $r.Status | Should -Be 'Feito'
            $r.Liberado | Should -Be 5
            Should -Invoke Move-TmdParaLixeira -ModuleName Tamandua.Nucleo -Times 1 -Exactly -ParameterFilter { $Caminho -eq "$raiz\solto.tmp" }
        }

        It 'se a Lixeira não tirou o item do lugar, é erro' {
            Mock Move-TmdParaLixeira -ModuleName Tamandua.Nucleo { }
            $r = Remove-TmdItem -Caminho "$raiz\solto.tmp" -Raizes $raiz -Destino Lixeira
            $r.Status | Should -Be 'Erro'
            Test-Path "$raiz\solto.tmp" | Should -BeTrue
        }

        It 'com -Simular nem chama a Lixeira' {
            Mock Move-TmdParaLixeira -ModuleName Tamandua.Nucleo { throw 'não devia chamar' }
            (Remove-TmdItem -Caminho "$raiz\solto.tmp" -Raizes $raiz -Destino Lixeira -Simular).Status | Should -Be 'Simulado'
            Should -Invoke Move-TmdParaLixeira -ModuleName Tamandua.Nucleo -Times 0 -Exactly
        }
    }

    It 'lista de proteção ilegível: não apaga nada' {
        $arquivo = Join-Path $env:TAMANDUA_CONFIG 'protegidos.txt'
        New-Item -ItemType Directory -Path $arquivo -Force | Out-Null
        try {
            $r = Remove-TmdItem -Caminho "$raiz\solto.tmp" -Raizes $raiz
        }
        finally {
            Remove-Item -LiteralPath $arquivo -Force
        }
        $r.Status | Should -Be 'Erro'
        $r.Motivo | Should -Match 'nada foi removido'
        Test-Path "$raiz\solto.tmp" | Should -BeTrue
    }

    It 'registra cada chamada no log de operações' {
        $log = Join-Path $env:TAMANDUA_DADOS 'logs\operacoes.jsonl'
        $antes = if (Test-Path $log) { @(Get-Content $log).Count } else { 0 }
        Remove-TmdItem -Caminho "$raiz\solto.tmp" -Raizes $raiz -Modulo 'teste' -Id 'solto' | Out-Null
        Remove-TmdItem -Caminho "$raiz\cache" -Raizes $raiz -Modulo 'teste' -Simular | Out-Null
        $linhas = @(Get-Content $log -Encoding UTF8)
        $linhas.Count | Should -Be ($antes + 2)
        $ultima = $linhas[-2] | ConvertFrom-Json
        $ultima.Modulo | Should -Be 'teste'
        $ultima.Id | Should -Be 'solto'
        $ultima.Status | Should -Be 'Feito'
        $ultima.Liberado | Should -Be 5
        ($linhas[-1] | ConvertFrom-Json).Simulado | Should -BeTrue
    }
}

Describe 'Measure-TmdTamanho' {
    It 'soma arquivos de subpastas e não entra em links' {
        $pasta = New-ArvoreFalsa -Pasta (Join-Path $TestDrive 'medir') -Arquivos @{ 'a' = '123'; 's\b' = '4567' }
        $grande = New-ArvoreFalsa -Pasta (Join-Path $TestDrive 'grande') -Arquivos @{ 'enorme' = ('x' * 5000) }
        New-Item -ItemType Junction -Path "$pasta\link" -Target $grande | Out-Null
        $m = Measure-TmdTamanho -Caminho $pasta
        $m.Bytes | Should -Be 7
        $m.Arquivos | Should -Be 2
    }

    It 'caminho inexistente mede zero' {
        (Measure-TmdTamanho -Caminho (Join-Path $TestDrive 'nada')).Bytes | Should -Be 0
    }
}

# Opcional porque deixa um arquivinho na Lixeira real: rode com $env:TAMANDUA_TESTE_LIXEIRA = '1'.
Describe 'Lixeira de verdade' -Skip:($env:TAMANDUA_TESTE_LIXEIRA -ne '1') {
    It 'Move-TmdParaLixeira compila e tira um arquivo da sandbox do lugar' {
        $arquivo = Join-Path $TestDrive 'tamandua-teste-lixeira.txt'
        Set-Content -LiteralPath $arquivo -Value 'pode apagar: arquivo de teste do Tamanduá'
        InModuleScope Tamandua.Nucleo -Parameters @{ A = $arquivo } { param($A) Move-TmdParaLixeira -Caminho $A }
        Test-Path -LiteralPath $arquivo | Should -BeFalse
    }
}
