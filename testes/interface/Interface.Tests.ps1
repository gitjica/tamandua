BeforeAll {
    . (Join-Path $PSScriptRoot '..\Ajudantes.ps1')
    $pastaInterface = Join-Path $script:RaizProjeto 'interface'
    Import-Module (Join-Path $pastaInterface 'Interface.psm1') -Force -DisableNameChecking

    # Abre a janela de verdade, espera a primeira página e devolve o que estava na tela. Fecha sozinha em 30 s se travar.
    function Invoke-InterfaceTeste {
        param([Parameter(Mandatory)][string]$Raiz, [string]$Tema = 'claro')
        $resultado = @{ Carregou = $false }
        $aoCarregar = {
            param($tela)
            $c = $tela.Controles
            $resultado.Carregou = $true
            $resultado.Titulo = $c.TituloPagina.Text
            $resultado.Modulos = @($c.ListaModulos.ItemsSource)
            $resultado.Linhas = @($c.ListaAlvos.ItemsSource)
            $resultado.Mensagem = if ($c.PainelMensagem.Visibility -eq 'Visible') { $c.TituloMensagem.Text } else { $null }
            $resultado.Status = $c.TextoStatus.Text
            $resultado.TemIcone = $null -ne $tela.Janela.Icon
            $tela.Janela.Close()
        }.GetNewClosure()
        Start-TmdInterface -Raiz $Raiz -Tema $Tema -AoCarregar $aoCarregar -FecharAposSeg 30
        $resultado
    }
}

Describe 'Tema' {
    It 'claro e escuro definem exatamente as mesmas cores' {
        $chaves = foreach ($t in 'tema-claro.xaml', 'tema-escuro.xaml') {
            $xml = [xml](Get-Content -LiteralPath (Join-Path $pastaInterface $t) -Raw -Encoding UTF8)
            , @($xml.ResourceDictionary.SolidColorBrush | ForEach-Object { $_.Key } | Sort-Object)
        }
        $chaves[0].Count | Should -BeGreaterThan 10
        ($chaves[0] -join ',') | Should -Be ($chaves[1] -join ',')
    }

    It 'nenhuma cor fixa fora dos arquivos de tema' {
        $arquivos = Get-ChildItem -LiteralPath $pastaInterface -File |
            Where-Object { $_.Extension -in '.xaml', '.ps1', '.psm1' -and $_.Name -notlike 'tema-*' }
        $achados = foreach ($a in $arquivos) {
            Select-String -LiteralPath $a.FullName -Pattern '#[0-9A-Fa-f]{6}\b|#[0-9A-Fa-f]{8}\b|Color\s*=\s*"[A-Za-z]' |
                ForEach-Object { "$($a.Name):$($_.LineNumber): $($_.Line.Trim())" }
        }
        $achados | Should -BeNullOrEmpty -Because ($achados -join "`n")
    }

    It 'a janela carrega com todos os controles, e trocar o tema troca as cores' {
        InModuleScope Interface -Parameters @{ Raiz = $script:RaizProjeto } {
            param($Raiz)
            $tela = New-TmdJanela -Raiz $Raiz -Tema 'claro'
            $tela.Controles.Count | Should -Be $script:NomesControles.Count
            $tela.Janela.FindResource('Fundo').Color.ToString() | Should -Be '#FFF3EADD'
            Set-TmdTema -Tela $tela -Tema 'escuro'
            $tela.Janela.FindResource('Fundo').Color.ToString() | Should -Be '#FF1A1716'
            $tela.Tema | Should -Be 'escuro'
            $tela.Janela.Close()
        }
    }
}

Describe 'Conversão para a tela' {
    It 'barra lateral: um cabeçalho por grupo, ícone e marcador por estado' {
        $modulos = @(
            [pscustomobject]@{ Nome = 'status'; Titulo = 'Status'; Grupo = 'Sistema'; Estado = 'ok'; Motivo = '' }
            [pscustomobject]@{ Nome = 'limpar'; Titulo = 'Limpar'; Grupo = 'Limpeza'; Estado = 'faltando'; Motivo = 'pasta x' }
            [pscustomobject]@{ Nome = 'outro'; Titulo = 'Outro'; Grupo = 'Limpeza'; Estado = 'indisponivel'; Motivo = 'sem winget' }
        )
        $itens = InModuleScope Interface -Parameters @{ M = $modulos } { param($M) ConvertTo-ItemNavegacao -Modulos $M }
        ($itens | ForEach-Object Tipo) -join ',' | Should -Be 'Grupo,Modulo,Grupo,Modulo,Modulo'
        $itens[0].Rotulo | Should -Be 'Sistema'
        $itens[1].Marcador | Should -BeNullOrEmpty
        $itens[3].Marcador | Should -Not -BeNullOrEmpty
        $itens[4].Icone | Should -Not -BeNullOrEmpty -Because 'módulo sem ícone conhecido usa o padrão'
        $itens[4].Motivo | Should -Be 'sem winget'
    }

    It 'linhas: cabeçalho por categoria, barra só com Valor numérico, selo por estado' {
        $alvos = @(
            [pscustomobject]@{ Id = 'a'; Nome = 'CPU'; Categoria = 'Desempenho'; Estado = 'NaoSeAplica'; Detalhe = '18%'; Nivel = 'Normal'; Valor = 18 }
            [pscustomobject]@{ Id = 'b'; Nome = 'Telemetria'; Categoria = 'Privacidade'; Estado = 'Aplicado'; Detalhe = 'x' }
            [pscustomobject]@{ Id = 'c'; Nome = 'Só nome' }
        )
        $linhas = InModuleScope Interface -Parameters @{ A = $alvos } { param($A) ConvertTo-LinhaAlvo -Alvos $A }
        ($linhas | ForEach-Object Tipo) -join ',' | Should -Be 'Categoria,Alvo,Categoria,Alvo,Categoria,Alvo'
        $linhas[1].TemValor | Should -BeTrue
        $linhas[1].Valor | Should -Be 18
        $linhas[3].TemValor | Should -BeFalse
        $linhas[3].Selo | Should -Be 'aplicado'
        $linhas[3].TemSelo | Should -BeTrue
        $linhas[5].Nivel | Should -Be 'Normal'
        $linhas[5].Alvo.Id | Should -Be 'c'
    }

    It 'busca filtra por nome, detalhe ou categoria, sem diferenciar maiúsculas' {
        $alvos = @(
            [pscustomobject]@{ Id = 'a'; Nome = 'CPU'; Categoria = 'Desempenho'; Detalhe = '18%' }
            [pscustomobject]@{ Id = 'b'; Nome = 'Disco C:'; Categoria = 'Discos'; Detalhe = '200 GB livres' }
        )
        InModuleScope Interface -Parameters @{ A = $alvos } {
            param($A)
            @((ConvertTo-LinhaAlvo -Alvos $A -Busca 'cpu') | Where-Object Tipo -eq 'Alvo').Id | Should -Be 'a'
            @((ConvertTo-LinhaAlvo -Alvos $A -Busca 'LIVRES') | Where-Object Tipo -eq 'Alvo').Id | Should -Be 'b'
            @((ConvertTo-LinhaAlvo -Alvos $A -Busca 'desempenho') | Where-Object Tipo -eq 'Alvo').Id | Should -Be 'a'
            (ConvertTo-LinhaAlvo -Alvos $A -Busca 'nada disso').Count | Should -Be 0
        }
    }

    It 'mensagem para módulo <Estado>' -ForEach @(
        @{ Estado = 'faltando'; Titulo = 'Módulo faltando' }
        @{ Estado = 'quebrado'; Titulo = 'Módulo com defeito' }
        @{ Estado = 'indisponivel'; Titulo = 'Indisponível nesta máquina' }
    ) {
        $m = [pscustomobject]@{ Estado = $Estado; Motivo = 'pasta modulos\x não encontrada' }
        $msg = InModuleScope Interface -Parameters @{ M = $m } { param($M) Get-MensagemModulo -Modulo $M }
        $msg.Titulo | Should -Be $Titulo
        $msg.Texto | Should -Match '^Pasta modulos\\x não encontrada\. O resto do Tamanduá continua'
    }

    It 'módulo ok não tem mensagem' {
        InModuleScope Interface { Get-MensagemModulo -Modulo ([pscustomobject]@{ Estado = 'ok'; Motivo = '' }) } | Should -BeNullOrEmpty
    }

    It 'texto da barra de status' {
        InModuleScope Interface {
            Get-TextoStatusPagina -Quantidade 1 -Escreve $false -Quando ([datetime]'2026-10-29 14:03:22') |
                Should -Be '1 item · atualizado às 14:03:22 · módulo só de leitura'
            Get-TextoStatusPagina -Quantidade 5 -Escreve $true -Quando ([datetime]'2026-10-29 14:03:22') |
                Should -Match '^5 itens .* nada é alterado sem confirmação$'
        }
    }
}

Describe 'Tarefas em segundo plano' {
    BeforeAll {
        function Wait-Tarefas {
            $limite = [DateTime]::UtcNow.AddSeconds(20)
            while ((InModuleScope Interface { $script:Tarefas.Count }) -gt 0 -and [DateTime]::UtcNow -lt $limite) {
                Start-Sleep -Milliseconds 50
                InModuleScope Interface { Update-TmdTarefa }
            }
        }
    }

    It 'entrega o resultado' {
        $r = @{}
        $ao = { param($saida, $erro) $r.Saida = $saida; $r.Erro = $erro }.GetNewClosure()
        InModuleScope Interface -Parameters @{ Ao = $ao } { param($Ao) [void](Start-TmdTarefa -Script { param($X) $X * 2 } -Parametros @{ X = 21 } -AoTerminar $Ao) }
        Wait-Tarefas
        $r.Saida | Should -Be 42
        $r.Erro | Should -BeNullOrEmpty
    }

    It 'entrega o erro sem derrubar nada' {
        $r = @{}
        $ao = { $r.Erro = $args[1] }.GetNewClosure()
        InModuleScope Interface -Parameters @{ Ao = $ao } { param($Ao) [void](Start-TmdTarefa -Script { throw 'falhou lá' } -AoTerminar $Ao) }
        Wait-Tarefas
        $r.Erro | Should -Be 'falhou lá'
    }

    It 'tarefa cancelada não entrega nada' {
        $r = @{ Chamou = $false }
        $ao = { $r.Chamou = $true }.GetNewClosure()
        InModuleScope Interface -Parameters @{ Ao = $ao } {
            param($Ao)
            $t = Start-TmdTarefa -Script { Start-Sleep -Seconds 30 } -AoTerminar $Ao
            Stop-TmdTarefa -Tarefa $t
        }
        Wait-Tarefas
        $r.Chamou | Should -BeFalse
    }

    It 'carrega os módulos do projeto real como dados simples' {
        $r = @{}
        $ao = { param($saida, $erro) $r.Saida = $saida; $r.Erro = $erro }.GetNewClosure()
        InModuleScope Interface -Parameters @{ Ao = $ao; Raiz = $script:RaizProjeto } {
            param($Ao, $Raiz)
            [void](Start-TmdTarefa -Script $script:ScriptCarregarModulos -AoTerminar $Ao `
                    -Parametros @{ Nucleo = (Join-Path $Raiz 'nucleo\Tamandua.Nucleo.psm1'); Raiz = $Raiz })
        }
        Wait-Tarefas
        $r.Erro | Should -BeNullOrEmpty
        $r.Saida.Count | Should -Be 12
        ($r.Saida | Where-Object Nome -eq 'status').Estado | Should -Be 'ok'
        ($r.Saida | Where-Object Nome -eq 'atualizacoes').Titulo | Should -Be 'Atualizações'
    }

    It 'repassa o progresso enquanto roda (o item atual), e não depois do fim' {
        $r = @{ Vistos = [System.Collections.Generic.List[string]]::new(); Terminou = $false; ProgressoDepois = $false }
        $ao = { $r.Terminou = $true }.GetNewClosure()
        $aoProgresso = { param($registro) if ($r.Terminou) { $r.ProgressoDepois = $true }; $r.Vistos.Add("$($registro.StatusDescription)|$($registro.CurrentOperation)") }.GetNewClosure()
        InModuleScope Interface -Parameters @{ Ao = $ao; AoP = $aoProgresso } {
            param($Ao, $AoP)
            $script = {
                foreach ($i in 1..3) { Write-Progress -Activity 'Tamanduá' -Status "item $i" -CurrentOperation "$i de 3" -PercentComplete (($i - 1) * 33); Start-Sleep -Milliseconds 400 }
                Write-Progress -Activity 'Tamanduá' -Completed
                'fim'
            }
            [void](Start-TmdTarefa -Script $script -AoTerminar $Ao -AoProgresso $AoP)
        }
        Wait-Tarefas
        $r.Terminou | Should -BeTrue
        $r.ProgressoDepois | Should -BeFalse
        $r.Vistos | Should -Contain 'item 1|1 de 3'
        $r.Vistos | Should -Contain 'item 3|3 de 3'
        $r.Vistos | Should -Not -Contain '|' -Because 'o registro "Completed" não é mostrado'
    }
}

Describe 'Progresso na barra (funções puras)' {
    It 'tempo decorrido em segundos, minutos e horas' -TestCases @(
        @{ S = 0; Texto = '0 s' }, @{ S = 59; Texto = '59 s' }, @{ S = 65; Texto = '1 min 05 s' }, @{ S = 3725; Texto = '1 h 02 min' }
    ) {
        param($S, $Texto)
        InModuleScope Interface -Parameters @{ S = $S } { param($S) Format-TempoDecorrido -Tempo ([timespan]::FromSeconds($S)) } | Should -Be $Texto
    }

    It 'vários itens: barra com a fração, texto com o item, a posição e o tempo' {
        $reg = [System.Management.Automation.ProgressRecord]::new(0, 'Tamanduá', 'Verificar arquivos (SFC)')
        $reg.CurrentOperation = '2 de 4'
        $reg.PercentComplete = 25
        $p = InModuleScope Interface -Parameters @{ R = $reg } { param($R) ConvertFrom-TmdProgresso -Registro $R -Decorrido ([timespan]::FromSeconds(75)) }
        $p.Texto | Should -Be 'Executando Verificar arquivos (SFC)… · 2 de 4 · há 1 min 15 s'
        $p.Indeterminado | Should -BeFalse
        $p.Porcento | Should -Be 25
    }

    It 'um item só: barra indeterminada (não fica parada em 0%)' {
        $reg = [System.Management.Automation.ProgressRecord]::new(0, 'Tamanduá', 'DISM')
        $reg.CurrentOperation = '1 de 1'
        $reg.PercentComplete = 0
        $p = InModuleScope Interface -Parameters @{ R = $reg } { param($R) ConvertFrom-TmdProgresso -Registro $R -Decorrido ([timespan]::FromSeconds(3)) -Verbo 'Desfazendo' }
        $p.Texto | Should -Be 'Desfazendo DISM… · há 3 s'
        $p.Indeterminado | Should -BeTrue
    }
}

Describe 'Janela de verdade' {
    It 'abre no projeto real, mostra os módulos e carrega o status' {
        $r = Invoke-InterfaceTeste -Raiz $script:RaizProjeto
        $r.Carregou | Should -BeTrue
        @($r.Modulos | Where-Object Tipo -eq 'Modulo').Count | Should -Be 13 -Because '12 do catálogo + a página Histórico'
        @($r.Modulos | Where-Object Tipo -eq 'Modulo')[-1].Nome | Should -Be 'historico'
        $r.Titulo | Should -Be 'Status'
        $r.Mensagem | Should -BeNullOrEmpty
        @($r.Linhas | Where-Object { $_.Tipo -eq 'Alvo' -and $_.Id -eq 'saude' }).Count | Should -Be 1
        $r.Status | Should -Match 'módulo só de leitura'
        $r.TemIcone | Should -BeTrue -Because 'a janela tem ícone próprio (o logo), não o do PowerShell'
    }

    It 'sem nenhum módulo: abre e explica que o módulo está faltando' {
        $raiz = New-ProjetoFalso -Pai $TestDrive -ComInterface
        $r = Invoke-InterfaceTeste -Raiz $raiz -Tema 'escuro'
        $r.Carregou | Should -BeTrue
        $r.Mensagem | Should -Be 'Módulo faltando'
    }

    It 'módulo que devolve um item só ou nenhum: mostra sem erro' {
        $raiz = New-ProjetoFalso -Pai $TestDrive -Catalogo 'um' -ComInterface
        New-ModuloFalso -Raiz $raiz -Nome 'um' -Codigo @'
function Test-Requisitos { @{ Ok = $true } }
function Find-Alvos { [pscustomobject]@{ Id = 'so'; Nome = 'Único'; Categoria = 'C'; Estado = 'NaoSeAplica'; Detalhe = 'd' } }
'@ | Out-Null
        $r = Invoke-InterfaceTeste -Raiz $raiz
        $r.Status | Should -Not -Match 'Erro'
        @($r.Linhas | Where-Object Tipo -eq 'Alvo').Count | Should -Be 1

        $vazio = New-ProjetoFalso -Pai $TestDrive -Catalogo 'vazio' -ComInterface
        New-ModuloFalso -Raiz $vazio -Nome 'vazio' | Out-Null
        $r = Invoke-InterfaceTeste -Raiz $vazio
        $r.Status | Should -Not -Match 'Erro'
        $r.Mensagem | Should -Be 'Nada a fazer aqui'
    }

    It 'módulo em grade: ícone do programa ou inicial, e o botão troca para lista e volta' {
        $raiz = New-ProjetoFalso -Pai $TestDrive -Catalogo 'grade' -ComInterface
        New-ModuloFalso -Raiz $raiz -Nome 'grade' -Manifesto @{ Visualizacao = 'Grade' } -Codigo @'
function Test-Requisitos { @{ Ok = $true } }
function Find-Alvos {
    [pscustomobject]@{ Id = 'com'; Nome = 'Com ícone'; Categoria = 'C'; Estado = 'NaoSeAplica'; Detalhe = 'd'; Icone = '%SystemRoot%\System32\shell32.dll,3' }
    [pscustomobject]@{ Id = 'sem'; Nome = 'sem ícone'; Categoria = 'C'; Estado = 'NaoSeAplica'; Detalhe = 'd'; Icone = 'C:\nao\existe.exe' }
}
'@ | Out-Null
        $resultado = @{}
        $aoCarregar = {
            param($tela)
            $c = $tela.Controles
            $janela = $tela.Janela
            $linhas = @($c.ListaAlvos.ItemsSource | Where-Object Tipo -eq 'Alvo')
            $resultado.Botao = [string]$c.BotaoVisao.Visibility
            $resultado.Modelo = $c.ListaAlvos.ItemTemplate -eq $janela.FindResource('ModeloGrade')
            $resultado.Com = $linhas | Where-Object Id -eq 'com'
            $resultado.Sem = $linhas | Where-Object Id -eq 'sem'
            $c.BotaoVisao.RaiseEvent((New-Object Windows.RoutedEventArgs([Windows.Controls.Button]::ClickEvent)))
            $resultado.ModeloDepois = $c.ListaAlvos.ItemTemplate -eq $janela.FindResource('ModeloGrade')
            $resultado.LinhasDepois = @($c.ListaAlvos.ItemsSource | Where-Object Tipo -eq 'Alvo').Count
            $c.BotaoVisao.RaiseEvent((New-Object Windows.RoutedEventArgs([Windows.Controls.Button]::ClickEvent)))
            $resultado.ModeloVolta = $c.ListaAlvos.ItemTemplate -eq $janela.FindResource('ModeloGrade')
            $janela.Close()
        }.GetNewClosure()
        Start-TmdInterface -Raiz $raiz -AoCarregar $aoCarregar -FecharAposSeg 30

        $resultado.Botao | Should -Be 'Visible'
        $resultado.Modelo | Should -BeTrue
        $resultado.Com.TemImagem | Should -BeTrue
        $resultado.Com.Imagem | Should -BeOfType [Windows.Media.Imaging.BitmapSource] -Because 'o Binding do WPF não converte um PSObject em imagem'
        $resultado.Sem.TemImagem | Should -BeFalse
        $resultado.Sem.Inicial | Should -Be 'S'
        $resultado.ModeloDepois | Should -BeFalse -Because 'o botão troca para lista'
        $resultado.LinhasDepois | Should -Be 2
        $resultado.ModeloVolta | Should -BeTrue
    }

    It 'pasta da grade: selecionar não abre; clique abre; Voltar mostra a lista inteira e nada abre sozinho depois' {
        $raiz = New-ProjetoFalso -Pai $TestDrive -Catalogo 'pastas' -ComInterface
        New-ModuloFalso -Raiz $raiz -Nome 'pastas' -Manifesto @{ Visualizacao = 'Grade'; Escreve = $true } -Codigo @'
function Test-Requisitos { @{ Ok = $true } }
function Find-Alvos {
    foreach ($g in 'A', 'B', 'C') { foreach ($n in 1, 2) { [pscustomobject]@{ Id = "$g$n"; Nome = "Prog $g$n"; Categoria = 'C'; Estado = 'NaoAplicado'; Detalhe = 'd'; Selecionado = $false; Grupo = "Grupo $g" } } }
}
function Invoke-Acao { param($Alvos, [switch]$Simular) }
'@ | Out-Null
        $global:TmdTestePastas = @{}
        $aoCarregar = {
            param($tela)
            $r = $global:TmdTestePastas
            $c = $tela.Controles
            $lista = $c.ListaAlvos
            $clicar = {
                param($linha)
                $lista.UpdateLayout(); $lista.ScrollIntoView($linha); $lista.UpdateLayout()
                $item = $lista.ItemContainerGenerator.ContainerFromItem($linha)
                # Como um clique de verdade: o WPF tira o "botão esquerdo" do PreviewMouseDown/Up em todo o caminho.
                foreach ($ev in [Windows.Input.Mouse]::PreviewMouseDownEvent, [Windows.Input.Mouse]::PreviewMouseUpEvent) {
                    $a = New-Object Windows.Input.MouseButtonEventArgs([Windows.Input.Mouse]::PrimaryDevice, 0, [Windows.Input.MouseButton]::Left)
                    $a.RoutedEvent = $ev
                    $item.RaiseEvent($a)
                }
            }
            $pastas = @($lista.ItemsSource | Where-Object Tipo -eq 'Pasta')
            $r.PastasNoInicio = $pastas.Count
            $lista.SelectedItem = $pastas[1]
            $r.AbriuPorSelecao = [bool]@($lista.ItemsSource | Where-Object Tipo -eq 'Voltar')
            & $clicar $pastas[1]
            $r.Dentro = @($lista.ItemsSource | ForEach-Object { "$($_.Tipo):$($_.Nome)" }) -join ','
            & $clicar @($lista.ItemsSource | Where-Object Tipo -eq 'Voltar')[0]
            $r.PastasDepois = @($lista.ItemsSource | Where-Object Tipo -eq 'Pasta').Count
            # O que travava: logo depois de voltar, uma pasta cai embaixo do mouse e é selecionada.
            $lista.SelectedItem = @($lista.ItemsSource | Where-Object Tipo -eq 'Pasta')[0]
            $r.AbriuDepois = [bool]@($lista.ItemsSource | Where-Object Tipo -eq 'Voltar')
            $tela.Janela.Close()
        }
        Start-TmdInterface -Raiz $raiz -AoCarregar $aoCarregar -FecharAposSeg 30
        $r = $global:TmdTestePastas
        Remove-Variable -Name TmdTestePastas -Scope Global
        $r.PastasNoInicio | Should -Be 3
        $r.AbriuPorSelecao | Should -BeFalse
        $r.Dentro | Should -Be 'Categoria:Grupo B,Voltar:Voltar,Alvo:Prog B1,Alvo:Prog B2'
        $r.PastasDepois | Should -Be 3
        $r.AbriuDepois | Should -BeFalse
    }

    It 'barra lateral e primeira página aparecem antes de um módulo lento terminar de carregar; depois a lista de verdade troca a provisória' {
        $raiz = New-ProjetoFalso -Pai $TestDrive -Catalogo 'rapido', 'lento' -ComInterface
        New-ModuloFalso -Raiz $raiz -Nome 'rapido' -Codigo @'
function Test-Requisitos { @{ Ok = $true } }
function Find-Alvos { [pscustomobject]@{ Id = 'a'; Nome = 'Item rápido'; Categoria = 'C'; Estado = 'NaoSeAplica'; Detalhe = 'd' } }
'@ | Out-Null
        New-ModuloFalso -Raiz $raiz -Nome 'lento' -Codigo @'
function Test-Requisitos { Start-Sleep -Seconds 4; @{ Ok = $false; Motivo = 'demorou e não serve' } }
function Find-Alvos { }
'@ | Out-Null
        $global:TmdTesteProvisoria = @{ Relogio = [Diagnostics.Stopwatch]::StartNew(); Lista = $null; Pagina = $null }
        Add-Type -AssemblyName WindowsBase, PresentationFramework
        $vigia = New-Object Windows.Threading.DispatcherTimer
        $vigia.Interval = [TimeSpan]::FromMilliseconds(100)
        $vigia.Add_Tick({
                try {
                    $r = $global:TmdTesteProvisoria
                    $tela = InModuleScope Interface { $script:Tela }
                    # Só a janela deste teste (a de um teste anterior pode ainda estar guardada, já fechada).
                    if (-not $tela -or -not $tela.Janela.IsVisible) { return }
                    $c = $tela.Controles
                    $temAlvo = { param($l) $l -and $l.PSObject.Properties['Tipo'] -and $l.Tipo -eq 'Alvo' }
                    if ($null -eq $r.Lista -and @($c.ListaModulos.ItemsSource | Where-Object { $_ }).Count -gt 0) { $r.Lista = $r.Relogio.ElapsedMilliseconds }
                    if ($null -eq $r.Pagina -and @($c.ListaAlvos.ItemsSource | Where-Object { & $temAlvo $_ }).Count -gt 0) { $r.Pagina = $r.Relogio.ElapsedMilliseconds }
                }
                catch { Write-Verbose "vigia: $($_.Exception.Message)" }
            })
        $vigia.Start()
        $aoCarregar = {
            param($tela)
            $r = $global:TmdTesteProvisoria
            $r.Carregou = $r.Relogio.ElapsedMilliseconds
            $r.Lento = @($tela.Controles.ListaModulos.ItemsSource | Where-Object Nome -eq 'lento')[0].Estado
            $r.Titulo = $tela.Controles.TituloPagina.Text
            $tela.Janela.Close()
        }
        try { Start-TmdInterface -Raiz $raiz -AoCarregar $aoCarregar -FecharAposSeg 30 }
        finally { $vigia.Stop() }
        $r = $global:TmdTesteProvisoria
        Remove-Variable -Name TmdTesteProvisoria -Scope Global
        $r.Lista | Should -BeLessThan 3000 -Because 'a barra lateral vem do catálogo, sem esperar os módulos'
        $r.Pagina | Should -BeLessThan 3500 -Because 'a primeira página abre sem esperar o módulo lento'
        $r.Carregou | Should -BeGreaterThan 3900 -Because '"carregou" só depois da lista de verdade'
        $r.Lento | Should -Be 'indisponivel' -Because 'a lista de verdade troca a provisória (que achava tudo ok)'
        $r.Titulo | Should -Be 'Rapido'
    }

    It 'grade grande: os primeiros quadros vão na hora e o resto logo depois, sem perder nenhum' {
        $raiz = New-ProjetoFalso -Pai $TestDrive -Catalogo 'muitos' -ComInterface
        New-ModuloFalso -Raiz $raiz -Nome 'muitos' -Manifesto @{ Visualizacao = 'Grade' } -Codigo @'
function Test-Requisitos { @{ Ok = $true } }
function Find-Alvos { foreach ($i in 1..120) { [pscustomobject]@{ Id = "p$i"; Nome = "Programa $i"; Categoria = 'C'; Estado = 'NaoSeAplica'; Detalhe = 'd' } } }
'@ | Out-Null
        $global:TmdTesteGrade = @{}
        $aoCarregar = {
            param($tela)
            $r = $global:TmdTesteGrade
            $lista = $tela.Controles.ListaAlvos
            $r.AoAvisar = @($lista.ItemsSource).Count
            & (Get-Module Interface) { Update-TmdBusca }
            $r.LogoDepois = @($lista.ItemsSource).Count
            [void]$tela.Janela.Dispatcher.BeginInvoke([Action] {
                    $global:TmdTesteGrade.NoFim = @($lista.ItemsSource).Count
                    $tela.Janela.Close()
                }.GetNewClosure(), [Windows.Threading.DispatcherPriority]::ContextIdle)
        }
        Start-TmdInterface -Raiz $raiz -AoCarregar $aoCarregar -FecharAposSeg 30
        $r = $global:TmdTesteGrade
        Remove-Variable -Name TmdTesteGrade -Scope Global
        $r.AoAvisar | Should -Be 121 -Because 'quem é avisado de "carregou" já acha a lista completa (120 + o cabeçalho)'
        $r.LogoDepois | Should -Be 48 -Because 'no primeiro desenho vão só os primeiros quadros'
        $r.NoFim | Should -Be 121
    }

    It 'módulo que falha ao buscar: a janela continua de pé e mostra o erro' {
        $raiz = New-ProjetoFalso -Pai $TestDrive -Catalogo 'ruim' -ComInterface
        New-ModuloFalso -Raiz $raiz -Nome 'ruim' -Codigo @'
function Test-Requisitos { @{ Ok = $true } }
function Find-Alvos { throw 'disco sumiu' }
'@ | Out-Null
        $r = Invoke-InterfaceTeste -Raiz $raiz
        $r.Carregou | Should -BeTrue
        $r.Mensagem | Should -Be 'O módulo falhou'
        $r.Status | Should -Match 'disco sumiu'
    }
}

Describe 'Seleção e resultado (funções puras)' {
    It 'módulo que escreve: linhas com caixa, marcadas conforme o alvo' {
        $alvos = @(
            [pscustomobject]@{ Id = 'a'; Nome = 'Temp'; Categoria = 'T'; Estado = 'NaoSeAplica'; Detalhe = 'x'; Tamanho = 2048; Selecionado = $true }
            [pscustomobject]@{ Id = 'b'; Nome = 'Dumps'; Categoria = 'T'; Estado = 'NaoSeAplica'; Detalhe = 'y'; Tamanho = 0; Selecionado = $false }
        )
        InModuleScope Interface -Parameters @{ A = $alvos } {
            param($A)
            $linhas = ConvertTo-LinhaAlvo -Alvos $A -Escreve
            @($linhas | Where-Object Tipo -eq 'Alvo' | ForEach-Object TemCaixa) | Should -Be @($true, $true)
            ($linhas | Where-Object Id -eq 'a').Selecionado | Should -BeTrue
            ($linhas | Where-Object Id -eq 'b').Selecionado | Should -BeFalse
            $r = Get-ResumoSelecao -Linhas $linhas
            $r.Quantidade | Should -Be 1
            $r.Bytes | Should -Be 2048
            $r.Texto | Should -Match '^1 selecionado · 2[,.]0 KB$'
            $r.Alvos[0].Id | Should -Be 'a'
            ((ConvertTo-LinhaAlvo -Alvos $A) | Where-Object Tipo -eq 'Alvo' | ForEach-Object TemCaixa) | Should -Not -Contain $true -Because 'módulo de leitura não tem caixa'
        }
    }

    It 'preset nunca marca item já aplicado (Desfaz); marcado à mão, a confirmação avisa que desfaz' {
        $alvos = @(
            [pscustomobject]@{ Id = 'novo'; Nome = 'Novo'; Categoria = 'T'; Estado = 'NaoAplicado'; Detalhe = ''; Selecionado = $false; Presets = @('P'); Reversivel = $true }
            [pscustomobject]@{ Id = 'feito'; Nome = 'Feito'; Categoria = 'T'; Estado = 'Aplicado'; Detalhe = ''; Selecionado = $false; Presets = @('P'); Reversivel = $true; Desfaz = $true }
        )
        InModuleScope Interface -Parameters @{ A = $alvos } {
            param($A)
            Set-SelecaoPreset -Alvos $A -Preset 'P' | Should -Be 1
            ($A | Where-Object Id -eq 'feito').Selecionado | Should -BeFalse
            ($A | Where-Object Id -eq 'feito').Selecionado = $true
            $resumo = Get-ResumoSelecao -Linhas (ConvertTo-LinhaAlvo -Alvos $A -Escreve)
            $resumo.Desfazendo | Should -Be 1
            Get-AvisoConfirmacao -Resumo $resumo | Should -Match '^ 1 já aplicado\(s\) será\(ão\) DESFEITO\(S\)\. Dá para desfazer pelo Histórico\.$'
        }
    }

    It 'classificação: selo na linha, contratempo e solução nos detalhes, e a confirmação lista os arriscados' {
        $alvos = @(
            [pscustomobject]@{ Id = 'a'; Nome = 'Seguro'; Categoria = 'T'; Estado = 'NaoAplicado'; Detalhe = 'd'; Selecionado = $true; Classificacao = 'Recomendado'; Reversivel = $true }
            [pscustomobject]@{ Id = 'b'; Nome = 'Perigoso'; Categoria = 'T'; Estado = 'NaoAplicado'; Detalhe = 'd'; Selecionado = $true; Classificacao = 'Arriscado'
                Contratempo = 'O Wi-Fi pode cair.'; SeAcontecer = 'Desfaça e reinicie.'; Reversivel = $true }
            [pscustomobject]@{ Id = 'c'; Nome = 'Já feito'; Categoria = 'T'; Estado = 'Aplicado'; Detalhe = 'd'; Selecionado = $true; Classificacao = 'Arriscado'; Desfaz = $true; Reversivel = $true }
        )
        InModuleScope Interface -Parameters @{ A = $alvos } {
            param($A)
            $todas = ConvertTo-LinhaAlvo -Alvos $A -Escreve; $linhas = @($todas | Where-Object Tipo -eq 'Alvo')
            $linhas[0].RotuloClasse | Should -Be 'Recomendado'
            $linhas[1].RotuloClasse | Should -Be 'Arriscado'
            $linhas[1].TemClasse | Should -BeTrue
            $d = Get-DetalheAlvo -Linha $linhas[1]
            $d.Problema | Should -Be 'O Wi-Fi pode cair.'
            $d.Solucao | Should -Be 'Desfaça e reinicie.'
            $d.Tom | Should -Be 'Perigo'
            @($d.Selos | ForEach-Object Texto) | Should -Contain 'Arriscado'
            $aviso = Get-AvisoConfirmacao -Resumo (Get-ResumoSelecao -Linhas $linhas)
            $aviso | Should -Match 'ARRISCADO \(1\): Perigoso' -Because 'desfazer um arriscado não conta'
        }
    }

    It 'pastas de alternativas: fechadas viram um quadro só, abertas mostram os itens e o Voltar; sozinho não vira pasta' {
        $alvos = @(
            [pscustomobject]@{ Id = 'vlc'; Nome = 'VLC'; Categoria = 'Multimídia'; Estado = 'NaoAplicado'; Detalhe = ''; Selecionado = $true; Grupo = 'Players de vídeo' }
            [pscustomobject]@{ Id = 'mpv'; Nome = 'mpv'; Categoria = 'Multimídia'; Estado = 'NaoAplicado'; Detalhe = ''; Selecionado = $false; Grupo = 'Players de vídeo' }
            [pscustomobject]@{ Id = 'gimp'; Nome = 'GIMP'; Categoria = 'Multimídia'; Estado = 'NaoAplicado'; Detalhe = ''; Selecionado = $false; Grupo = '' }
            [pscustomobject]@{ Id = 'aimp'; Nome = 'AIMP'; Categoria = 'Multimídia'; Estado = 'NaoAplicado'; Detalhe = ''; Selecionado = $false; Grupo = 'Players de música' }
        )
        InModuleScope Interface -Parameters @{ A = $alvos } {
            param($A)
            $linhas = ConvertTo-LinhaAlvo -Alvos $A -Escreve
            $fechadas = ConvertTo-LinhasComPastas -Linhas $linhas
            ($fechadas | ForEach-Object { "$($_.Tipo):$($_.Nome)" }) -join ',' | Should -Be 'Categoria:Multimídia,Pasta:Players de vídeo,Alvo:GIMP,Alvo:AIMP'
            ($fechadas | Where-Object Tipo -eq 'Pasta').Selo | Should -Be '1 de 2 marcados'
            $abertas = ConvertTo-LinhasComPastas -Linhas $linhas -PastaAberta 'Players de vídeo'
            ($abertas | ForEach-Object { "$($_.Tipo):$($_.Nome)" }) -join ',' | Should -Be 'Categoria:Players de vídeo,Voltar:Voltar,Alvo:VLC,Alvo:mpv'
            # A marca continua no alvo: o resumo da seleção não muda por causa das pastas.
            (Get-ResumoSelecao -Linhas $linhas).Quantidade | Should -Be 1
        }
    }

    It 'categorias como pastas: fechada, um quadro por categoria; aberta, o Voltar e os itens separados por tipo' {
        $alvos = @(
            [pscustomobject]@{ Id = 'vlc'; Nome = 'VLC'; Categoria = 'Multimídia'; Estado = 'NaoAplicado'; Detalhe = ''; Selecionado = $true; Grupo = 'Players de vídeo' }
            [pscustomobject]@{ Id = 'blender'; Nome = 'Blender'; Categoria = 'Multimídia'; Estado = 'NaoAplicado'; Detalhe = ''; Selecionado = $false; Grupo = '' }
            [pscustomobject]@{ Id = 'mpv'; Nome = 'mpv'; Categoria = 'Multimídia'; Estado = 'NaoAplicado'; Detalhe = ''; Selecionado = $false; Grupo = 'Players de vídeo' }
            [pscustomobject]@{ Id = 'gimp'; Nome = 'GIMP'; Categoria = 'Multimídia'; Estado = 'NaoAplicado'; Detalhe = ''; Selecionado = $false; Grupo = 'Edição de imagem' }
            [pscustomobject]@{ Id = 'firefox'; Nome = 'Firefox'; Categoria = 'Navegadores'; Estado = 'NaoAplicado'; Detalhe = ''; Selecionado = $false; Grupo = '' }
        )
        InModuleScope Interface -Parameters @{ A = $alvos } {
            param($A)
            $linhas = ConvertTo-LinhaAlvo -Alvos $A -Escreve
            $fechadas = ConvertTo-LinhasPorCategoria -Linhas $linhas
            ($fechadas | ForEach-Object { "$($_.Tipo):$($_.Nome)" }) -join ',' | Should -Be 'Alvo:Firefox,Secao:Multimídia'
            ($fechadas | Where-Object Nome -eq 'Multimídia').Selo | Should -Be '1 de 4 marcados'
            $aberta = ConvertTo-LinhasPorCategoria -Linhas $linhas -Aberta 'Multimídia'
            ($aberta | ForEach-Object { "$($_.Tipo):$($_.Nome)" }) -join ',' |
                Should -Be 'Categoria:Multimídia,Voltar:Voltar,Alvo:Blender,Categoria:Players de vídeo,Alvo:VLC,Alvo:mpv,Categoria:Edição de imagem,Alvo:GIMP'
        }
    }

    It 'escolha única: a barra diz o escolhido em cada grupo, e a pasta mostra o escolhido e as amostras' {
        $alvos = @(
            [pscustomobject]@{ Id = 'fam-arial'; Nome = 'Arial'; Categoria = 'Sem serifa'; Estado = 'NaoSeAplica'; Detalhe = ''; Selecionado = $true; Exclusivo = 'fonte'; Amostra = 'Aa'; AmostraFonte = 'Arial' }
            [pscustomobject]@{ Id = 'fam-verdana'; Nome = 'Verdana'; Categoria = 'Sem serifa'; Estado = 'NaoSeAplica'; Detalhe = ''; Selecionado = $false; Exclusivo = 'fonte'; Amostra = 'Aa'; AmostraFonte = 'Verdana' }
            [pscustomobject]@{ Id = 'tam-custom'; Nome = 'Personalizado'; Categoria = 'Tamanho do texto'; Estado = 'NaoSeAplica'; Detalhe = ''; Selecionado = $true; Exclusivo = 'tamanho'; ValorEscolhido = 97.5; Selo = '97,5%' }
            [pscustomobject]@{ Id = 'limpar-copias'; Nome = 'Apagar cópias'; Categoria = 'Segoe UI'; Estado = 'NaoSeAplica'; Detalhe = ''; Selecionado = $true }
        )
        InModuleScope Interface -Parameters @{ A = $alvos } {
            param($A)
            $grupos = @([pscustomobject]@{ Nome = 'fonte'; Rotulo = 'Fonte'; Vazio = 'escolha uma' }, [pscustomobject]@{ Nome = 'tamanho'; Rotulo = 'Tamanho'; Vazio = 'automático' })
            Get-ResumoGrupos -Grupos $grupos -Alvos $A | Should -Be 'Fonte: Arial · Tamanho: Personalizado (97,5%) · + 1 item'
            Get-ResumoGrupos -Grupos $grupos -Alvos @($A[1]) | Should -Be 'Fonte: escolha uma · Tamanho: automático'

            $linhas = ConvertTo-LinhaAlvo -Alvos @($A[0], $A[1]) -Escreve
            $script:NomeItens = 'opção|opções'
            try { $pasta = New-LinhaPasta -Tipo 'Secao' -Nome 'Sem serifa' -Membros @($linhas | Where-Object Tipo -eq 'Alvo') }
            finally { $script:NomeItens = 'programa|programas' }
            $pasta.Selo | Should -Be "$([char]0x2713) Arial"
            $pasta.TemMiniTexto | Should -BeTrue
            "$($pasta.MiniTexto0)|$($pasta.MiniFonte1)" | Should -Be 'Aa|Verdana'
            $linhas[1].Selecionado = $false
            $linhas[0].Selecionado = $false
            (New-LinhaPasta -Tipo 'Secao' -Nome 'Sem serifa' -Membros @($linhas | Where-Object Tipo -eq 'Alvo')).Selo | Should -Be '2 programas'
        }
    }

    It 'Histórico: cada linha sem caixa diz por que não dá para desfazer' {
        InModuleScope Interface {
            $ops = @(
                [pscustomobject]@{ Data = '2026-10-29T10:00:00'; Modulo = 'ajustes'; Id = 'a'; Acao = 'ajustar'; Caminho = 'A'; Status = 'Feito'; Motivo = ''; Simulado = $true; Liberado = 0; Reversivel = $false }
                [pscustomobject]@{ Data = '2026-10-29T10:00:00'; Modulo = 'ajustes'; Id = 'b'; Acao = 'ajustar'; Caminho = 'B'; Status = 'Feito'; Motivo = 'já estava aplicado'; Simulado = $false; Liberado = 0; Reversivel = $false }
                [pscustomobject]@{ Data = '2026-10-29T10:00:00'; Modulo = 'limpar'; Id = 'c'; Acao = 'remover'; Caminho = 'C'; Status = 'Feito'; Motivo = ''; Simulado = $false; Liberado = 10; Reversivel = $false }
                [pscustomobject]@{ Data = '2026-10-29T10:00:00'; Modulo = 'ajustes'; Id = 'd'; Acao = 'ajustar'; Caminho = 'D'; Status = 'Feito'; Motivo = ''; Simulado = $false; Liberado = 0; Reversivel = $true }
            )
            $linhas = @(ConvertTo-AlvoHistorico -Operacoes $ops)
            $linhas[0].Mudancas[0] | Should -Match 'simulação'
            $linhas[1].Mudancas[0] | Should -Match 'Já estava aplicado antes.*página Ajustes'
            $linhas[2].Mudancas[0] | Should -Match 'Lixeira'
            $linhas[3].Selecionavel | Should -BeTrue
            $linhas[3].Mudancas[0] | Should -Match 'valor salvo'
        }
    }

    It 'texto do resultado: simulação, sucesso, parcial e erro' {
        InModuleScope Interface {
            $sim = Get-TextoResultado -Resultados @([pscustomobject]@{ Status = 'Simulado'; Liberado = 1048576; Motivo = '' }) -Simulado $true
            $sim.Texto | Should -Match '^Simulação: liberaria 1[,.]0 MB\. Nada foi alterado\.$'
            (Get-TextoResultado -Resultados @([pscustomobject]@{ Status = 'Feito'; Liberado = 1024; Motivo = '' }) -Simulado $false).Cor | Should -Be 'Sucesso'
            $parcial = Get-TextoResultado -Resultados @([pscustomobject]@{ Status = 'Parcial'; Liberado = 10; Motivo = '2 pulado(s)' }) -Simulado $false
            $parcial.Cor | Should -Be 'Aviso'
            $parcial.Texto | Should -Match '2 pulado'
            (Get-TextoResultado -Resultados @([pscustomobject]@{ Status = 'Erro'; Liberado = 0; Motivo = 'x' }) -Simulado $false).Cor | Should -Be 'Perigo'
        }
    }
}

Describe 'Histórico (funções puras)' {
    It 'só ajuste reversível ganha caixa; agrupa por dia; desfazer não diz que é irreversível' {
        $ops = @(
            [pscustomobject]@{ Data = '2026-10-29T14:03:00'; Modulo = 'ajustes'; Id = 'priv-x'; Acao = 'ajustar'; Caminho = 'Desativar X'; Status = 'Feito'; Liberado = 0; Motivo = ''; Simulado = $false; Reversivel = $true }
            [pscustomobject]@{ Data = '2026-10-28T09:00:00'; Modulo = 'limpar'; Id = 'temp-usuario'; Acao = 'remover'; Caminho = 'C:\Temp\a'; Status = 'Parcial'; Liberado = 2048; Motivo = '1 em uso'; Simulado = $false; Reversivel = $false }
        )
        InModuleScope Interface -Parameters @{ O = $ops } {
            param($O)
            $alvos = @(ConvertTo-AlvoHistorico -Operacoes $O)
            $alvos[0].Nome | Should -Be 'Ajuste: Desativar X'
            $alvos[0].Categoria | Should -Be '29/10/2026'
            $alvos[0].IdAjuste | Should -Be 'priv-x'
            $alvos[1].Nivel | Should -Be 'Atencao'
            $alvos[1].Detalhe | Should -Match 'Parcial · limpar · 2[,.]0 KB · 09:00 · 1 em uso'
            $linhas = ConvertTo-LinhaAlvo -Alvos $alvos -Escreve
            @($linhas | Where-Object { $_.Tipo -eq 'Alvo' } | ForEach-Object TemCaixa) | Should -Be @($true, $false)
            $alvos[0].Selecionado = $true
            $resumo = Get-ResumoSelecao -Linhas (ConvertTo-LinhaAlvo -Alvos $alvos -Escreve)
            $resumo.Quantidade | Should -Be 1
            $resumo.Irreversiveis | Should -Be 0
            (Get-TextoResultado -Resultados @([pscustomobject]@{ Status = 'Feito'; Liberado = 0 }) -Acao 'desfazer').Texto | Should -Match '^Desfeitos: 1'
        }
    }
}

Describe 'Presets (funções puras)' {
    It 'lista os presets na ordem em que aparecem, com Nenhum no fim, e marca só os do preset' {
        $alvos = @(
            [pscustomobject]@{ Id = 'a'; Presets = @('Essencial', 'Privacidade'); Selecionado = $false }
            [pscustomobject]@{ Id = 'b'; Presets = @('Privacidade'); Selecionado = $true }
            [pscustomobject]@{ Id = 'c'; Presets = @(); Selecionado = $true }
        )
        InModuleScope Interface -Parameters @{ A = $alvos } {
            param($A)
            (Get-PresetAlvo -Alvos $A) -join ',' | Should -Be 'Essencial,Privacidade,Nenhum'
            Set-SelecaoPreset -Alvos $A -Preset 'Essencial' | Should -Be 1
            ($A | ForEach-Object Selecionado) -join ',' | Should -Be 'True,False,False'
            Set-SelecaoPreset -Alvos $A -Preset 'Nenhum' | Should -Be 0
            (Get-PresetAlvo -Alvos @([pscustomobject]@{ Id = 'x' })).Count | Should -Be 0
            $t = Get-TextoResultado -Resultados @([pscustomobject]@{ Id = 'a'; Status = 'Feito'; Liberado = 0; Motivo = '' }) -Acao 'ajustar'
            $t.Texto | Should -Be 'Aplicados: 1 ajuste(s). Dá para desfazer pelo Histórico.'
            $t.Cor | Should -Be 'Sucesso'
        }
    }
}

Describe 'Selo e resultado de módulos que não se desfazem pelo Histórico' {
    It 'selo próprio do módulo substitui o padrão; resultado sem "desfazer"' {
        $alvos = @([pscustomobject]@{ Id = 'vlc'; Nome = 'VLC'; Categoria = 'M'; Estado = 'Parcial'; Selo = 'atualizar para 3.1'; Detalhe = '' })
        InModuleScope Interface -Parameters @{ A = $alvos } {
            param($A)
            ((ConvertTo-LinhaAlvo -Alvos $A -Escreve) | Where-Object Tipo -eq 'Alvo').Selo | Should -Be 'atualizar para 3.1'
            ((ConvertTo-LinhaAlvo -Alvos $A -Escreve) | Where-Object Tipo -eq 'Alvo').RequerAdmin | Should -BeFalse
            ((ConvertTo-LinhaAlvo -Alvos @([pscustomobject]@{ Id = 'x'; Nome = 'X'; Categoria = 'C'; RequerAdmin = $true }) -Escreve) |
                Where-Object Tipo -eq 'Alvo').RequerAdmin | Should -BeTrue
            $t = Get-TextoResultado -Resultados @([pscustomobject]@{ Id = 'vlc'; Status = 'Feito'; Liberado = 0 }) -Acao 'ajustar' -DaParaDesfazer $false
            $t.Texto | Should -Be 'Concluídos: 1 item(ns).'
        }
    }
}

Describe 'Ajustes pela janela de verdade' {
    It 'preset Essencial, confirmação dizendo que dá para desfazer, aplica e a página mostra "aplicado"' {
        $env:TAMANDUA_DADOS = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
        $raizReg = "HKCU:\Software\TamanduaTestes\janela-ajustes-$([guid]::NewGuid().ToString('N'))"
        $projeto = New-ProjetoFalso -Pai $TestDrive -Catalogo 'ajustes' -ComInterface -ModulosReais 'ajustes'
        $env:TAMANDUA_REGISTRO_TESTE = $raizReg
        $passos = @{ Etapa = 0 }
        try {
            $aoCarregar = {
                $tela = $args[0]
                $p = $passos
                $relogio = New-Object System.Windows.Threading.DispatcherTimer
                $relogio.Interval = [TimeSpan]::FromMilliseconds(200)
                $clicar = { param($b) $b.RaiseEvent((New-Object System.Windows.RoutedEventArgs([System.Windows.Controls.Primitives.ButtonBase]::ClickEvent))) }
                $relogio.Add_Tick({
                        $c = $tela.Controles
                        if ($c.BarraTarefa.Visibility -eq 'Visible') { return }
                        switch ($p.Etapa) {
                            0 {
                                $p.Presets = @($c.ListaPresets.ItemsSource) -join ','
                                $p.PresetsVisivel = [string]$c.PainelPresets.Visibility
                                $recipiente = $c.ListaPresets.ItemContainerGenerator.ContainerFromIndex(0)
                                & $clicar ([System.Windows.Media.VisualTreeHelper]::GetChild($recipiente, 0))
                            }
                            1 {
                                $p.Marcados = $c.TextoStatus.Text
                                # Marca mais um item clicando na caixa de verdade (fora do preset).
                                $linha = @($c.ListaAlvos.ItemsSource | Where-Object { $_.Id -eq 'priv-outlook-classico' })[0]
                                # A lista só cria as linhas que estão na tela: rola até ela antes de procurar a caixa.
                                $c.ListaAlvos.ScrollIntoView($linha); $c.ListaAlvos.UpdateLayout()
                                $fila = [System.Collections.Generic.Queue[object]]::new()
                                $fila.Enqueue($c.ListaAlvos.ItemContainerGenerator.ContainerFromItem($linha))
                                $caixa = $null
                                while ($fila.Count -gt 0 -and -not $caixa) {
                                    $no = $fila.Dequeue()
                                    if ($no -is [System.Windows.Controls.CheckBox]) { $caixa = $no; break }
                                    for ($k = 0; $k -lt [System.Windows.Media.VisualTreeHelper]::GetChildrenCount($no); $k++) {
                                        $fila.Enqueue([System.Windows.Media.VisualTreeHelper]::GetChild($no, $k))
                                    }
                                }
                                $caixa.IsChecked = $true
                                & $clicar $caixa
                            }
                            2 { $p.MaisUm = $c.TextoStatus.Text; & $clicar $c.BotaoAplicar }
                            3 { $p.Confirmacao = $c.TextoStatus.Text; & $clicar $c.BotaoAplicar }
                            4 {
                                $p.Final = $c.TextoStatus.Text
                                $p.Aplicados = @($c.ListaAlvos.ItemsSource | Where-Object { $_.Estado -eq 'Aplicado' }).Count
                                $relogio.Stop()
                                $tela.Janela.Close()
                            }
                        }
                        $p.Etapa++
                    }.GetNewClosure())
                $relogio.Start()
            }.GetNewClosure()
            Start-TmdInterface -Raiz $projeto -Tema 'escuro' -AoCarregar $aoCarregar -FecharAposSeg 60
        }
        finally {
            Remove-Item Env:\TAMANDUA_REGISTRO_TESTE -ErrorAction SilentlyContinue
            if (Test-Path -LiteralPath $raizReg) { Remove-Item -LiteralPath $raizReg -Recurse -Force }
            $mae = 'HKCU:\Software\TamanduaTestes'
            if ((Test-Path -LiteralPath $mae) -and @(Get-ChildItem -LiteralPath $mae).Count -eq 0) { Remove-Item -LiteralPath $mae -Force }
        }
        # Na área de testes só entram os ajustes que são só registro: conta a partir do catálogo.
        $catalogo = @(foreach ($a in ([IO.File]::ReadAllText((Join-Path $script:RaizProjeto 'modulos\ajustes\ajustes.json'), [Text.Encoding]::UTF8) | ConvertFrom-Json)) { $a })
        $soRegistro = @($catalogo | Where-Object { -not $_.PSObject.Properties['acao'] -and -not $_.requerAdmin -and @($_.mudancas | Where-Object { $_.tipo -ne 'Registro' }).Count -eq 0 })
        $essencial = @($soRegistro | Where-Object { @($_.presets) -contains 'Essencial' }).Count
        $essencial | Should -BeGreaterThan 3
        $passos.Etapa | Should -Be 5
        $passos.PresetsVisivel | Should -Be 'Visible'
        $passos.Presets | Should -Match '^Essencial,.*Notebook.*Nenhum$'
        $passos.Marcados | Should -Match "^Preset Essencial: $essencial marcado"
        $passos.MaisUm | Should -Match "^$($essencial + 1) selecionados"
        $passos.Confirmacao | Should -Match "^Aplicar: $($essencial + 1) itens\. Dá para desfazer pelo Histórico\. Confirmar\?$"
        $passos.Final | Should -Match "^Aplicados: $($essencial + 1) ajuste"
        $passos.Aplicados | Should -Be ($essencial + 1)
    }
}

Describe 'Desfazer pela página Histórico' {
    It 'mostra o ajuste aplicado, desfaz com confirmação e o registro volta ao que era' {
        $env:TAMANDUA_DADOS = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
        $chave = "HKCU:\Software\TamanduaTestes\janela-$([guid]::NewGuid().ToString('N'))"
        Import-Module (Join-Path $script:RaizProjeto 'nucleo\Tamandua.Nucleo.psm1') -Force -DisableNameChecking -Global
        $ajuste = [pscustomobject]@{ id = 'janela-teste'; nome = 'Ajuste da janela'; requerAdmin = $false
            mudancas = @([pscustomobject]@{ tipo = 'Registro'; caminho = $chave; nome = 'Valor'; valor = 1; tipoValor = 'DWord' }) }
        (Set-TmdAjuste -Ajuste $ajuste).Status | Should -Be 'Feito'
        $projeto = New-ProjetoFalso -Pai $TestDrive -ComInterface
        $passos = @{ Etapa = 0 }
        try {
            $aoCarregar = {
                $tela = $args[0]
                $p = $passos
                $relogio = New-Object System.Windows.Threading.DispatcherTimer
                $relogio.Interval = [TimeSpan]::FromMilliseconds(200)
                $clicar = { param($b) $b.RaiseEvent((New-Object System.Windows.RoutedEventArgs([System.Windows.Controls.Primitives.ButtonBase]::ClickEvent))) }
                $relogio.Add_Tick({
                        $c = $tela.Controles
                        if ($c.BarraTarefa.Visibility -eq 'Visible') { return }
                        switch ($p.Etapa) {
                            0 { $c.ListaModulos.SelectedItem = @($c.ListaModulos.ItemsSource | Where-Object { $_.Nome -eq 'historico' })[0] }
                            1 {
                                $linha = @($c.ListaAlvos.ItemsSource | Where-Object { $_.TemCaixa })[0]
                                $p.Linha = $linha.Nome
                                $linha.Alvo.Selecionado = $true
                                & $clicar $c.BotaoAplicar
                            }
                            2 { $p.Confirmacao = $c.TextoStatus.Text; & $clicar $c.BotaoAplicar }
                            3 { $p.Final = $c.TextoStatus.Text; $relogio.Stop(); $tela.Janela.Close() }
                        }
                        $p.Etapa++
                    }.GetNewClosure())
                $relogio.Start()
            }.GetNewClosure()
            Start-TmdInterface -Raiz $projeto -Tema 'claro' -AoCarregar $aoCarregar -FecharAposSeg 60
        }
        finally {
            if (Test-Path -LiteralPath $chave) { Remove-Item -LiteralPath $chave -Recurse -Force }
        }
        $passos.Etapa | Should -Be 4
        $passos.Linha | Should -Be 'Ajuste: Ajuste da janela'
        $passos.Confirmacao | Should -Match '^Desfazer: 1 item\. Confirmar\?$'
        $passos.Final | Should -Match '^Desfeitos: 1'
        Test-TmdAjusteReversivel -Id 'janela-teste' | Should -BeFalse
    }
}

Describe 'Cache e leitura antecipada na janela' {
    It 'cada página é lida uma vez ao abrir (a primeira junto com a lista, as outras em segundo plano); F5 lê de novo' {
        $projeto = New-ProjetoFalso -Pai $TestDrive -Catalogo 'alfa', 'beta' -ComInterface
        # Cada Find-Alvos anota uma linha no arquivo: dá para contar quantas vezes cada página foi lida de verdade.
        $contador = Join-Path $TestDrive "leituras-$([guid]::NewGuid().ToString('N')).txt"
        foreach ($nome in 'alfa', 'beta') {
            New-ModuloFalso -Raiz $projeto -Nome $nome -Codigo @"
function Test-Requisitos { @{ Ok = `$true } }
function Find-Alvos {
    [IO.File]::AppendAllText('$contador', "$nome``n")
    [pscustomobject]@{ Id = '$nome-1'; Nome = 'Item de $nome'; Categoria = 'C'; Estado = 'NaoSeAplica'; Detalhe = '' }
}
"@ | Out-Null
        }
        $leituras = { param($n) @(Get-Content -LiteralPath $contador -ErrorAction SilentlyContinue | Where-Object { $_ -eq $n }).Count }.GetNewClosure()
        $passos = @{ Etapa = 0 }
        $aoCarregar = {
            $tela = $args[0]
            $p = $passos
            $ler = $leituras
            $interface = Get-Module Interface
            $relogio = New-Object System.Windows.Threading.DispatcherTimer
            $relogio.Interval = [TimeSpan]::FromMilliseconds(100)
            $relogio.Add_Tick({
                    $c = $tela.Controles
                    if ($c.BarraTarefa.Visibility -eq 'Visible') { return }
                    $antecipando = & $interface { $null -ne $script:Estado.Antecipando -or ($script:Estado.Fila -and $script:Estado.Fila.Count -gt 0) }
                    if ($antecipando) { return }
                    switch ($p.Etapa) {
                        0 { $p.AlfaAoAbrir = & $ler 'alfa'; $p.BetaAntecipada = & $ler 'beta'
                            $c.ListaModulos.SelectedItem = @($c.ListaModulos.ItemsSource | Where-Object Nome -eq 'beta')[0] }
                        1 { $p.BetaDepoisDeAbrir = & $ler 'beta'; $p.Itens = @($c.ListaAlvos.ItemsSource).Count
                            $c.BotaoAtualizar.RaiseEvent((New-Object System.Windows.RoutedEventArgs([System.Windows.Controls.Primitives.ButtonBase]::ClickEvent))) }
                        2 { $p.BetaDepoisDeF5 = & $ler 'beta'
                            $c.ListaModulos.SelectedItem = @($c.ListaModulos.ItemsSource | Where-Object Nome -eq 'alfa')[0] }
                        3 { $p.AlfaNoFim = & $ler 'alfa'; $relogio.Stop(); $tela.Janela.Close() }
                    }
                    $p.Etapa++
                }.GetNewClosure())
            $relogio.Start()
        }.GetNewClosure()
        Start-TmdInterface -Raiz $projeto -Tema 'claro' -AoCarregar $aoCarregar -FecharAposSeg 60

        $passos.Etapa | Should -Be 4 -Because 'a sequência inteira precisa ter rodado'
        $passos.AlfaAoAbrir | Should -Be 1
        $passos.BetaAntecipada | Should -Be 1 -Because 'beta foi lida em segundo plano antes do clique'
        $passos.BetaDepoisDeAbrir | Should -Be 1 -Because 'abrir beta usou o que já tinha sido lido'
        $passos.Itens | Should -BeGreaterThan 0
        $passos.BetaDepoisDeF5 | Should -Be 2 -Because 'F5 sempre lê de novo'
        $passos.AlfaNoFim | Should -Be 1 -Because 'a primeira página também ficou guardada'
    }
}

Describe 'Limpar pela janela de verdade' {
    It 'Simular não apaga; Limpar pede confirmação; Confirmar apaga o velho e mantém o recente' {
        $base = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
        $temp = New-ArvoreFalsa -Pasta (Join-Path $base 'Temp') -Arquivos @{ 'velho.tmp' = 'aaaa'; 'recente.tmp' = 'b' }
        New-ArvoreFalsa -Pasta (Join-Path $base 'Local\CrashDumps') -Arquivos @{ 'x.dmp' = 'cc' } | Out-Null
        Set-Idade "$temp\velho.tmp" 48
        $projeto = New-ProjetoFalso -Pai $TestDrive -Catalogo 'limpar' -ComInterface -ModulosReais 'limpar'

        # As tarefas da janela rodam neste processo e leem TEMP/LOCALAPPDATA daqui: aponta para a sandbox durante o teste.
        # TAMANDUA_LIMPAR_RAIZ: as categorias do sistema (Windows\Temp, WER...) também ficam na sandbox.
        $originais = @{ TEMP = $env:TEMP; TMP = $env:TMP; LOCALAPPDATA = $env:LOCALAPPDATA }
        $env:TEMP = $temp; $env:TMP = $temp; $env:LOCALAPPDATA = Join-Path $base 'Local'; $env:TAMANDUA_LIMPAR_RAIZ = $base
        $passos = @{ Etapa = 0 }
        try {
            $aoCarregar = {
                # GetNewClosure só captura variáveis locais: copia para locais o que o relógio vai usar.
                $tela = $args[0]
                $p = $passos
                $pastaTemp = $temp
                $relogio = New-Object System.Windows.Threading.DispatcherTimer
                $relogio.Interval = [TimeSpan]::FromMilliseconds(200)
                $clicar = { param($b) $b.RaiseEvent((New-Object System.Windows.RoutedEventArgs([System.Windows.Controls.Primitives.ButtonBase]::ClickEvent))) }
                $relogio.Add_Tick({
                        $c = $tela.Controles
                        if ($c.BarraTarefa.Visibility -eq 'Visible') { return }
                        switch ($p.Etapa) {
                            0 { & $clicar $c.BotaoSimular }
                            1 { $p.Simulacao = $c.TextoStatus.Text; $p.VelhoDepoisDeSimular = Test-Path "$pastaTemp\velho.tmp"; & $clicar $c.BotaoAplicar }
                            2 { $p.Confirmacao = $c.TextoStatus.Text; $p.RotuloConfirmar = $c.BotaoAplicar.Content; & $clicar $c.BotaoAplicar }
                            3 { $p.Final = $c.TextoStatus.Text; $relogio.Stop(); $tela.Janela.Close() }
                        }
                        $p.Etapa++
                    }.GetNewClosure())
                $relogio.Start()
            }.GetNewClosure()
            Start-TmdInterface -Raiz $projeto -Tema 'claro' -AoCarregar $aoCarregar -FecharAposSeg 60
        }
        finally {
            $env:TEMP = $originais.TEMP; $env:TMP = $originais.TMP; $env:LOCALAPPDATA = $originais.LOCALAPPDATA
            Remove-Item Env:\TAMANDUA_LIMPAR_RAIZ -ErrorAction SilentlyContinue
        }

        $passos.Etapa | Should -Be 4 -Because 'a sequência inteira precisa ter rodado'
        $passos.Simulacao | Should -Match 'Simulação: liberaria'
        $passos.VelhoDepoisDeSimular | Should -BeTrue
        $passos.RotuloConfirmar | Should -Be 'Confirmar'
        $passos.Confirmacao | Should -Match 'Limpar: 2 itens .* Confirmar\?'
        $passos.Final | Should -Match '^Liberado'
        Test-Path "$temp\velho.tmp" | Should -BeFalse
        Test-Path "$temp\recente.tmp" | Should -BeTrue
        Test-Path (Join-Path $base 'Local\CrashDumps\x.dmp') | Should -BeFalse
    }
}
