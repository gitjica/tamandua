# Módulo limpar. Toda pasta é da sandbox: TAMANDUA_LIMPAR_RAIZ troca Windows, ProgramData, AppData e Steam por
# subpastas dela, e o TEMP vem por -Pastas (no processo) ou pela variável TEMP do processo filho (CLI).
# A Lixeira é uma pasta da sandbox (TAMANDUA_LIXEIRA_TESTE). Nada aqui toca no sistema real nem pede admin.

BeforeAll {
    . (Join-Path $PSScriptRoot '..\..\Ajudantes.ps1')
    Import-Module (Join-Path $script:RaizProjeto 'nucleo\Tamandua.Nucleo.psm1') -Force -DisableNameChecking -Global
    Import-Module (Join-Path $script:RaizProjeto 'modulos\limpar\limpar.psm1') -Force -DisableNameChecking

    # TEMP com dois itens velhos e um recente; CrashDumps com um despejo (sem regra de idade).
    function New-CenarioLimpeza {
        param([string]$Base = (Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))))
        $temp = New-ArvoreFalsa -Pasta (Join-Path $Base 'Temp') -Arquivos @{
            'velho.tmp'              = 'aaaaaaaaaa'
            'instalador\pacote.cab'  = 'bbbbbbbbbbbbbbbbbbbb'
            'recente.tmp'            = 'ccc'
        }
        $crash = New-ArvoreFalsa -Pasta (Join-Path $Base 'Local\CrashDumps') -Arquivos @{ 'app.exe.1234.dmp' = 'ddddd' }
        Set-Idade "$temp\velho.tmp" 48
        Set-Idade "$temp\instalador" 72
        Set-Idade "$temp\recente.tmp" 1
        [pscustomobject]@{
            Base   = $Base
            Temp   = $temp
            Crash  = $crash
            Pastas = @{ 'temp-usuario' = $temp }
        }
    }
    function Get-Alvo { param($Alvos, $Id) @($Alvos | Where-Object Id -eq $Id)[0] }
}

Describe 'Módulo limpar' {
    BeforeEach {
        $cen = New-CenarioLimpeza
        $env:TAMANDUA_LIMPAR_RAIZ = $cen.Base
        $env:TAMANDUA_LIXEIRA_TESTE = Join-Path $cen.Base 'Lixeira'
        # Pester 6: o mock com filtro não cai no comando real; nos testes nenhum programa está aberto.
        Mock Get-ProcessoAberto -ModuleName limpar { @() }
    }
    AfterEach { Remove-Item Env:\TAMANDUA_LIMPAR_RAIZ, Env:\TAMANDUA_LIXEIRA_TESTE -ErrorAction SilentlyContinue }

    Describe 'Find-Alvos' {
        It 'uma entrada por categoria, contando só o que pode ser apagado' {
            $alvos = @(Find-Alvos -Pastas $cen.Pastas)
            $temp = Get-Alvo $alvos 'temp-usuario'
            $temp.Tamanho | Should -Be 30
            $temp.Detalhe | Should -Match '2 itens'
            $temp.Detalhe | Should -Match '1 recente\(s\) mantido\(s\)'
            $temp.Selecionado | Should -BeTrue
            (Get-Alvo $alvos 'crashdumps').Tamanho | Should -Be 5
        }

        It 'categorias do sistema sempre aparecem; as de programas só se o programa existir' {
            $ids = @(Find-Alvos -Pastas $cen.Pastas | ForEach-Object Id)
            foreach ($id in 'temp-usuario', 'temp-windows', 'crashdumps', 'relatorios-erro', 'relatorios-erro-sistema', 'minidump', 'logs-windows', 'windows-update', 'otimizacao-entrega', 'lixeira') {
                $ids | Should -Contain $id
            }
            foreach ($id in 'chrome', 'edge', 'brave', 'firefox', 'discord', 'spotify', 'steam', 'epic', 'battlenet', 'ubisoft', 'shaders') {
                $ids | Should -Not -Contain $id
            }
        }

        It 'tem todas as propriedades de alvo de módulo que escreve' {
            foreach ($a in Find-Alvos -Pastas $cen.Pastas) {
                foreach ($p in 'Id', 'Nome', 'Categoria', 'Estado', 'Detalhe', 'Caminho', 'Tamanho', 'Risco', 'Selecionado', 'Destino', 'RequerAdmin', 'Reversivel', 'Mudancas') {
                    $a.PSObject.Properties.Name | Should -Contain $p
                }
                $a.Mudancas.Count | Should -BeGreaterThan 0
            }
        }

        It 'pasta que não existe: mostra e não vem marcada' {
            $c = Get-Alvo @(Find-Alvos -Pastas @{ 'temp-usuario' = $cen.Temp; 'crashdumps' = (Join-Path $cen.Base 'nao-existe') }) 'crashdumps'
            $c.Detalhe | Should -Be 'pasta não existe'
            $c.Selecionado | Should -BeFalse
            $c.Tamanho | Should -Be 0
        }

        It 'na sandbox nada pede admin; logs, minidump e Windows Update não vêm marcados' {
            New-ArvoreFalsa -Pasta (Join-Path $cen.Base 'Windows\Minidump') -Arquivos @{ 'a.dmp' = 'x' } | Out-Null
            $alvos = @(Find-Alvos -Pastas $cen.Pastas)
            @($alvos | Where-Object RequerAdmin).Count | Should -Be 0
            (Get-Alvo $alvos 'minidump').Selecionado | Should -BeFalse
            (Get-Alvo $alvos 'lixeira').Selecionado | Should -BeFalse
        }

        It 'TAMANDUA_LIMPAR_RAIZ fora da pasta temporária é recusada' {
            $env:TAMANDUA_LIMPAR_RAIZ = 'C:\Windows'
            { Find-Alvos } | Should -Throw '*pasta temporária*'
        }

        It 'não altera nada' {
            $antes = Get-AssinaturaPasta $cen.Base
            Find-Alvos -Pastas $cen.Pastas | Out-Null
            Get-AssinaturaPasta $cen.Base | Should -Be $antes
        }
    }

    Describe 'Invoke-Acao' {
        BeforeEach { $alvos = @(Find-Alvos -Pastas $cen.Pastas) }

        It 'apaga o que é velho e mantém o recente' {
            $r = @(Invoke-Acao -Alvos (Get-Alvo $alvos 'temp-usuario') -Pastas $cen.Pastas)
            $r.Count | Should -Be 1
            $r[0].Status | Should -Be 'Feito'
            $r[0].Liberado | Should -Be 30
            Test-Path "$($cen.Temp)\velho.tmp" | Should -BeFalse
            Test-Path "$($cen.Temp)\instalador" | Should -BeFalse
            Test-Path "$($cen.Temp)\recente.tmp" | Should -BeTrue
            Test-Path $cen.Temp | Should -BeTrue -Because 'a pasta Temp em si nunca é apagada'
        }

        It 'só mexe nas categorias recebidas' {
            Invoke-Acao -Alvos (Get-Alvo $alvos 'temp-usuario') -Pastas $cen.Pastas | Out-Null
            Test-Path "$($cen.Crash)\app.exe.1234.dmp" | Should -BeTrue
        }

        It 'CrashDumps não tem regra de idade' {
            (Invoke-Acao -Alvos (Get-Alvo $alvos 'crashdumps') -Pastas $cen.Pastas).Liberado | Should -Be 5
            Test-Path "$($cen.Crash)\app.exe.1234.dmp" | Should -BeFalse
        }

        It '-Simular não muda nenhum byte' {
            $antes = Get-AssinaturaPasta $cen.Base
            $r = @(Invoke-Acao -Alvos ($alvos | Where-Object Id -in 'temp-usuario', 'crashdumps') -Pastas $cen.Pastas -Simular)
            Get-AssinaturaPasta $cen.Base | Should -Be $antes
            ($r | ForEach-Object Status | Select-Object -Unique) | Should -Be 'Simulado'
            ($r | Measure-Object Liberado -Sum).Sum | Should -Be 35
        }

        It 'arquivo em uso: apaga o resto e devolve Parcial com o motivo' {
            Set-Idade "$($cen.Temp)\recente.tmp" 48
            $trava = [IO.File]::Open("$($cen.Temp)\recente.tmp", 'Open', 'Read', 'None')
            try {
                $r = Invoke-Acao -Alvos (Get-Alvo $alvos 'temp-usuario') -Pastas $cen.Pastas
            }
            finally {
                $trava.Close()
            }
            $r.Status | Should -Be 'Parcial'
            $r.Motivo | Should -Match '1 pulado\(s\).*em uso'
            Test-Path "$($cen.Temp)\velho.tmp" | Should -BeFalse
        }

        It 'link dentro do Temp: destino intacto, link não é apagado' {
            $fora = New-ArvoreFalsa -Pasta (Join-Path $cen.Base 'Importante') -Arquivos @{ 'contrato.docx' = 'x' }
            $assinatura = Get-AssinaturaPasta $fora
            New-Item -ItemType Junction -Path "$($cen.Temp)\atalho" -Target $fora | Out-Null
            Set-Idade "$($cen.Temp)\atalho" 48
            $alvosNovos = @(Find-Alvos -Pastas $cen.Pastas)
            (Get-Alvo $alvosNovos 'temp-usuario').Mudancas -join ' ' | Should -Match 'link'
            Invoke-Acao -Alvos (Get-Alvo $alvosNovos 'temp-usuario') -Pastas $cen.Pastas | Out-Null
            Get-AssinaturaPasta $fora | Should -Be $assinatura
            Test-Path "$($cen.Temp)\atalho" | Should -BeTrue
        }

        It 'não confia no Caminho do alvo recebido' {
            $outra = New-ArvoreFalsa -Pasta (Join-Path $cen.Base 'Documentos') -Arquivos @{ 'tese.docx' = 'x' }
            Set-Idade "$outra\tese.docx" 100
            $falso = [pscustomobject]@{ Id = 'temp-usuario'; Caminho = $outra }
            Invoke-Acao -Alvos @($falso) -Pastas $cen.Pastas | Out-Null
            Test-Path "$outra\tese.docx" | Should -BeTrue
        }

        It 'categoria desconhecida vira erro, sem apagar nada' {
            $antes = Get-AssinaturaPasta $cen.Base
            $r = Invoke-Acao -Alvos @([pscustomobject]@{ Id = 'system32'; Caminho = 'C:\Windows\System32' }) -Pastas $cen.Pastas
            $r.Status | Should -Be 'Erro'
            Get-AssinaturaPasta $cen.Base | Should -Be $antes
        }

        It 'registra no log com o módulo e a categoria' {
            Invoke-Acao -Alvos (Get-Alvo $alvos 'crashdumps') -Pastas $cen.Pastas | Out-Null
            $ultima = @(Get-TmdHistorico -Ultimos 1)[0]
            $ultima.Modulo | Should -Be 'limpar'
            $ultima.Id | Should -Be 'crashdumps'
            $ultima.Status | Should -Be 'Feito'
        }
    }

    Describe 'Categorias do swept' {
        It 'navegador Chromium: só as pastas de cache dos perfis; histórico, cookies e senhas ficam' {
            $dados = Join-Path $cen.Base 'Local\Google\Chrome\User Data'
            New-ArvoreFalsa -Pasta $dados -Arquivos @{
                'Default\Cache\Cache_Data\f_000001' = 'aaaa'
                'Default\Code Cache\js\index'       = 'bb'
                'Default\History'                   = 'historico'
                'Default\Network\Cookies'           = 'cookies'
                'Default\Login Data'                = 'senhas'
                'Profile 1\GPUCache\data_0'         = 'c'
                'Perfil sem marca\Cache\x'          = 'nao e perfil'
            } | Out-Null
            $chrome = Get-Alvo @(Find-Alvos -Pastas $cen.Pastas) 'chrome'
            $chrome.Tamanho | Should -Be 7
            $chrome.Selecionado | Should -BeTrue
            $r = Invoke-Acao -Alvos $chrome -Pastas $cen.Pastas
            $r.Status | Should -Be 'Feito'
            Test-Path "$dados\Default\Cache\Cache_Data" | Should -BeFalse
            Test-Path "$dados\Profile 1\GPUCache\data_0" | Should -BeFalse
            Test-Path "$dados\Default\Cache" | Should -BeTrue -Because 'a pasta de cache fica, só o conteúdo sai'
            foreach ($f in 'Default\History', 'Default\Network\Cookies', 'Default\Login Data', 'Perfil sem marca\Cache\x') { Test-Path "$dados\$f" | Should -BeTrue }
        }

        It 'Firefox: cache2, startupCache e thumbnails de cada perfil' {
            $perfis = Join-Path $cen.Base 'Local\Mozilla\Firefox\Profiles'
            New-ArvoreFalsa -Pasta $perfis -Arquivos @{ 'abc.default\cache2\entries\1' = 'aa'; 'abc.default\places.sqlite' = 'hist' } | Out-Null
            $r = Invoke-Acao -Alvos (Get-Alvo @(Find-Alvos -Pastas $cen.Pastas) 'firefox') -Pastas $cen.Pastas
            $r.Liberado | Should -Be 2
            Test-Path "$perfis\abc.default\places.sqlite" | Should -BeTrue
        }

        It 'programa aberto: não vem marcado, não dá para marcar e nada é apagado' {
            New-ArvoreFalsa -Pasta (Join-Path $cen.Base 'Roaming\discord\Cache') -Arquivos @{ 'f' = 'abc' } | Out-Null
            Mock Get-ProcessoAberto -ModuleName limpar { @('Discord') }
            $discord = Get-Alvo @(Find-Alvos -Pastas $cen.Pastas) 'discord'
            $discord.Selecionado | Should -BeFalse
            $discord.Selecionavel | Should -BeFalse
            $discord.Detalhe | Should -Match '^feche o Discord'
            $r = Invoke-Acao -Alvos $discord -Pastas $cen.Pastas
            $r.Status | Should -Be 'Ignorado'
            $r.Motivo | Should -Match 'feche o Discord'
            Test-Path (Join-Path $cen.Base 'Roaming\discord\Cache\f') | Should -BeTrue
        }

        It 'logs do Windows: só .log com mais de 7 dias, em qualquer subpasta' {
            $logs = New-ArvoreFalsa -Pasta (Join-Path $cen.Base 'Windows\Logs') -Arquivos @{ 'CBS\velho.log' = 'aaaa'; 'CBS\novo.log' = 'b'; 'CBS\pacote.cab' = 'cc'; 'DISM\dism.log' = 'ddd' }
            Set-Idade "$logs\CBS\velho.log" 200
            Set-Idade "$logs\CBS\pacote.cab" 200
            Set-Idade "$logs\DISM\dism.log" 300
            $a = Get-Alvo @(Find-Alvos -Pastas $cen.Pastas) 'logs-windows'
            $a.Tamanho | Should -Be 7
            Invoke-Acao -Alvos $a -Pastas $cen.Pastas | Out-Null
            Test-Path "$logs\CBS\velho.log" | Should -BeFalse
            Test-Path "$logs\DISM\dism.log" | Should -BeFalse
            Test-Path "$logs\CBS\novo.log" | Should -BeTrue
            Test-Path "$logs\CBS\pacote.cab" | Should -BeTrue
        }

        It 'Steam: logs, dumps e cache da loja; jogos ficam' {
            $steam = New-ArvoreFalsa -Pasta (Join-Path $cen.Base 'Steam') -Arquivos @{ 'logs\content_log.txt' = 'aa'; 'appcache\httpcache\x' = 'b'; 'appcache\appinfo.vdf' = 'info'; 'steamapps\common\Jogo\jogo.exe' = 'jogo' }
            Invoke-Acao -Alvos (Get-Alvo @(Find-Alvos -Pastas $cen.Pastas) 'steam') -Pastas $cen.Pastas | Out-Null
            Test-Path "$steam\logs\content_log.txt" | Should -BeFalse
            Test-Path "$steam\appcache\httpcache\x" | Should -BeFalse
            Test-Path "$steam\appcache\appinfo.vdf" | Should -BeTrue
            Test-Path "$steam\steamapps\common\Jogo\jogo.exe" | Should -BeTrue
        }

        It 'Lixeira: mostra o que tem, não vem marcada; simular não apaga; executar esvazia' {
            New-ArvoreFalsa -Pasta $env:TAMANDUA_LIXEIRA_TESTE -Arquivos @{ 'a.txt' = 'aaaa'; 'pasta\b.txt' = 'bb' } | Out-Null
            $l = Get-Alvo @(Find-Alvos -Pastas $cen.Pastas) 'lixeira'
            $l.Tamanho | Should -Be 6
            $l.Detalhe | Should -Match '2 itens'
            $l.Selecionado | Should -BeFalse
            (Invoke-Acao -Alvos $l -Pastas $cen.Pastas -Simular).Status | Should -Be 'Simulado'
            @(Get-ChildItem -LiteralPath $env:TAMANDUA_LIXEIRA_TESTE).Count | Should -Be 2
            $r = Invoke-Acao -Alvos $l -Pastas $cen.Pastas
            $r.Status | Should -Be 'Feito'
            $r.Liberado | Should -Be 6
            @(Get-ChildItem -LiteralPath $env:TAMANDUA_LIXEIRA_TESTE).Count | Should -Be 0
        }
    }

    Describe 'Pela linha de comando' {
        BeforeEach {
            $ambiente = @{ TEMP = $cen.Temp; TMP = $cen.Temp; TAMANDUA_LIMPAR_RAIZ = $cen.Base; TAMANDUA_LIXEIRA_TESTE = $env:TAMANDUA_LIXEIRA_TESTE }
            $projeto = New-ProjetoFalso -Pai $TestDrive -ModulosReais 'limpar'
        }

        It '-Simular mostra quanto liberaria e não apaga nada' {
            $r = Invoke-Tamandua -Raiz $projeto -Argumentos 'limpar', '-Simular' -Ambiente $ambiente
            $r.Codigo | Should -Be 0
            $r.Saida | Should -Match 'Simulação'
            $r.Saida | Should -Match '\[x\] Temporários do usuário'
            Test-Path "$($cen.Temp)\velho.tmp" | Should -BeTrue
            Test-Path "$($cen.Crash)\app.exe.1234.dmp" | Should -BeTrue
        }

        It 'sem -Sim e sem console interativo: cancela (código 3) e não apaga nada' {
            $r = Invoke-Tamandua -Raiz $projeto -Argumentos 'limpar' -Ambiente $ambiente
            $r.Codigo | Should -Be 3
            $r.Saida | Should -Match 'Nada foi alterado'
            Test-Path "$($cen.Temp)\velho.tmp" | Should -BeTrue
        }

        It '-Sim limpa, mantém o recente e aparece no histórico' {
            $r = Invoke-Tamandua -Raiz $projeto -Argumentos 'limpar', '-Sim' -Ambiente $ambiente
            $r.Codigo | Should -Be 0
            $r.Saida | Should -Match 'Liberado'
            Test-Path "$($cen.Temp)\velho.tmp" | Should -BeFalse
            Test-Path "$($cen.Crash)\app.exe.1234.dmp" | Should -BeFalse
            Test-Path "$($cen.Temp)\recente.tmp" | Should -BeTrue
            (Invoke-Tamandua -Raiz $projeto -Argumentos 'historico').Saida | Should -Match 'limpar'
        }

        It 'argumento solto depois do módulo é erro (nenhum módulo recebe pasta)' {
            $r = Invoke-Tamandua -Raiz $projeto -Argumentos 'limpar', 'C:\Users' -Ambiente $ambiente
            $r.Codigo | Should -Be 1
            $r.Saida | Should -Match "não aceita: C:\\Users"
        }

        It '-Simular em módulo só de leitura e em comando do núcleo é erro' {
            $projetoStatus = New-ProjetoFalso -Pai $TestDrive -ModulosReais 'status'
            (Invoke-Tamandua -Raiz $projetoStatus -Argumentos 'status', '-Simular').Codigo | Should -Be 1
            (Invoke-Tamandua -Raiz $projetoStatus -Argumentos 'modulos', '-Sim').Codigo | Should -Be 1
        }
    }
}
