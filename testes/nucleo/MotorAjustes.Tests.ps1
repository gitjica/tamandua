# Motor de ajustes (seção 7.3 e 12.3). Registro sempre numa chave de teste em HKCU:\Software\TamanduaTestes;
# serviços e tarefas são trocados por Mock; scripts escrevem só na sandbox.

BeforeAll {
    . (Join-Path $PSScriptRoot '..\Ajudantes.ps1')
    Import-Module (Join-Path $script:RaizProjeto 'nucleo\Tamandua.Nucleo.psm1') -Force -DisableNameChecking -Global
    $script:ChaveTestes = "HKCU:\Software\TamanduaTestes\$([guid]::NewGuid().ToString('N'))"

    # Raiz de registro nova por teste; os caminhos do ajuste (HKCU:\ e HKLM:\) são redirecionados para dentro dela.
    function New-RaizRegistro { "$script:ChaveTestes\$([guid]::NewGuid().ToString('N'))" }
    function Get-ValorSandbox([string]$Raiz, [string]$Caminho, [string]$Nome) {
        InModuleScope Tamandua.Nucleo -Parameters @{ R = $Raiz; C = $Caminho; N = $Nome } { param($R, $C, $N) Read-TmdRegistro -Caminho $C -Nome $N -RaizRegistro $R }
    }
    function Set-ValorSandbox([string]$Raiz, [string]$Caminho, [string]$Nome, $Valor, [string]$Tipo) {
        InModuleScope Tamandua.Nucleo -Parameters @{ R = $Raiz; C = $Caminho; N = $Nome; V = $Valor; T = $Tipo } {
            param($R, $C, $N, $V, $T) Write-TmdRegistro -Caminho $C -Nome $N -Valor $V -TipoValor $T -RaizRegistro $R
        }
    }
    function New-Ajuste([string]$Id, [object[]]$Mudancas, [bool]$RequerAdmin = $false) {
        [pscustomobject]@{ id = $Id; nome = "Ajuste $Id"; requerAdmin = $RequerAdmin; mudancas = $Mudancas }
    }
    function New-MudancaRegistro([string]$Nome, $Valor, [string]$Tipo = 'DWord', $Padrao = $null, [string]$Caminho = 'HKCU:\Software\Teste\Sub') {
        [pscustomobject]@{ tipo = 'Registro'; caminho = $Caminho; nome = $Nome; valor = $Valor; tipoValor = $Tipo; padraoWindows = $Padrao }
    }
}

AfterAll {
    if (Test-Path -LiteralPath $script:ChaveTestes) { Remove-Item -LiteralPath $script:ChaveTestes -Recurse -Force }
    # Não deixa nem a chave-mãe vazia no registro do usuário.
    $mae = 'HKCU:\Software\TamanduaTestes'
    if ((Test-Path -LiteralPath $mae) -and @(Get-ChildItem -LiteralPath $mae).Count -eq 0) { Remove-Item -LiteralPath $mae -Force }
}

Describe 'Registro: aplicar e desfazer' {
    BeforeEach {
        $env:TAMANDUA_DADOS = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
        $raiz = New-RaizRegistro
    }

    It 'valor que não existia: aplica, guarda "não existia" e o desfazer apaga o valor' {
        $a = New-Ajuste 'priv-teste' @(New-MudancaRegistro 'Telemetria' 0)
        $r = Set-TmdAjuste -Ajuste $a -RaizRegistro $raiz
        $r.Status | Should -Be 'Feito'
        (Get-ValorSandbox $raiz 'HKCU:\Software\Teste\Sub' 'Telemetria').Valor | Should -Be 0
        Get-TmdEstadoAjuste -Ajuste $a -RaizRegistro $raiz | Should -Be 'Aplicado'
        Test-TmdAjusteReversivel -Id 'priv-teste' | Should -BeTrue

        $d = Undo-TmdAjuste -Id 'priv-teste' -RaizRegistro $raiz
        $d.Status | Should -Be 'Feito'
        (Get-ValorSandbox $raiz 'HKCU:\Software\Teste\Sub' 'Telemetria').Existe | Should -BeFalse
        Get-TmdEstadoAjuste -Ajuste $a -RaizRegistro $raiz | Should -Be 'NaoAplicado'
        Test-TmdAjusteReversivel -Id 'priv-teste' | Should -BeFalse
    }

    It 'restaura exatamente o valor e o tipo de antes: <Tipo>' -ForEach @(
        @{ Tipo = 'String'; Antes = 'antigo'; Novo = 'novo' }
        @{ Tipo = 'ExpandString'; Antes = '%USERPROFILE%\pasta'; Novo = 'C:\outra' }
        @{ Tipo = 'DWord'; Antes = 4294967295; Novo = 0 }
        @{ Tipo = 'QWord'; Antes = 9007199254740993; Novo = 1 }
        @{ Tipo = 'Binary'; Antes = [byte[]](1, 2, 255); Novo = [byte[]](0) }
        @{ Tipo = 'MultiString'; Antes = [string[]]('a', 'b c'); Novo = [string[]]('x') }
    ) {
        Set-ValorSandbox $raiz 'HKCU:\Software\Teste\Sub' 'Valor' $Antes $Tipo
        $antes = Get-ValorSandbox $raiz 'HKCU:\Software\Teste\Sub' 'Valor'
        $a = New-Ajuste 'tipo-teste' @(New-MudancaRegistro 'Valor' $Novo $Tipo)
        (Set-TmdAjuste -Ajuste $a -RaizRegistro $raiz).Status | Should -Be 'Feito'
        (Undo-TmdAjuste -Id 'tipo-teste' -RaizRegistro $raiz).Status | Should -Be 'Feito'
        $depois = Get-ValorSandbox $raiz 'HKCU:\Software\Teste\Sub' 'Valor'
        $depois.TipoValor | Should -Be $Tipo
        (@($depois.Valor) -join '|') | Should -BeExactly (@($antes.Valor) -join '|')
    }

    It 'aplicar duas vezes não troca o valor salvo pelo que o próprio Tamanduá escreveu' {
        Set-ValorSandbox $raiz 'HKCU:\Software\Teste\Sub' 'Modo' 3 'DWord'
        $a = New-Ajuste 'duas-vezes' @(New-MudancaRegistro 'Modo' 0)
        Set-TmdAjuste -Ajuste $a -RaizRegistro $raiz | Out-Null
        (Set-TmdAjuste -Ajuste $a -RaizRegistro $raiz).Motivo | Should -Be 'já estava aplicado'
        # Algo de fora muda o valor de novo, e o ajuste é reaplicado: o salvo continua sendo o 3 original.
        Set-ValorSandbox $raiz 'HKCU:\Software\Teste\Sub' 'Modo' 7 'DWord'
        Set-TmdAjuste -Ajuste $a -RaizRegistro $raiz | Out-Null
        Undo-TmdAjuste -Id 'duas-vezes' -RaizRegistro $raiz | Out-Null
        (Get-ValorSandbox $raiz 'HKCU:\Software\Teste\Sub' 'Modo').Valor | Should -Be 3
    }

    It 'já aplicado antes do Tamanduá: não salva estado (não há o que desfazer)' {
        Set-ValorSandbox $raiz 'HKCU:\Software\Teste\Sub' 'Modo' 0 'DWord'
        $r = Set-TmdAjuste -Ajuste (New-Ajuste 'ja-estava' @(New-MudancaRegistro 'Modo' 0)) -RaizRegistro $raiz
        $r.Motivo | Should -Be 'já estava aplicado'
        Test-TmdAjusteReversivel -Id 'ja-estava' | Should -BeFalse
    }

    It '-Simular descreve a mudança e não escreve nem salva nada' {
        $a = New-Ajuste 'simulado' @(New-MudancaRegistro 'Telemetria' 0)
        $r = Set-TmdAjuste -Ajuste $a -RaizRegistro $raiz -Simular
        $r.Status | Should -Be 'Simulado'
        $r.Mudancas[0] | Should -Match 'Telemetria: não existe → 0'
        (Get-ValorSandbox $raiz 'HKCU:\Software\Teste\Sub' 'Telemetria').Existe | Should -BeFalse
        Test-TmdAjusteReversivel -Id 'simulado' | Should -BeFalse
    }

    It 'se não der para salvar o estado, nada é escrito' {
        New-Item -ItemType File -Path (Join-Path $env:TAMANDUA_DADOS 'estado') -Force | Out-Null
        $r = Set-TmdAjuste -Ajuste (New-Ajuste 'sem-estado' @(New-MudancaRegistro 'Telemetria' 0)) -RaizRegistro $raiz
        $r.Status | Should -Be 'Erro'
        (Get-ValorSandbox $raiz 'HKCU:\Software\Teste\Sub' 'Telemetria').Existe | Should -BeFalse
    }

    It 'se a conferência depois de escrever falhar, volta e devolve erro' {
        Mock Write-TmdMudanca -ModuleName Tamandua.Nucleo { }
        $r = Set-TmdAjuste -Ajuste (New-Ajuste 'nao-pegou' @(New-MudancaRegistro 'Telemetria' 0)) -RaizRegistro $raiz
        $r.Status | Should -Be 'Erro'
        $r.Motivo | Should -Match 'conferência'
        Test-TmdAjusteReversivel -Id 'nao-pegou' | Should -BeFalse
    }

    It 'três mudanças e a segunda falha: a primeira volta e a terceira nem é aplicada' {
        Set-ValorSandbox $raiz 'HKCU:\Software\Teste\Sub' 'Um' 5 'DWord'
        $a = New-Ajuste 'tres' @(
            New-MudancaRegistro 'Um' 0
            [pscustomobject]@{ tipo = 'Script'; aplicar = "throw 'acesso negado'"; desfazer = '$null' }
            New-MudancaRegistro 'Tres' 0
        )
        $r = Set-TmdAjuste -Ajuste $a -RaizRegistro $raiz
        $r.Status | Should -Be 'Erro'
        $r.Motivo | Should -Match 'acesso negado.*nada ficou alterado'
        (Get-ValorSandbox $raiz 'HKCU:\Software\Teste\Sub' 'Um').Valor | Should -Be 5
        (Get-ValorSandbox $raiz 'HKCU:\Software\Teste\Sub' 'Tres').Existe | Should -BeFalse
        Test-TmdAjusteReversivel -Id 'tres' | Should -BeFalse
    }

    It 'HKLM vai para a sandbox, nunca para o HKLM real' {
        Mock Test-TmdAdministrador -ModuleName Tamandua.Nucleo { $true }
        $m = New-MudancaRegistro 'X' 1 -Caminho 'HKLM:\SOFTWARE\TamanduaNaoExiste'
        (Set-TmdAjuste -Ajuste (New-Ajuste 'hklm-teste' @($m) -RequerAdmin $true) -RaizRegistro $raiz).Status | Should -Be 'Feito'
        Test-Path -LiteralPath "$raiz\HKLM\SOFTWARE\TamanduaNaoExiste" | Should -BeTrue
        Test-Path -LiteralPath 'HKLM:\SOFTWARE\TamanduaNaoExiste' | Should -BeFalse
    }
}

Describe 'Ajustes mal definidos e permissões' {
    BeforeEach {
        $env:TAMANDUA_DADOS = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
        $raiz = New-RaizRegistro
    }

    It 'recusa <Caso>' -ForEach @(
        @{ Caso = 'HKLM sem requerAdmin'; A = [pscustomobject]@{ id = 'x'; mudancas = @([pscustomobject]@{ tipo = 'Registro'; caminho = 'HKLM:\SOFTWARE\X'; nome = 'a'; valor = 1; tipoValor = 'DWord' }) } }
        @{ Caso = 'tipo desconhecido'; A = [pscustomobject]@{ id = 'x'; mudancas = @([pscustomobject]@{ tipo = 'Formatar' }) } }
        @{ Caso = 'caminho fora de HKCU/HKLM/HKU'; A =[pscustomobject]@{ id = 'x'; mudancas = @([pscustomobject]@{ tipo = 'Registro'; caminho = 'HKCR:\x'; nome = 'a'; valor = 1; tipoValor = 'DWord' }) } }
        @{ Caso = 'tipoValor inválido'; A = [pscustomobject]@{ id = 'x'; mudancas = @([pscustomobject]@{ tipo = 'Registro'; caminho = 'HKCU:\X'; nome = 'a'; valor = 1; tipoValor = 'Texto' }) } }
        @{ Caso = 'script sem desfazer'; A = [pscustomobject]@{ id = 'x'; mudancas = @([pscustomobject]@{ tipo = 'Script'; aplicar = '1' }) } }
        @{ Caso = 'id com caracteres inválidos'; A = [pscustomobject]@{ id = '..\x'; mudancas = @([pscustomobject]@{ tipo = 'Registro'; caminho = 'HKCU:\X'; nome = 'a'; valor = 1; tipoValor = 'DWord' }) } }
        @{ Caso = 'sem mudanças'; A = [pscustomobject]@{ id = 'x'; mudancas = @() } }
    ) {
        $r = Set-TmdAjuste -Ajuste $A -RaizRegistro $raiz
        $r.Status | Should -Be 'Erro'
        Test-Path -LiteralPath $raiz | Should -BeFalse -Because 'nada pode ter sido escrito'
    }

    It 'requerAdmin sem ser administrador: simular funciona (só lê)' {
        Mock Test-TmdAdministrador -ModuleName Tamandua.Nucleo { $false }
        $r = Set-TmdAjuste -Ajuste (New-Ajuste 'admin-sim' @(New-MudancaRegistro 'X' 1) -RequerAdmin $true) -RaizRegistro $raiz -Simular
        $r.Status | Should -Be 'Simulado'
        Test-Path -LiteralPath $raiz | Should -BeFalse
    }

    It 'requerAdmin sem ser administrador: ignorado, nada escrito' {
        Mock Test-TmdAdministrador -ModuleName Tamandua.Nucleo { $false }
        # Fora da área de testes (lá não há o que pedir), numa chave que não pode ser criada.
        $chave = "$script:ChaveTestes\fora-$([guid]::NewGuid().ToString('N'))"
        $r = Set-TmdAjuste -Ajuste (New-Ajuste 'admin' @(New-MudancaRegistro 'X' 1 -Caminho $chave) -RequerAdmin $true)
        $r.Status | Should -Be 'Ignorado'
        $r.Motivo | Should -Match 'administrador'
        Test-Path -LiteralPath $chave | Should -BeFalse
    }

    It 'na área de testes, ajuste com serviço ou script é recusado: só registro vai para a chave de teste' {
        Mock Set-TmdServicoInicializacao -ModuleName Tamandua.Nucleo { throw 'não devia mexer em serviço' }
        $a = New-Ajuste 'misto' @((New-MudancaRegistro 'X' 1), [pscustomobject]@{ tipo = 'Servico'; nome = 'DiagTrack'; inicializacao = 'Disabled'; padraoWindows = 'Automatic' }) -RequerAdmin $true
        $r = Set-TmdAjuste -Ajuste $a -RaizRegistro $raiz
        $r.Status | Should -Be 'Erro'
        $r.Motivo | Should -Match 'área de testes'
        Test-Path -LiteralPath $raiz | Should -BeFalse
    }

    It 'HKU exige requerAdmin; com ele, vai para a chave de teste e volta' {
        Mock Test-TmdAdministrador -ModuleName Tamandua.Nucleo { $true }
        $hku = New-MudancaRegistro 'InitialKeyboardIndicators' '2' -Tipo 'String' -Caminho 'HKU:\.DEFAULT\Control Panel\Keyboard'
        (Set-TmdAjuste -Ajuste (New-Ajuste 'hku-sem-admin' @($hku)) -RaizRegistro $raiz).Status | Should -Be 'Erro'
        (Set-TmdAjuste -Ajuste (New-Ajuste 'hku' @($hku) -RequerAdmin $true) -RaizRegistro $raiz).Status | Should -Be 'Feito'
        (Get-ValorSandbox $raiz 'HKU:\.DEFAULT\Control Panel\Keyboard' 'InitialKeyboardIndicators').Valor | Should -Be '2'
        Test-Path -LiteralPath "$raiz\HKU\.DEFAULT\Control Panel\Keyboard" | Should -BeTrue
        (Undo-TmdAjuste -Id 'hku').Status | Should -Be 'Feito'
        (Get-ValorSandbox $raiz 'HKU:\.DEFAULT\Control Panel\Keyboard' 'InitialKeyboardIndicators').Existe | Should -BeFalse
    }
}

Describe 'Serviços lidos pelo registro' {
    It 'inicialização de um serviço real (só leitura) e de um que não existe' {
        InModuleScope Tamandua.Nucleo { Get-TmdServicoInicializacao -Nome 'EventLog' } | Should -Be 'Automatic'
        InModuleScope Tamandua.Nucleo { Get-TmdServicoInicializacao -Nome 'TamanduaNaoExiste' } | Should -BeNullOrEmpty
    }
}

Describe 'Ponto de restauração' {
    BeforeEach {
        $env:TAMANDUA_DADOS = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
        Mock Invoke-TmdCriarPontoRestauracao -ModuleName Tamandua.Nucleo { }
    }

    It 'simular não cria; sem admin é ignorado; com admin cria e registra no histórico' {
        (New-TmdPontoRestauracao -Simular).Status | Should -Be 'Simulado'
        Mock Test-TmdAdministrador -ModuleName Tamandua.Nucleo { $false }
        (New-TmdPontoRestauracao).Status | Should -Be 'Ignorado'
        Should -Invoke Invoke-TmdCriarPontoRestauracao -ModuleName Tamandua.Nucleo -Times 0 -Exactly
        Mock Test-TmdAdministrador -ModuleName Tamandua.Nucleo { $true }
        (New-TmdPontoRestauracao).Status | Should -Be 'Feito'
        Should -Invoke Invoke-TmdCriarPontoRestauracao -ModuleName Tamandua.Nucleo -Times 1 -Exactly
        $h = @(Get-TmdHistorico -Ultimos 1)[0]
        $h.Caminho | Should -Be 'Ponto de restauração'
        $h.Status | Should -Be 'Feito'
    }

    It 'falha do Windows vira erro com o motivo' {
        Mock Test-TmdAdministrador -ModuleName Tamandua.Nucleo { $true }
        Mock Invoke-TmdCriarPontoRestauracao -ModuleName Tamandua.Nucleo { throw 'A Proteção do Sistema está desligada pela política' }
        $r = New-TmdPontoRestauracao
        $r.Status | Should -Be 'Erro'
        $r.Motivo | Should -Match 'Proteção do Sistema'
    }
}

Describe 'Desfazer sem estado salvo' {
    BeforeEach {
        $env:TAMANDUA_DADOS = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
        $raiz = New-RaizRegistro
    }

    It 'com a definição: volta ao padrão do Windows e avisa' {
        Set-ValorSandbox $raiz 'HKCU:\Software\Teste\Sub' 'Apagar' 0 'DWord'
        Set-ValorSandbox $raiz 'HKCU:\Software\Teste\Sub' 'Um' 0 'DWord'
        $a = New-Ajuste 'padrao' @((New-MudancaRegistro 'Apagar' 0 -Padrao $null), (New-MudancaRegistro 'Um' 0 -Padrao 1))
        $r = Undo-TmdAjuste -Id 'padrao' -Ajuste $a -RaizRegistro $raiz
        $r.Status | Should -Be 'Feito'
        $r.Motivo | Should -Match 'padrão do Windows'
        (Get-ValorSandbox $raiz 'HKCU:\Software\Teste\Sub' 'Apagar').Existe | Should -BeFalse
        (Get-ValorSandbox $raiz 'HKCU:\Software\Teste\Sub' 'Um').Valor | Should -Be 1
    }

    It 'sem a definição: erro, nada muda' {
        (Undo-TmdAjuste -Id 'nunca-aplicado' -RaizRegistro $raiz).Status | Should -Be 'Erro'
    }

    It 'estado salvo corrompido: erro, o valor atual fica como está' {
        Set-TmdAjuste -Ajuste (New-Ajuste 'corrompido' @(New-MudancaRegistro 'X' 9)) -RaizRegistro $raiz | Out-Null
        Set-Content -LiteralPath (Join-Path $env:TAMANDUA_DADOS 'estado\ajustes\corrompido.json') -Value '{ isso não é json'
        $r = Undo-TmdAjuste -Id 'corrompido' -RaizRegistro $raiz
        $r.Status | Should -Be 'Erro'
        $r.Motivo | Should -Match 'corrompido'
        (Get-ValorSandbox $raiz 'HKCU:\Software\Teste\Sub' 'X').Valor | Should -Be 9
    }
}

Describe 'Serviços, tarefas e scripts' {
    BeforeEach {
        $env:TAMANDUA_DADOS = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
        $global:TmdTesteServico = @{ Inicializacao = 'Automatic' }
        $global:TmdTesteTarefa = @{ Habilitada = $true }
        Mock Test-TmdAdministrador -ModuleName Tamandua.Nucleo { $true }
        Mock Get-TmdServicoInicializacao -ModuleName Tamandua.Nucleo { $global:TmdTesteServico.Inicializacao }
        Mock Set-TmdServicoInicializacao -ModuleName Tamandua.Nucleo { $global:TmdTesteServico.Inicializacao = $Inicializacao }
        Mock Get-TmdTarefaHabilitada -ModuleName Tamandua.Nucleo { $global:TmdTesteTarefa.Habilitada }
        Mock Set-TmdTarefaHabilitada -ModuleName Tamandua.Nucleo { $global:TmdTesteTarefa.Habilitada = $Habilitada }
    }
    AfterAll {
        Remove-Variable -Name TmdTesteServico, TmdTesteTarefa -Scope Global -ErrorAction SilentlyContinue
    }

    It 'serviço: aplica e volta à inicialização de antes' {
        $a = New-Ajuste 'servico' @([pscustomobject]@{ tipo = 'Servico'; nome = 'DiagTrack'; inicializacao = 'Disabled'; padraoWindows = 'Automatic' }) -RequerAdmin $true
        (Set-TmdAjuste -Ajuste $a).Status | Should -Be 'Feito'
        $global:TmdTesteServico.Inicializacao | Should -Be 'Disabled'
        (Undo-TmdAjuste -Id 'servico').Status | Should -Be 'Feito'
        $global:TmdTesteServico.Inicializacao | Should -Be 'Automatic'
    }

    It 'serviço que não existe nesta máquina: nada a fazer' {
        $global:TmdTesteServico.Inicializacao = $null
        $a = New-Ajuste 'sem-servico' @([pscustomobject]@{ tipo = 'Servico'; nome = 'NaoExiste'; inicializacao = 'Disabled' }) -RequerAdmin $true
        (Set-TmdAjuste -Ajuste $a).Motivo | Should -Be 'já estava aplicado'
        Should -Invoke Set-TmdServicoInicializacao -ModuleName Tamandua.Nucleo -Times 0 -Exactly
    }

    It 'tarefa agendada: desativa e reativa' {
        $a = New-Ajuste 'tarefa' @([pscustomobject]@{ tipo = 'Tarefa'; caminho = '\Microsoft\Windows\Teste\'; nome = 'Coleta'; habilitada = $false; padraoWindows = $true }) -RequerAdmin $true
        (Set-TmdAjuste -Ajuste $a).Status | Should -Be 'Feito'
        $global:TmdTesteTarefa.Habilitada | Should -BeFalse
        Get-TmdEstadoAjuste -Ajuste $a | Should -Be 'Aplicado'
        (Undo-TmdAjuste -Id 'tarefa').Status | Should -Be 'Feito'
        $global:TmdTesteTarefa.Habilitada | Should -BeTrue
    }

    It 'script: verificar diz o estado, aplicar e desfazer rodam' {
        $arquivo = Join-Path $TestDrive "marca-$([guid]::NewGuid().ToString('N')).txt"
        $a = New-Ajuste 'script' @([pscustomobject]@{
                tipo = 'Script'
                aplicar = "Set-Content -LiteralPath '$arquivo' -Value 'x'"
                desfazer = "[IO.File]::Delete('$arquivo')"
                verificar = "Test-Path -LiteralPath '$arquivo'"
            })
        Get-TmdEstadoAjuste -Ajuste $a | Should -Be 'NaoAplicado'
        (Set-TmdAjuste -Ajuste $a).Status | Should -Be 'Feito'
        Test-Path $arquivo | Should -BeTrue
        Get-TmdEstadoAjuste -Ajuste $a | Should -Be 'Aplicado'
        (Undo-TmdAjuste -Id 'script').Status | Should -Be 'Feito'
        Test-Path $arquivo | Should -BeFalse
    }

    It 'script sem verificar: estado desconhecido' {
        $a = New-Ajuste 'script-cego' @([pscustomobject]@{ tipo = 'Script'; aplicar = '$null'; desfazer = '$null' })
        Get-TmdEstadoAjuste -Ajuste $a | Should -Be 'Desconhecido'
    }
}

Describe 'Histórico e linha de comando' {
    BeforeEach {
        $env:TAMANDUA_DADOS = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
        # Caminho "real" do ajuste é uma chave de teste: o processo filho desfaz sem redirecionamento e continua na sandbox.
        $chave = "$script:ChaveTestes\cli-$([guid]::NewGuid().ToString('N'))"
        $ajuste = New-Ajuste 'cli-teste' @(New-MudancaRegistro 'Valor' 1 -Caminho $chave)
    }

    It 'log registra ajustar e desfazer; só o ajuste ainda não desfeito é reversível' {
        Set-TmdAjuste -Ajuste $ajuste | Out-Null
        $h = @(Get-TmdHistorico)
        $h[0].Acao | Should -Be 'ajustar'
        $h[0].Reversivel | Should -BeTrue
        Undo-TmdAjuste -Id 'cli-teste' | Out-Null
        $h = @(Get-TmdHistorico)
        $h[0].Acao | Should -Be 'desfazer'
        @($h | Where-Object Reversivel).Count | Should -Be 0
    }

    It 'tamandua desfazer: valida, simula, cancela sem console e desfaz com -Sim' {
        Set-TmdAjuste -Ajuste $ajuste | Out-Null
        (Invoke-Tamandua -Raiz $script:RaizProjeto -Argumentos 'historico').Saida | Should -Match 'tamandua desfazer cli-teste'
        (Invoke-Tamandua -Raiz $script:RaizProjeto -Argumentos 'desfazer').Codigo | Should -Be 1
        (Invoke-Tamandua -Raiz $script:RaizProjeto -Argumentos 'desfazer', 'nao-existe').Codigo | Should -Be 1

        $sim = Invoke-Tamandua -Raiz $script:RaizProjeto -Argumentos 'desfazer', 'cli-teste', '-Simular'
        $sim.Codigo | Should -Be 0
        $sim.Saida | Should -Match 'volta .*Valor para não existe'
        (Get-ItemProperty -LiteralPath $chave -Name Valor).Valor | Should -Be 1

        (Invoke-Tamandua -Raiz $script:RaizProjeto -Argumentos 'desfazer', 'cli-teste').Codigo | Should -Be 3
        (Get-ItemProperty -LiteralPath $chave -Name Valor).Valor | Should -Be 1

        $r = Invoke-Tamandua -Raiz $script:RaizProjeto -Argumentos 'desfazer', 'cli-teste', '-Sim'
        $r.Codigo | Should -Be 0
        (Get-ValorSandbox '' $chave 'Valor').Existe | Should -BeFalse
    }

    It 'guarda um .reg da chave antes de mudar' {
        Set-ValorSandbox '' $chave 'Outro' 'existe' 'String'
        Set-TmdAjuste -Ajuste $ajuste | Out-Null
        @(Get-ChildItem -LiteralPath (Join-Path $env:TAMANDUA_DADOS 'backup') -Filter '*cli-teste*.reg').Count | Should -Be 1
    }
}
