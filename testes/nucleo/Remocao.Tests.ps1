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

    It 'arquivo dentro da pasta que bate com a lista de proteção fica; o resto vai' {
        New-ArvoreFalsa -Pasta "$raiz\cache" -Arquivos @{ 'cofre\senhas.kdbx' = 'k' } | Out-Null
        $r = Remove-TmdItem -Caminho "$raiz\cache" -Raizes $raiz
        $r.Status | Should -Be 'Parcial'
        $r.Motivo | Should -Match '1 protegido\(s\) pela lista de proteção'
        Test-Path "$raiz\cache\cofre\senhas.kdbx" | Should -BeTrue
        Test-Path "$raiz\cache\a.bin" | Should -BeFalse
    }

    It 'arquivo do sistema dentro da pasta (ntuser.dat de um perfil copiado) fica; o resto vai' {
        New-ArvoreFalsa -Pasta "$raiz\cache" -Arquivos @{ 'perfil\NTUSER.DAT' = 'n' } | Out-Null
        $r = Remove-TmdItem -Caminho "$raiz\cache" -Raizes $raiz
        $r.Status | Should -Be 'Parcial'
        Test-Path "$raiz\cache\perfil\NTUSER.DAT" | Should -BeTrue
        Test-Path "$raiz\cache\a.bin" | Should -BeFalse
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

Describe 'Temporários do próprio Tamanduá' {
    It 'cria e apaga só "tamandua-*" direto na pasta temporária' {
        $arq = New-TmdArquivoTemporario -Extensao '.json'
        (Split-Path -Leaf $arq) | Should -BeLike 'tamandua-*.json'
        Set-Content -LiteralPath $arq -Value '{}'
        Remove-TmdArquivoTemporario -Caminho $arq
        Test-Path -LiteralPath $arq | Should -BeFalse
    }

    It 'recusa qualquer outro arquivo' {
        $outro = Join-Path $TestDrive 'tamandua-dentro-de-subpasta.txt'
        Set-Content -LiteralPath $outro -Value 'x'
        { Remove-TmdArquivoTemporario -Caminho $outro } | Should -Throw '*não é um temporário*'
        $semPrefixo = Join-Path ([IO.Path]::GetTempPath()) "outro-$([guid]::NewGuid().ToString('N')).txt"
        Set-Content -LiteralPath $semPrefixo -Value 'x'
        try { { Remove-TmdArquivoTemporario -Caminho $semPrefixo } | Should -Throw '*não é um temporário*' }
        finally { [IO.File]::Delete($semPrefixo) }
        Test-Path -LiteralPath $outro | Should -BeTrue
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
Describe 'Uso de CPU' {
    It 'devolve de 0 a 100; -Desde só espera o que falta do intervalo' {
        $u = Get-TmdUsoCpu -IntervaloMs 100
        $u | Should -BeGreaterOrEqual 0
        $u | Should -BeLessOrEqual 100
        $m = Start-TmdMedidaCpu
        Start-Sleep -Milliseconds 300
        $relogio = [Diagnostics.Stopwatch]::StartNew()
        [void](Get-TmdUsoCpu -Desde $m -IntervaloMs 250)
        $relogio.ElapsedMilliseconds | Should -BeLessThan 100 -Because 'o intervalo já passou enquanto outras coisas eram lidas'
    }
}

Describe 'Esvaziar a Lixeira (falsa)' {
    BeforeEach {
        $env:TAMANDUA_LIXEIRA_TESTE = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
        New-ArvoreFalsa -Pasta $env:TAMANDUA_LIXEIRA_TESTE -Arquivos @{ 'a.txt' = 'aaa'; 'p\b.txt' = 'b' } | Out-Null
        $env:TAMANDUA_DADOS = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
    }
    AfterEach { Remove-Item Env:\TAMANDUA_LIXEIRA_TESTE -ErrorAction SilentlyContinue }

    It 'mede, simula sem apagar, esvazia e registra no log' {
        $l = Get-TmdLixeira
        $l.Itens | Should -Be 2
        $l.Bytes | Should -Be 4
        (Clear-TmdLixeira -Simular -Modulo 'teste').Status | Should -Be 'Simulado'
        (Get-TmdLixeira).Itens | Should -Be 2
        $r = Clear-TmdLixeira -Modulo 'teste' -Id 'lixeira'
        $r.Status | Should -Be 'Feito'
        $r.Liberado | Should -Be 4
        (Get-TmdLixeira).Itens | Should -Be 0
        @(Get-TmdHistorico -Ultimos 1)[0].Caminho | Should -Be 'Lixeira'
    }

    It 'Lixeira falsa fora da pasta temporária é recusada' {
        $env:TAMANDUA_LIXEIRA_TESTE = 'C:\LixeiraFalsaForaDoTemp'
        { Get-TmdLixeira } | Should -Throw '*pasta temporária*'
    }
}

Describe 'Lixeira de verdade' -Skip:($env:TAMANDUA_TESTE_LIXEIRA -ne '1') {
    It 'Move-TmdParaLixeira compila e tira um arquivo da sandbox do lugar' {
        $arquivo = Join-Path $TestDrive 'tamandua-teste-lixeira.txt'
        Set-Content -LiteralPath $arquivo -Value 'pode apagar: arquivo de teste do Tamanduá'
        InModuleScope Tamandua.Nucleo -Parameters @{ A = $arquivo } { param($A) Move-TmdParaLixeira -Caminho $A }
        Test-Path -LiteralPath $arquivo | Should -BeFalse
    }
}

Describe 'Ícones para a grade (só leitura)' {
    It 'tira o PNG de um ícone do Windows, com ou sem índice e aspas' {
        $png = Get-TmdIconePng -Caminho '"%SystemRoot%\System32\shell32.dll",3'
        $png | Should -BeOfType [byte]
        # Assinatura do PNG: 89 50 4E 47.
        $png[0..3] | Should -Be @(0x89, 0x50, 0x4E, 0x47)
    }

    It 'arquivo que não existe ou caminho vazio: nada, sem erro' {
        Get-TmdIconePng -Caminho 'C:\nao\existe\app.exe,0' | Should -BeNullOrEmpty
        Get-TmdIconePng -Caminho '' | Should -BeNullOrEmpty
    }

    It 'nome simples para comparar programas' {
        ConvertTo-TmdNomeSimples 'Mozilla Firefox (x64 pt-BR)' | Should -Be 'mozillafirefoxx64ptbr'
    }
}

Describe 'Onde achar o ícone de um programa (só leitura)' {
    It 'ordem: DisplayIcon, .ico do MSI, exe com o nome do programa, outros exe, desinstalador; nunca msiexec nem unins*' {
        $sr = Join-Path $TestDrive 'win'
        $codigo = '{11111111-2222-3333-4444-555555555555}'
        New-Item -ItemType Directory -Path (Join-Path $sr "Installer\$codigo") -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $sr "Installer\$codigo\produto.ico") -Value 'x'
        $pasta = Join-Path $TestDrive 'Acme Editor'
        New-Item -ItemType Directory -Path $pasta -Force | Out-Null
        foreach ($f in 'outro.exe', 'AcmeEditor.exe', 'unins000.exe', 'leia.txt') { Set-Content -LiteralPath (Join-Path $pasta $f) -Value 'x' }
        $antes = $env:SystemRoot
        try {
            $env:SystemRoot = $sr
            $c = @(Get-TmdCandidatosIcone -DisplayIcon 'C:\x\a.exe,0' -Chave $codigo -Nome 'Acme Editor 2.1' -Pasta "`"$pasta`"" -Desinstalador '"C:\Apps\Acme\Update.exe" --uninstall')
        }
        finally { $env:SystemRoot = $antes }
        $c[0] | Should -Be 'C:\x\a.exe,0'
        $c[1] | Should -BeLike '*\produto.ico'
        $c[2] | Should -BeLike '*\AcmeEditor.exe'
        $c[3] | Should -BeLike '*\outro.exe'
        $c[-1] | Should -Be 'C:\Apps\Acme\Update.exe'
        ($c -join '|') | Should -Not -Match 'unins000|leia\.txt'
        @(Get-TmdCandidatosIcone -Nome 'Acme' -Desinstalador 'MsiExec.exe /X{1}') | Where-Object { $_ -match '(?i)msiexec' } | Should -BeNullOrEmpty
    }

    It 'o primeiro candidato que tem ícone vale; nenhum, nada' {
        $png = Get-TmdIconePngPrimeiro -Caminhos @('C:\nao\existe.exe', '%SystemRoot%\System32\shell32.dll,3')
        $png[0..3] | Should -Be @(0x89, 0x50, 0x4E, 0x47)
        Get-TmdIconePngPrimeiro -Caminhos @('C:\nao\existe.exe') | Should -BeNullOrEmpty
        Get-TmdIconePngPrimeiro -Caminhos @() | Should -BeNullOrEmpty
    }
}
