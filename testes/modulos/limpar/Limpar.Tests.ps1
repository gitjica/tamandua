# Módulo limpar. Pastas de TEMP e CrashDumps são sempre da sandbox: por -Pastas (no processo)
# ou por TEMP/TMP/LOCALAPPDATA trocados no processo filho (CLI).

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
            Pastas = @{ 'temp-usuario' = $temp; 'crashdumps' = $crash }
        }
    }
}

Describe 'Find-Alvos' {
    BeforeEach { $cen = New-CenarioLimpeza }

    It 'uma entrada por categoria, contando só o que pode ser apagado' {
        $alvos = @(Find-Alvos -Pastas $cen.Pastas)
        $alvos.Count | Should -Be 2
        $temp = $alvos | Where-Object Id -eq 'temp-usuario'
        $temp.Tamanho | Should -Be 30
        $temp.Detalhe | Should -Match '2 itens'
        $temp.Detalhe | Should -Match '1 recente\(s\) mantido\(s\)'
        $temp.Selecionado | Should -BeTrue
        ($alvos | Where-Object Id -eq 'crashdumps').Tamanho | Should -Be 5
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
        $alvos = @(Find-Alvos -Pastas @{ 'temp-usuario' = $cen.Temp; 'crashdumps' = (Join-Path $cen.Base 'nao-existe') })
        $c = $alvos | Where-Object Id -eq 'crashdumps'
        $c.Detalhe | Should -Be 'pasta não existe'
        $c.Selecionado | Should -BeFalse
        $c.Tamanho | Should -Be 0
    }

    It 'não altera nada' {
        $antes = Get-AssinaturaPasta $cen.Base
        Find-Alvos -Pastas $cen.Pastas | Out-Null
        Get-AssinaturaPasta $cen.Base | Should -Be $antes
    }
}

Describe 'Invoke-Acao' {
    BeforeEach {
        $cen = New-CenarioLimpeza
        $alvos = @(Find-Alvos -Pastas $cen.Pastas)
    }

    It 'apaga o que é velho e mantém o recente' {
        $r = @(Invoke-Acao -Alvos ($alvos | Where-Object Id -eq 'temp-usuario') -Pastas $cen.Pastas)
        $r.Count | Should -Be 1
        $r[0].Status | Should -Be 'Feito'
        $r[0].Liberado | Should -Be 30
        Test-Path "$($cen.Temp)\velho.tmp" | Should -BeFalse
        Test-Path "$($cen.Temp)\instalador" | Should -BeFalse
        Test-Path "$($cen.Temp)\recente.tmp" | Should -BeTrue
        Test-Path $cen.Temp | Should -BeTrue -Because 'a pasta Temp em si nunca é apagada'
    }

    It 'só mexe nas categorias recebidas' {
        Invoke-Acao -Alvos ($alvos | Where-Object Id -eq 'temp-usuario') -Pastas $cen.Pastas | Out-Null
        Test-Path "$($cen.Crash)\app.exe.1234.dmp" | Should -BeTrue
    }

    It 'CrashDumps não tem regra de idade' {
        (Invoke-Acao -Alvos ($alvos | Where-Object Id -eq 'crashdumps') -Pastas $cen.Pastas).Liberado | Should -Be 5
        Test-Path "$($cen.Crash)\app.exe.1234.dmp" | Should -BeFalse
    }

    It '-Simular não muda nenhum byte' {
        $antes = Get-AssinaturaPasta $cen.Base
        $r = @(Invoke-Acao -Alvos $alvos -Pastas $cen.Pastas -Simular)
        Get-AssinaturaPasta $cen.Base | Should -Be $antes
        ($r | ForEach-Object Status | Select-Object -Unique) | Should -Be 'Simulado'
        ($r | Measure-Object Liberado -Sum).Sum | Should -Be 35
    }

    It 'arquivo em uso: apaga o resto e devolve Parcial com o motivo' {
        Set-Idade "$($cen.Temp)\recente.tmp" 48
        $trava = [IO.File]::Open("$($cen.Temp)\recente.tmp", 'Open', 'Read', 'None')
        try {
            $r = Invoke-Acao -Alvos ($alvos | Where-Object Id -eq 'temp-usuario') -Pastas $cen.Pastas
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
        ($alvosNovos | Where-Object Id -eq 'temp-usuario').Mudancas -join ' ' | Should -Match 'link'
        Invoke-Acao -Alvos ($alvosNovos | Where-Object Id -eq 'temp-usuario') -Pastas $cen.Pastas | Out-Null
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
        Invoke-Acao -Alvos ($alvos | Where-Object Id -eq 'crashdumps') -Pastas $cen.Pastas | Out-Null
        $ultima = @(Get-TmdHistorico -Ultimos 1)[0]
        $ultima.Modulo | Should -Be 'limpar'
        $ultima.Id | Should -Be 'crashdumps'
        $ultima.Status | Should -Be 'Feito'
    }
}

Describe 'Pela linha de comando' {
    BeforeEach {
        $cen = New-CenarioLimpeza
        $ambiente = @{ TEMP = $cen.Temp; TMP = $cen.Temp; LOCALAPPDATA = (Join-Path $cen.Base 'Local') }
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

    It '-Simular em módulo só de leitura e em comando do núcleo é erro' {
        $projetoStatus = New-ProjetoFalso -Pai $TestDrive -ModulosReais 'status'
        (Invoke-Tamandua -Raiz $projetoStatus -Argumentos 'status', '-Simular').Codigo | Should -Be 1
        (Invoke-Tamandua -Raiz $projetoStatus -Argumentos 'modulos', '-Sim').Codigo | Should -Be 1
    }
}
