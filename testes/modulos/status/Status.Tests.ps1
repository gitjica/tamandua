BeforeAll {
    . (Join-Path $PSScriptRoot '..\..\Ajudantes.ps1')
    Import-Module (Join-Path $script:RaizProjeto 'nucleo\Tamandua.Nucleo.psm1') -Force -DisableNameChecking -Global
    Import-Module (Join-Path $script:RaizProjeto 'modulos\status\status.psm1') -Force -DisableNameChecking
}

Describe 'Conversão da leitura em itens' {
    BeforeAll {
        # Leitura de uma máquina saudável; cada teste troca só o que interessa.
        function New-LeituraFalsa {
            param([hashtable]$Trocas = @{})
            $agora = [datetime]'2026-10-29 12:00'
            $leitura = [ordered]@{
                Agora     = $agora
                Sistema   = [pscustomobject]@{ Nome = 'Windows 11 Teste'; Build = '26300'; Inicio = $agora.AddHours(-5) }
                Memoria   = [pscustomobject]@{ TotalBytes = 16GB; LivreBytes = 8GB }
                Cpu       = [pscustomobject]@{ Percentual = 18 }
                Discos    = @([pscustomobject]@{ Letra = 'C:'; Rotulo = ''; TotalBytes = 500GB; LivreBytes = 250GB })
                Rede      = @([pscustomobject]@{ Indice = 3; Nome = 'Ethernet'; IPv4 = '192.168.0.10' })
                Bateria   = @()
                Processos = @([pscustomobject]@{ Nome = 'firefox'; MemoriaBytes = 1GB })
            }
            foreach ($k in $Trocas.Keys) { $leitura[$k] = $Trocas[$k] }
            [pscustomobject]$leitura
        }
        function Get-ItemPorId($Itens, $Id) { $Itens | Where-Object Id -eq $Id }
    }

    It 'máquina saudável: nota 100, tudo normal, ids únicos' {
        $itens = InModuleScope status -Parameters @{ L = (New-LeituraFalsa) } { param($L) ConvertTo-AlvoStatus -Leitura $L }
        $itens[0].Id | Should -Be 'saude'
        $itens[0].Detalhe | Should -Be '100 / 100'
        @($itens | Where-Object Nivel -ne 'Normal') | Should -BeNullOrEmpty
        @($itens.Id | Select-Object -Unique).Count | Should -Be $itens.Count
        (Get-ItemPorId $itens 'cpu').Detalhe | Should -Be '18%'
        (Get-ItemPorId $itens 'memoria').Valor | Should -Be 50
        (Get-ItemPorId $itens 'disco-c').Detalhe | Should -Match '50% livre'
        (Get-ItemPorId $itens 'rede-3').Detalhe | Should -Be '192.168.0.10'
        (Get-ItemPorId $itens 'sistema-ligado').Detalhe | Should -Be '5 h 0 min'
        Get-ItemPorId $itens 'bateria' | Should -BeNullOrEmpty -Because 'desktop sem bateria não mostra bateria'
    }

    It 'todo item tem as propriedades do contrato' {
        $itens = InModuleScope status -Parameters @{ L = (New-LeituraFalsa) } { param($L) ConvertTo-AlvoStatus -Leitura $L }
        foreach ($i in $itens) {
            foreach ($p in 'Id', 'Nome', 'Categoria', 'Estado', 'Detalhe', 'Nivel', 'Valor') {
                $i.PSObject.Properties.Name | Should -Contain $p
            }
        }
    }

    It 'disco com <Livre>% livre fica <Nivel>' -ForEach @(
        @{ Livre = 50; Nivel = 'Normal' }
        @{ Livre = 10; Nivel = 'Atencao' }
        @{ Livre = 5; Nivel = 'Critico' }
    ) {
        $disco = [pscustomobject]@{ Letra = 'D:'; Rotulo = 'Dados'; TotalBytes = 1000GB; LivreBytes = [int64](10GB * $Livre) }
        $itens = InModuleScope status -Parameters @{ L = (New-LeituraFalsa @{ Discos = @($disco) }) } { param($L) ConvertTo-AlvoStatus -Leitura $L }
        $d = Get-ItemPorId $itens 'disco-d'
        $d.Nivel | Should -Be $Nivel
        $d.Nome | Should -Be 'Disco D: (Dados)'
    }

    It 'disco com menos de 2 GB livres é crítico mesmo com % alto' {
        $disco = [pscustomobject]@{ Letra = 'E:'; Rotulo = ''; TotalBytes = 4GB; LivreBytes = 1GB }
        $itens = InModuleScope status -Parameters @{ L = (New-LeituraFalsa @{ Discos = @($disco) }) } { param($L) ConvertTo-AlvoStatus -Leitura $L }
        (Get-ItemPorId $itens 'disco-e').Nivel | Should -Be 'Critico'
    }

    It 'CPU <Cpu>% fica <Nivel>' -ForEach @(
        @{ Cpu = 50; Nivel = 'Normal' }, @{ Cpu = 85; Nivel = 'Atencao' }, @{ Cpu = 99; Nivel = 'Critico' }
    ) {
        $l = New-LeituraFalsa @{ Cpu = [pscustomobject]@{ Percentual = $Cpu } }
        $itens = InModuleScope status -Parameters @{ L = $l } { param($L) ConvertTo-AlvoStatus -Leitura $L }
        (Get-ItemPorId $itens 'cpu').Nivel | Should -Be $Nivel
    }

    It 'bateria a <Pct>% <Situacao> fica <Nivel>' -ForEach @(
        @{ Pct = 80; Carregando = $false; Situacao = 'na bateria'; Nivel = 'Normal' }
        @{ Pct = 15; Carregando = $false; Situacao = 'na bateria'; Nivel = 'Atencao' }
        @{ Pct = 5; Carregando = $false; Situacao = 'na bateria'; Nivel = 'Critico' }
        @{ Pct = 5; Carregando = $true; Situacao = 'na tomada'; Nivel = 'Normal' }
    ) {
        $l = New-LeituraFalsa @{ Bateria = @([pscustomobject]@{ Percentual = $Pct; Carregando = $Carregando }) }
        $itens = InModuleScope status -Parameters @{ L = $l } { param($L) ConvertTo-AlvoStatus -Leitura $L }
        $b = Get-ItemPorId $itens 'bateria'
        $b.Nivel | Should -Be $Nivel
        $b.Detalhe | Should -Be "$Pct% ($Situacao)"
    }

    It 'ligado há mais de 14 dias pede reinício' {
        $agora = [datetime]'2026-10-29 12:00'
        $l = New-LeituraFalsa @{ Sistema = [pscustomobject]@{ Nome = 'W'; Build = '1'; Inicio = $agora.AddDays(-20).AddHours(-3) } }
        $itens = InModuleScope status -Parameters @{ L = $l } { param($L) ConvertTo-AlvoStatus -Leitura $L }
        $ligado = Get-ItemPorId $itens 'sistema-ligado'
        $ligado.Nivel | Should -Be 'Atencao'
        $ligado.Detalhe | Should -Match '^20 d 3 h - reinicie'
    }

    It 'nota de saúde cai com problemas e nunca fica negativa' {
        $discos = 1..6 | ForEach-Object { [pscustomobject]@{ Letra = "$([char](67 + $_)):"; Rotulo = ''; TotalBytes = 100GB; LivreBytes = 1GB } }
        $l = New-LeituraFalsa @{ Discos = @($discos); Cpu = [pscustomobject]@{ Percentual = 85 } }
        $itens = InModuleScope status -Parameters @{ L = $l } { param($L) ConvertTo-AlvoStatus -Leitura $L }
        $itens[0].Valor | Should -Be 0
        $itens[0].Nivel | Should -Be 'Critico'
        $itens[0].Detalhe | Should -Match '7 pontos de atenção'
    }

    It 'seção que falhou na leitura aparece como desconhecida e não derruba as outras' {
        $l = New-LeituraFalsa @{ Cpu = $null; Discos = $null; Rede = $null; Bateria = $null; Processos = $null; Sistema = $null; Memoria = $null }
        $itens = InModuleScope status -Parameters @{ L = $l } { param($L) ConvertTo-AlvoStatus -Leitura $L }
        foreach ($id in 'sistema-windows', 'cpu', 'memoria', 'discos', 'rede', 'bateria', 'processos') {
            (Get-ItemPorId $itens $id).Estado | Should -Be 'Desconhecido'
        }
        $itens[0].Detalhe | Should -Be '100 / 100' -Because 'o que não foi lido não conta como problema'
    }

    It 'sem conexão de rede ativa vira ponto de atenção' {
        $itens = InModuleScope status -Parameters @{ L = (New-LeituraFalsa @{ Rede = @() }) } { param($L) ConvertTo-AlvoStatus -Leitura $L }
        (Get-ItemPorId $itens 'rede').Nivel | Should -Be 'Atencao'
    }
}

Describe 'Leitura do sistema' {
    It 'uma classe CIM que falha não impede as outras seções' {
        # Pester 6 não cai no comando original quando o filtro não bate; o mock padrão chama o real.
        Mock Get-CimInstance -ModuleName status { CimCmdlets\Get-CimInstance @PesterBoundParameters }
        Mock Get-CimInstance -ModuleName status -ParameterFilter { $ClassName -eq 'Win32_Battery' } { throw 'WMI corrompido' }
        $l = InModuleScope status { Get-LeituraSistema }
        $l.Bateria | Should -BeNullOrEmpty
        $null -eq $l.Bateria | Should -BeTrue
        $l.Sistema | Should -Not -BeNullOrEmpty
        $l.Discos.Count | Should -BeGreaterThan 0
    }

    It 'lê o sistema real (só leitura) com todas as seções' {
        $l = InModuleScope status { Get-LeituraSistema }
        $l.Sistema.Nome | Should -Match 'Windows'
        $l.Memoria.TotalBytes | Should -BeGreaterThan 0
        $null -eq $l.Discos | Should -BeFalse
        $null -eq $l.Bateria | Should -BeFalse -Because 'sem bateria é lista vazia, não falha'
        $l.Processos.Count | Should -BeGreaterThan 0
    }

    It 'Test-Requisitos diz que não dá quando o CIM não responde' {
        Mock Get-CimInstance -ModuleName status { throw 'serviço WMI parado' }
        $r = InModuleScope status { Test-Requisitos }
        $r.Ok | Should -BeFalse
        $r.Motivo | Should -Match 'serviço WMI parado'
    }
}

Describe 'Pelo programa' {
    It 'tamandua status roda no sistema real e mostra o painel' {
        $r = Invoke-Tamandua -Raiz $script:RaizProjeto -Argumentos 'status'
        $r.Codigo | Should -Be 0
        $r.Saida | Should -Match 'Saúde\s+\d+ / 100'
        # O WMI às vezes não devolve a carga da CPU; aí o item aparece como não lido, e isso é o comportamento certo.
        $r.Saida | Should -Match 'CPU\s+(\d+%|não foi possível ler)'
        $r.Saida | Should -Match 'Disco C:'
        $r.Tudo | Should -Not -Match 'At line|CategoryInfo'
    }

    It 'status aparece como ok em tamandua modulos' {
        (Invoke-Tamandua -Raiz $script:RaizProjeto -Argumentos 'modulos').Saida | Should -Match 'status\s+ok'
    }
}
