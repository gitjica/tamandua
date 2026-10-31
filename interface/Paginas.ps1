# Comportamento da janela: barra lateral, página do módulo, detalhes, busca, tema e barra de ação.
# Toda chamada ao núcleo vai para uma tarefa em segundo plano (SegundoPlano.ps1).

$script:Tela = $null
$script:Estado = $null

function Initialize-TmdTela {
    param([Parameter(Mandatory)]$Tela, [Parameter(Mandatory)][string]$Raiz, [scriptblock]$AoCarregar)

    $script:Tela = $Tela
    $script:Estado = @{
        Raiz          = $Raiz
        Nucleo        = Join-Path $Raiz 'nucleo\Tamandua.Nucleo.psm1'
        Modulos       = @()
        ModuloAtual   = $null
        Alvos         = @()
        TarefaPagina  = $null
        TarefaAcao    = $null
        Confirmando   = $false
        AoCarregar    = $AoCarregar
        JaAvisouCarga = $false
        # Módulo -> 'Lista' quando o usuário trocou a grade por lista nele.
        Visao         = @{}
        # Barra lateral provisória (catálogo) na tela até a lista de verdade chegar; e a troca de uma pela outra.
        ListaProvisoria = $false
        TrocandoLista = $false
        CargaPendente = $false
        # Pasta de alternativas aberta na grade (nome do grupo), ou vazio; e o quadro onde o botão do mouse desceu.
        PastaAberta   = ''
        PastaApertada = $null
        # Linhas já montadas da página atual (Id -> linha), para a busca e as pastas não remontarem tudo.
        CacheLinhas   = @{}
        # As mesmas linhas, guardadas por página (ver Get-TmdCacheLinhasPagina).
        LinhasPorPagina = @{}
        # Cartão de valor e redesenho das marcas em andamento (para um não disparar o outro).
        MostrandoValor = $false
        RedesenhandoMarcas = $false
        # Páginas já lidas (nome -> Alvos e Quando) e a leitura antecipada em andamento. Ver Start-TmdAntecipacao.
        Cache         = @{}
        Geracao       = 0
        Fila          = $null
        Antecipando   = $null
        Esperando     = $null
        # Primeira página lida junto com a lista de módulos (ver Start-TmdCargaModulos).
        Inicial       = $null
    }
    $c = $Tela.Controles
    Initialize-TmdConjunto -Nucleo $script:Estado.Nucleo

    $admin = Test-TmdAdmin
    $c.IconeAdmin.ToolTip = if ($admin) { 'Rodando como administrador' } else { 'Rodando sem permissão de administrador' }

    $c.ListaModulos.Add_SelectionChanged({ Invoke-TmdProtegido { Open-TmdPaginaSelecionada } })
    $c.ListaAlvos.Add_SelectionChanged({ Invoke-TmdProtegido { Show-TmdDetalhe } })
    # Grade: os quadros esticam para preencher a linha (sem sobra nas laterais). Cabem tantas colunas de no mínimo 150
    # (pastas de categoria: 196) quanto a largura deixa; borda e margem somam 10. O subtítulo de categoria tem a largura
    # dessas colunas, e não a da janela.
    $lista = $c.ListaAlvos
    $lista.Resources['LarguraQuadro'] = [double]150
    $lista.Resources['LarguraPasta'] = [double]196
    $lista.Resources['LarguraLinhaGrade'] = [double]632
    $lista.Add_SizeChanged({
            $disponivel = $lista.ActualWidth - 36
            $colunas = [math]::Max(1, [math]::Floor($disponivel / 160))
            $quadro = [math]::Max(150, [math]::Floor($disponivel / $colunas) - 10)
            $lista.Resources['LarguraQuadro'] = [double]$quadro
            $lista.Resources['LarguraLinhaGrade'] = [double]($colunas * ($quadro + 10) - 8)
            $colunas = [math]::Max(1, [math]::Floor($disponivel / 206))
            $lista.Resources['LarguraPasta'] = [double][math]::Max(196, [math]::Floor($disponivel / $colunas) - 10)
        }.GetNewClosure())
    $c.CampoBusca.Add_TextChanged({ Invoke-TmdProtegido { Update-TmdBusca } })
    # Dica da página fechada: não volta mais naquela página (fica nas preferências).
    $c.FecharDica.Add_Click({
            Invoke-TmdProtegido {
                $script:Tela.Controles.DicaPagina.Visibility = 'Collapsed'
                $nome = $script:Estado.ModuloAtual
                if ($nome -and $script:Preferencias -and @($script:Preferencias.DicasFechadas) -notcontains $nome) {
                    $script:Preferencias.DicasFechadas = @($script:Preferencias.DicasFechadas) + $nome
                    Save-TmdPreferencias
                }
            }
        })
    # Cartão de valor (tamanho personalizado da página Fonte): régua e campo andam juntos.
    $c.ReguaValor.Add_ValueChanged({ Invoke-TmdProtegido { Set-TmdValorDoCartao -Valor ([math]::Round($script:Tela.Controles.ReguaValor.Value, 1)) } })
    $c.CampoValor.Add_LostFocus({ Invoke-TmdProtegido { Read-TmdCampoValor } })
    $c.CampoValor.Add_KeyDown({
            $e = $args[1]
            if ($e.Key -eq 'Enter') { Invoke-TmdProtegido { Read-TmdCampoValor }; $e.Handled = $true }
        })
    $c.BotaoAtualizar.Add_Click({ Invoke-TmdProtegido { Open-TmdPagina -Nome $script:Estado.ModuloAtual -Forcar } })
    $c.BotaoVisao.Add_Click({ Invoke-TmdProtegido { Switch-TmdVisao } })
    # O jeito "lista" é o que está no janela.xaml; a grade vem de estilos.xaml (Set-TmdVisao troca entre os dois).
    $script:VisaoLista = @{ Modelo = $c.ListaAlvos.ItemTemplate; Painel = $c.ListaAlvos.ItemsPanel }
    $c.BotaoCancelar.Add_Click({ Invoke-TmdProtegido { Stop-TmdCargaPagina } })
    $c.BotaoSimular.Add_Click({ Invoke-TmdProtegido { Invoke-TmdBotaoSimular } })
    $c.BotaoAplicar.Add_Click({ Invoke-TmdProtegido { Invoke-TmdBotaoAplicar } })
    # $args é lido aqui fora: dentro do bloco do Invoke-TmdProtegido ele seria o $args daquele bloco (vazio).
    $c.ListaPresets.AddHandler([System.Windows.Controls.Primitives.ButtonBase]::ClickEvent, [System.Windows.RoutedEventHandler] {
            $evento = $args[1]
            Invoke-TmdProtegido {
                $nome = [string]$evento.OriginalSource.DataContext
                if ($nome) { Select-TmdPreset -Preset $nome }
            }
        })
    # Pastas da grade abrem (e "Voltar" fecha) no CLIQUE: botão apertado e solto no mesmo quadro. Não pela seleção:
    # o ListBox muda a seleção quando o mouse passa com o botão apertado, e depois de trocar a lista caía outra
    # pasta embaixo do mouse, que abria sozinha.
    $c.ListaAlvos.AddHandler([System.Windows.UIElement]::PreviewMouseLeftButtonDownEvent, [System.Windows.Input.MouseButtonEventHandler] {
            $script:Estado.PastaApertada = Get-TmdLinhaDoEvento -Origem $args[1].OriginalSource
        })
    $c.ListaAlvos.AddHandler([System.Windows.UIElement]::PreviewMouseLeftButtonUpEvent, [System.Windows.Input.MouseButtonEventHandler] {
            $evento = $args[1]
            Invoke-TmdProtegido {
                $linha = Get-TmdLinhaDoEvento -Origem $evento.OriginalSource
                $apertada = $script:Estado.PastaApertada
                $script:Estado.PastaApertada = $null
                if ($linha -and $linha -eq $apertada -and $linha.Tipo -in 'Pasta', 'Secao', 'Voltar') {
                    Open-TmdPasta -Nome $(if ($linha.Tipo -ne 'Voltar') { $linha.Nome } else { '' })
                    $evento.Handled = $true
                }
                # Clicar em qualquer parte do quadro (ou da linha) marca ou desmarca, sem mirar na caixinha. Marcar não
                # muda nada: aplicar sempre pede confirmação.
                elseif ($linha -and $linha -eq $apertada -and $linha.Tipo -eq 'Alvo' -and $linha.TemCaixa -and
                    -not (Test-TmdCliqueNaCaixa -Origem $evento.OriginalSource)) {
                    Set-TmdSelecao -Linha $linha -Selecionado (-not $linha.Selecionado) -Redesenhar
                }
            }
        })
    # Caixas de seleção dentro das linhas: um único ouvinte na lista para todos os cliques.
    $c.ListaAlvos.AddHandler([System.Windows.Controls.Primitives.ButtonBase]::ClickEvent, [System.Windows.RoutedEventHandler] {
            $evento = $args[1]
            Invoke-TmdProtegido {
                $caixa = $evento.OriginalSource
                if ($caixa -is [System.Windows.Controls.CheckBox] -and $caixa.DataContext) {
                    Set-TmdSelecao -Linha $caixa.DataContext -Selecionado ([bool]$caixa.IsChecked)
                }
            }
        })
    $c.BotaoTema.Add_Click({
            Invoke-TmdProtegido {
                $novo = if ($script:Tela.Tema -eq 'claro') { 'escuro' } else { 'claro' }
                Set-TmdTema -Tela $script:Tela -Tema $novo
                # Escolhido no botão: fica (sem escolher, segue o tema do Windows).
                if ($script:Preferencias) { $script:Preferencias.Tema = $novo; Save-TmdPreferencias }
            }
        })
    $Tela.Janela.Add_PreviewKeyDown({
            $e = $args[1]
            if ($e.Key -eq 'F' -and [System.Windows.Input.Keyboard]::Modifiers -eq 'Control') {
                [void]$script:Tela.Controles.CampoBusca.Focus()
                $e.Handled = $true
            }
            elseif ($e.Key -eq 'Enter' -and $script:Tela.Controles.ListaAlvos.IsKeyboardFocusWithin -and
                $script:Tela.Controles.ListaAlvos.SelectedItem -and $script:Tela.Controles.ListaAlvos.SelectedItem.Tipo -in 'Pasta', 'Secao', 'Voltar') {
                $sel = $script:Tela.Controles.ListaAlvos.SelectedItem
                Invoke-TmdProtegido { Open-TmdPasta -Nome $(if ($sel.Tipo -ne 'Voltar') { $sel.Nome } else { '' }) }
                $e.Handled = $true
            }
            # Espaço marca ou desmarca o item selecionado na lista (teclado, sem mouse).
            elseif ($e.Key -eq 'Space' -and $script:Tela.Controles.ListaAlvos.IsKeyboardFocusWithin -and
                $script:Tela.Controles.ListaAlvos.SelectedItem -and $script:Tela.Controles.ListaAlvos.SelectedItem.Tipo -eq 'Alvo' -and
                $script:Tela.Controles.ListaAlvos.SelectedItem.TemCaixa) {
                $sel = $script:Tela.Controles.ListaAlvos.SelectedItem
                Invoke-TmdProtegido { Set-TmdSelecao -Linha $sel -Selecionado (-not $sel.Selecionado) -Redesenhar }
                $e.Handled = $true
            }
            elseif ($e.Key -eq 'Escape' -and $script:Estado.PastaAberta -and -not $script:Tela.Controles.CampoBusca.IsKeyboardFocused) {
                Invoke-TmdProtegido { Open-TmdPasta -Nome '' }
                $e.Handled = $true
            }
            elseif ($e.Key -eq 'Escape' -and $script:Tela.Controles.CampoBusca.IsKeyboardFocused) {
                $script:Tela.Controles.CampoBusca.Text = ''
                $e.Handled = $true
            }
            elseif ($e.Key -eq 'F5') {
                Invoke-TmdProtegido { Open-TmdPagina -Nome $script:Estado.ModuloAtual -Forcar }
                $e.Handled = $true
            }
        })
    $Tela.Janela.Add_SourceInitialized({ Set-TmdBarraTituloEscura -Janela $script:Tela.Janela -Escura ($script:Tela.Tema -eq 'escuro') })
    $Tela.Janela.Add_ContentRendered({ Invoke-TmdProtegido { Start-TmdCargaModulos } })
    $Tela.Janela.Add_Closing({ Stop-TmdTodasTarefas })

    $script:Relogio = New-Object System.Windows.Threading.DispatcherTimer
    $script:Relogio.Interval = [TimeSpan]::FromMilliseconds(100)
    $script:Relogio.Add_Tick({ Invoke-TmdProtegido { Update-TmdTarefa } })
    $script:Relogio.Start()
    $Tela.Janela.Add_Closed({ $script:Relogio.Stop(); Close-TmdConjunto })
}

# Erro num evento nunca derruba a janela: vira texto na barra de status.
function Invoke-TmdProtegido {
    param([Parameter(Mandatory)][scriptblock]$Bloco)
    try { & $Bloco }
    catch {
        if ($script:Tela) {
            $script:Tela.Controles.TextoStatus.Text = "Erro: $($_.Exception.Message)"
            $script:Tela.Controles.TextoStatus.Foreground = $script:Tela.Janela.FindResource('Perigo')
        }
    }
}

function Set-TmdStatus {
    param([string]$Texto, [string]$Cor = 'TextoSecundario')
    $script:Tela.Controles.TextoStatus.Text = $Texto
    $script:Tela.Controles.TextoStatus.Foreground = $script:Tela.Janela.FindResource($Cor)
}

function Set-TmdOcupado {
    param([bool]$Ocupado)
    $c = $script:Tela.Controles
    $c.BarraTarefa.Visibility = if ($Ocupado) { 'Visible' } else { 'Hidden' }
    # Volta ao "girando" até a próxima tarefa dizer em qual item está.
    $c.BarraTarefa.IsIndeterminate = $true
    $c.BarraTarefa.Value = 0
    $c.BotaoCancelar.Visibility = if ($Ocupado) { 'Visible' } else { 'Collapsed' }
    $c.BotaoAtualizar.IsEnabled = -not $Ocupado
}

function Start-TmdCargaModulos {
    Set-TmdStatus 'Carregando módulos…'
    Set-TmdOcupado $true
    Show-TmdMensagem -Icone ([string][char]0xE895) -Titulo 'Carregando módulos' -Texto 'Verificando o que está disponível nesta máquina.'
    # Ao mesmo tempo, já lê a primeira página: quando a lista chegar, ela abre sem esperar mais.
    $script:Estado.Inicial = @{ Pronto = $false; Nome = $null; Alvos = $null; Erro = $null }
    [void](Start-TmdTarefa -Script $script:ScriptPrimeiraPagina -Parametros @{ Nucleo = $script:Estado.Nucleo; Raiz = $script:Estado.Raiz } `
            -AoTerminar {
            param($saida, $erro)
            $inicial = $script:Estado.Inicial
            if (-not $inicial) { return }
            $r = @($saida)[0]
            $inicial.Pronto = $true
            $inicial.Erro = $erro
            if ($r -and $r.Ok) { $inicial.Nome = $r.Nome; $inicial.Alvos = @($r.Alvos) }
            $espera = $script:Estado.Esperando
            # Lista provisória e o módulo da primeira página não está ok de verdade (faltando, quebrado...): quem
            # mostra a mensagem certa é a lista de verdade, quando chegar (Update-TmdListaDeVerdade).
            if ($script:Estado.ListaProvisoria -and -not ($r -and $r.Ok)) { return }
            if ($espera -and $espera.Inicial) {
                $script:Estado.Esperando = $null
                Set-TmdOcupado $false
                Open-TmdPagina -Nome $script:Estado.ModuloAtual -StatusDepois $espera.StatusDepois
            }
        })
    [void](Start-TmdTarefa -Script $script:ScriptCarregarModulos `
            -Parametros @{ Nucleo = $script:Estado.Nucleo; Raiz = $script:Estado.Raiz } `
            -AoTerminar {
            param($saida, $erro, $avisos)
            $provisoria = $script:Estado.ListaProvisoria
            $script:Estado.ListaProvisoria = $false
            # A página da lista provisória pode ainda estar carregando: a barra de ocupado é dela.
            if (-not $provisoria -or (-not $script:Estado.Esperando -and -not $script:Estado.TarefaPagina)) { Set-TmdOcupado $false }
            if ($erro) {
                Show-TmdMensagem -Icone $script:MarcadorEstado.quebrado -Titulo 'Não foi possível carregar os módulos' -Texto (Format-Frase $erro) -Tom 'Perigo'
                Set-TmdStatus "Erro: $erro" 'Perigo'
                Complete-TmdCargaInicial
                return
            }
            $modulos = @($saida)
            $disponiveis = @($modulos | Where-Object { $_.Estado -eq 'ok' }).Count
            $texto = "$disponiveis de $($modulos.Count) módulos disponíveis"
            if (-not (Test-TmdAdmin)) { $texto += ' · sem administrador: o que tem escudo pede permissão na hora' }
            $script:Estado.Modulos = $modulos + $script:PaginaHistorico
            if ($provisoria) { Update-TmdListaDeVerdade -Texto $texto -Avisos $avisos; return }
            $script:Tela.Controles.ListaModulos.ItemsSource = ConvertTo-ItemNavegacao -Modulos $script:Estado.Modulos
            if ($avisos) { Set-TmdStatus "$texto · $($avisos -join ' · ')" 'Aviso' } else { Set-TmdStatus $texto }
            Select-TmdModuloInicial
        })
    # Enquanto isso, a barra lateral já aparece pelo catálogo e a primeira página começa a abrir (a leitura dela já
    # está em andamento acima): o usuário não espera os módulos carregarem para ver alguma coisa.
    $provisorios = @(Get-TmdModulosProvisorios -Raiz $script:Estado.Raiz)
    if ($provisorios.Count -gt 0) {
        $script:Estado.ListaProvisoria = $true
        $script:Estado.Modulos = $provisorios + $script:PaginaHistorico
        $script:Tela.Controles.ListaModulos.ItemsSource = ConvertTo-ItemNavegacao -Modulos $script:Estado.Modulos
        Select-TmdModuloInicial
    }
}

# Chegou a lista de verdade depois da provisória: troca a barra lateral sem reabrir a página que está na tela
# (a seleção é refeita sem disparar a abertura). Se o módulo aberto, na verdade, está com problema, reabre para
# mostrar a mensagem certa. A leitura antecipada das outras páginas só começa agora, com a lista certa.
function Update-TmdListaDeVerdade {
    param([string]$Texto, [string[]]$Avisos)
    $c = $script:Tela.Controles
    $script:Estado.TrocandoLista = $true
    try {
        $c.ListaModulos.ItemsSource = ConvertTo-ItemNavegacao -Modulos $script:Estado.Modulos
        $c.ListaModulos.SelectedItem = @($c.ListaModulos.ItemsSource | Where-Object { $_.Tipo -eq 'Modulo' -and $_.Nome -eq $script:Estado.ModuloAtual })[0]
    }
    finally { $script:Estado.TrocandoLista = $false }
    $atual = Get-TmdModuloAtual
    $esperaInicial = $script:Estado.Esperando -and $script:Estado.Esperando.Inicial -and $script:Estado.Inicial -and $script:Estado.Inicial.Pronto
    if (-not $atual -or $atual.Estado -ne 'ok' -or $esperaInicial) {
        # Módulo com problema, ou a primeira página ficou esperando esta lista: abre de novo, agora com a lista certa.
        $script:Estado.Esperando = $null
        Set-TmdOcupado $false
        if ($c.ListaModulos.SelectedItem) { Open-TmdPagina -Nome $script:Estado.ModuloAtual } else { Select-TmdModuloInicial }
    }
    elseif ($Avisos) { Set-TmdStatus "$Texto · $($Avisos -join ' · ')" 'Aviso' }
    elseif ($script:Estado.Esperando -or $script:Estado.TarefaPagina) { Set-TmdStatus $Texto }
    # A página que já estava pronta avisa agora (com a lista certa na tela) e as outras começam a ser lidas.
    if ($script:Estado.CargaPendente) { $script:Estado.CargaPendente = $false; Complete-TmdCargaInicial }
    if (-not $script:Estado.Esperando -and -not $script:Estado.TarefaPagina) { Start-TmdAntecipacao }
}

function Select-TmdModuloInicial {
    $itens = @($script:Tela.Controles.ListaModulos.ItemsSource | Where-Object { $_.Tipo -eq 'Modulo' })
    if ($itens.Count -eq 0) {
        Show-TmdMensagem -Icone ([string][char]0xEA86) -Titulo 'Nenhum módulo encontrado' -Texto 'O catálogo está vazio e a pasta modulos não tem nada.'
        Complete-TmdCargaInicial
        return
    }
    # O primeiro módulo disponível; a página Histórico só abre de início se não houver nenhum módulo.
    $modulos = @($itens | Where-Object { $_.Nome -ne $script:PaginaHistorico.Nome })
    $primeiro = @($modulos | Where-Object { $_.Estado -eq 'ok' } | Select-Object -First 1)
    if ($primeiro.Count -eq 0) { $primeiro = @($modulos | Select-Object -First 1) }
    if ($primeiro.Count -eq 0) { $primeiro = @($itens[0]) }
    $script:Tela.Controles.ListaModulos.SelectedItem = $primeiro[0]
}

function Open-TmdPaginaSelecionada {
    if ($script:Estado.TrocandoLista) { return }
    $item = $script:Tela.Controles.ListaModulos.SelectedItem
    if ($null -eq $item -or $item.Tipo -ne 'Modulo') { return }
    Open-TmdPagina -Nome $item.Nome
}

function Get-TmdModuloAtual {
    @($script:Estado.Modulos | Where-Object { $_.Nome -eq $script:Estado.ModuloAtual })[0]
}

# -StatusDepois: texto (e cor) para a barra de status quando a página terminar de carregar, no lugar do padrão.
# -Forcar: lê de novo mesmo que a página esteja no cache (Atualizar, F5, depois de uma ação).
function Open-TmdPagina {
    param([string]$Nome, $StatusDepois, [switch]$Forcar)
    if (-not $Nome) { return }

    $modulo = @($script:Estado.Modulos | Where-Object { $_.Nome -eq $Nome })[0]
    $c = $script:Tela.Controles
    Stop-TmdCargaPagina -Silencioso
    $script:Estado.ModuloAtual = $Nome
    $script:Estado.Alvos = @()
    $script:Estado.CacheLinhas = Get-TmdCacheLinhasPagina -Nome $Nome
    $script:Estado.PastaAberta = ''
    Exit-TmdConfirmacao
    $c.TituloPagina.Text = $modulo.Titulo
    $c.SubtituloPagina.Text = if ($modulo.Descricao) { "$($modulo.Grupo) · $($modulo.Descricao)" } else { $modulo.Grupo }
    $dica = [string](Get-ValorPropriedade $modulo 'Dica')
    $c.TextoDicaPagina.Text = $dica
    $fechada = $script:Preferencias -and @($script:Preferencias.DicasFechadas) -contains $Nome
    $c.DicaPagina.Visibility = if ($dica -and -not $fechada) { 'Visible' } else { 'Collapsed' }
    $nomeItens = [string](Get-ValorPropriedade $modulo 'NomeItens')
    $script:NomeItens = if ($nomeItens) { $nomeItens } else { 'item|itens' }
    $c.BotaoSimular.Visibility = if ($modulo.Escreve) { 'Visible' } else { 'Collapsed' }
    $c.BotaoAplicar.Visibility = if ($modulo.Escreve) { 'Visible' } else { 'Collapsed' }
    $c.BotaoSimular.IsEnabled = $false
    $c.BotaoAplicar.IsEnabled = $false
    $c.PainelPresets.Visibility = 'Collapsed'
    Set-TmdVisao
    $c.ListaPresets.ItemsSource = $null
    Show-TmdDetalhe

    $mensagem = Get-MensagemModulo -Modulo $modulo
    if ($mensagem) {
        Show-TmdMensagem -Icone $mensagem.Icone -Titulo $mensagem.Titulo -Texto $mensagem.Texto -Tom $mensagem.Tom
        Set-TmdStatus 'Nada para executar aqui.'
        $c.BotaoAtualizar.IsEnabled = $false
        Complete-TmdCargaInicial
        return
    }

    $c.BotaoAtualizar.IsEnabled = $true
    $especial = (Get-ValorPropriedade $modulo 'Especial') -eq $true
    $guardavel = Test-TmdPaginaGuardavel -Modulo $modulo
    # A primeira página, lida enquanto a lista de módulos carregava: usa uma vez e descarta.
    $inicial = $script:Estado.Inicial
    # Ela é sempre a primeira do catálogo; abrir outra página antes disso descarta a leitura inicial.
    if ($inicial -and -not $inicial.Pronto -and $Nome -ne @($script:Estado.Modulos)[0].Nome) { $script:Estado.Inicial = $inicial = $null }
    if ($inicial -and -not $Forcar) {
        if (-not $inicial.Pronto) {
            Show-TmdMensagem -Icone ([string][char]0xE895) -Titulo "Carregando $($modulo.Titulo)" -Texto 'Isso roda em segundo plano; a janela continua respondendo.'
            Set-TmdStatus 'Lendo…'
            Set-TmdOcupado $true
            $script:Estado.Esperando = @{ Nome = $Nome; Inicial = $true; StatusDepois = $StatusDepois }
            return
        }
        $script:Estado.Inicial = $null
        if ($inicial.Nome -eq $Nome -and -not $inicial.Erro) {
            $agora = Get-Date
            if ($guardavel) { $script:Estado.Cache[$Nome] = @{ Alvos = $inicial.Alvos; Quando = $agora } }
            Show-TmdPaginaLida -Saida $inicial.Alvos -StatusDepois $StatusDepois -Quando $agora
            Complete-TmdCargaInicial
            Start-TmdAntecipacao
            return
        }
    }
    if ($guardavel -and -not $Forcar) {
        $guardado = $script:Estado.Cache[$Nome]
        if ($guardado -and ((Get-Date) - $guardado.Quando) -lt $script:ValidadeCache) {
            Show-TmdPaginaLida -Saida $guardado.Alvos -StatusDepois $StatusDepois -Quando $guardado.Quando
            Complete-TmdCargaInicial
            return
        }
    }
    Show-TmdMensagem -Icone ([string][char]0xE895) -Titulo "Carregando $($modulo.Titulo)" -Texto 'Isso roda em segundo plano; a janela continua respondendo.'
    Set-TmdStatus 'Lendo…'
    Set-TmdOcupado $true
    # Já está sendo lida em segundo plano: espera essa mesma leitura em vez de começar outra.
    if ($guardavel -and -not $Forcar -and $script:Estado.Antecipando -and $script:Estado.Antecipando.Nome -eq $Nome) {
        $script:Estado.Esperando = @{ Nome = $Nome; StatusDepois = $StatusDepois }
        return
    }
    $codigo = if ($especial) { $script:ScriptHistorico } else { $script:ScriptBuscarAlvos }
    $parametros = if ($especial) { @{ Nucleo = $script:Estado.Nucleo } } else { @{ Nucleo = $script:Estado.Nucleo; Raiz = $script:Estado.Raiz; Nome = $Nome } }
    $script:Estado.TarefaPagina = Start-TmdTarefa -Script $codigo -Parametros $parametros `
        -Contexto @{ Nome = $Nome; StatusDepois = $StatusDepois; Especial = $especial; Guardavel = $guardavel; Geracao = $script:Estado.Geracao } `
        -AoTerminar {
        param($saida, $erro)
        $contexto = $args[1]   # 3º argumento (avisos) não é usado aqui; o 4º é o contexto
        $script:Estado.TarefaPagina = $null
        Set-TmdOcupado $false
        if ($erro) {
            Show-TmdErroPagina -Erro $erro
        }
        else {
            # @( ) por fora: "$x = if (...) { @(...) }" desmonta o array e um item só vira escalar.
            # Histórico: simulações ficam de fora (não mudaram nada e escondiam o que foi feito de verdade).
            $alvos = @(if ($contexto.Especial) { ConvertTo-AlvoHistorico -Operacoes @($saida | Where-Object { (Get-ValorPropriedade $_ 'Simulado') -ne $true }) } else { $saida })
            $agora = Get-Date
            if ($contexto.Guardavel -and $contexto.Geracao -eq $script:Estado.Geracao) { $script:Estado.Cache[$contexto.Nome] = @{ Alvos = $alvos; Quando = $agora } }
            Show-TmdPaginaLida -Saida $alvos -StatusDepois $contexto.StatusDepois -Quando $agora
        }
        Complete-TmdCargaInicial
        Start-TmdAntecipacao
    }
}

# Quanto tempo uma página lida continua valendo ao voltar nela. Atualizar (F5) sempre lê de novo.
$script:ValidadeCache = [TimeSpan]::FromMinutes(10)

# Status muda a cada segundo e o Histórico a cada ação: esses sempre são lidos na hora.
function Test-TmdPaginaGuardavel {
    param($Modulo)
    $Modulo -and $Modulo.Estado -eq 'ok' -and $Modulo.Nome -ne 'status' -and (Get-ValorPropriedade $Modulo 'Especial') -ne $true
}

function Show-TmdErroPagina {
    param([string]$Erro)
    Show-TmdMensagem -Icone $script:MarcadorEstado.quebrado -Titulo 'O módulo falhou' -Texto (Format-Frase $Erro) -Tom 'Perigo'
    Set-TmdStatus "Erro: $Erro" 'Perigo'
}

# Mostra os alvos lidos na página atual (da tarefa que acabou de ler ou do cache).
function Show-TmdPaginaLida {
    param([object[]]$Saida, $StatusDepois, [datetime]$Quando)
    $c = $script:Tela.Controles
    $script:Estado.Alvos = @($Saida)
    $script:Estado.CacheLinhas = Get-TmdCacheLinhasPagina -Nome $script:Estado.ModuloAtual
    Update-TmdBusca
    $m = Get-TmdModuloAtual
    if ($StatusDepois) { Set-TmdStatus $StatusDepois.Texto $StatusDepois.Cor }
    elseif ((Get-ValorPropriedade $m 'Especial') -eq $true -and $script:Estado.Alvos.Count -gt 0 -and
        @($script:Estado.Alvos | Where-Object { (Get-ValorPropriedade $_ 'Selecionavel') -ne $false }).Count -eq 0) {
        Set-TmdStatus 'Nada aqui pode ser desfeito (clique numa linha para ver o motivo). Ajuste que já estava aplicado se desfaz na página Ajustes.' 'Aviso'
    }
    elseif ($m.Escreve) { Update-TmdBarraAcao }
    else { Set-TmdStatus (Get-TextoStatusPagina -Quantidade $script:Estado.Alvos.Count -Escreve $false -Quando $Quando) }
    if ($m.Escreve) {
        $c.BotaoSimular.IsEnabled = $true
        $c.BotaoAplicar.IsEnabled = $true
        $presets = Get-PresetAlvo -Alvos $script:Estado.Alvos
        if ($presets.Count -gt 0) {
            $c.ListaPresets.ItemsSource = $presets
            $c.PainelPresets.Visibility = 'Visible'
        }
    }
}

# Depois que a primeira página aparece, lê as outras em segundo plano, uma por vez, na ordem da barra lateral:
# quando o usuário clicar, a página abre na hora. Só leitura (Find-Alvos); nada é alterado.
function Start-TmdAntecipacao {
    # Com a lista provisória ainda na tela, espera a de verdade (ela sabe quais módulos estão disponíveis).
    if ($script:Estado.ListaProvisoria) { return }
    if ($null -eq $script:Estado.Fila) {
        $script:Estado.Fila = [System.Collections.Generic.Queue[string]]::new()
        foreach ($m in $script:Estado.Modulos) { if (Test-TmdPaginaGuardavel -Modulo $m) { $script:Estado.Fila.Enqueue($m.Nome) } }
    }
    if ($script:Estado.Antecipando) { return }
    while ($script:Estado.Fila.Count -gt 0) {
        $nome = $script:Estado.Fila.Dequeue()
        if ($script:Estado.Cache.ContainsKey($nome)) { continue }
        if ($nome -eq $script:Estado.ModuloAtual -and $script:Estado.TarefaPagina) { continue }
        $tarefa = Start-TmdTarefa -Script $script:ScriptBuscarAlvos `
            -Parametros @{ Nucleo = $script:Estado.Nucleo; Raiz = $script:Estado.Raiz; Nome = $nome } `
            -Contexto @{ Nome = $nome; Geracao = $script:Estado.Geracao } `
            -AoTerminar {
            param($saida, $erro)
            $contexto = $args[1]
            $script:Estado.Antecipando = $null
            $alvos = @($saida)
            $agora = Get-Date
            if (-not $erro -and $contexto.Geracao -eq $script:Estado.Geracao) { $script:Estado.Cache[$contexto.Nome] = @{ Alvos = $alvos; Quando = $agora } }
            $espera = $script:Estado.Esperando
            if ($espera -and $espera.Nome -eq $contexto.Nome -and $script:Estado.ModuloAtual -eq $contexto.Nome) {
                $script:Estado.Esperando = $null
                Set-TmdOcupado $false
                if ($erro) { Show-TmdErroPagina -Erro $erro } else { Show-TmdPaginaLida -Saida $alvos -StatusDepois $espera.StatusDepois -Quando $agora }
            }
            Start-TmdAntecipacao
        }
        $script:Estado.Antecipando = @{ Nome = $nome; Tarefa = $tarefa }
        return
    }
}

# Depois de alterar o sistema, nada do que foi lido antes vale mais.
function Clear-TmdCache {
    $script:Estado.Cache = @{}
    $script:Estado.LinhasPorPagina = @{}
    $script:Estado.Geracao++
}

# Linhas já montadas de cada página (Id -> linha). Voltar a uma página já lida reaproveita as linhas e as imagens
# (montar as 190 de Ajustes levava ~0,4 s). Só valem para os mesmos objetos de alvo: página lida de novo monta de novo.
function Get-TmdCacheLinhasPagina {
    param([string]$Nome)
    if (-not $Nome) { return @{} }
    if (-not $script:Estado.LinhasPorPagina.ContainsKey($Nome)) { $script:Estado.LinhasPorPagina[$Nome] = @{} }
    $script:Estado.LinhasPorPagina[$Nome]
}

# Marca ou desmarca um alvo. A marca fica no próprio alvo, então sobrevive à busca.
# Alvo com Exclusivo (ex.: a página Fonte: uma fonte, um tamanho): marcar um desmarca os outros do mesmo grupo.
# -Redesenhar: a marca mudou por fora da caixinha (clique no quadro), e a lista precisa mostrar.
function Set-TmdSelecao {
    param([Parameter(Mandatory)]$Linha, [bool]$Selecionado, [switch]$Redesenhar)
    if ($Linha.Tipo -ne 'Alvo') { return }
    $Linha.Selecionado = $Selecionado
    if ($Linha.Alvo -and $Linha.Alvo.PSObject.Properties['Selecionado']) { $Linha.Alvo.Selecionado = $Selecionado }
    $grupo = if ($Selecionado -and $Linha.Alvo) { [string](Get-ValorPropriedade $Linha.Alvo 'Exclusivo') } else { '' }
    $mudou = [bool]$Redesenhar
    if ($grupo) {
        foreach ($a in $script:Estado.Alvos) {
            if ([object]::ReferenceEquals($a, $Linha.Alvo) -or [string](Get-ValorPropriedade $a 'Exclusivo') -ne $grupo) { continue }
            if ($a.Selecionado) { $a.Selecionado = $false; $mudou = $true }
        }
    }
    # Item que pede um valor (tamanho personalizado): marcado sem valor ainda, começa no padrão dele.
    $pede = if ($Selecionado -and $Linha.Alvo) { Get-ValorPropriedade $Linha.Alvo 'PedeValor' } else { $null }
    if ($pede -and $null -eq (Get-ValorPropriedade $Linha.Alvo 'ValorEscolhido')) { Set-TmdValorEscolhido -Linha $Linha -Valor ([double]$pede.Padrao) -SemRedesenhar; $mudou = $true }
    if ($mudou) { Update-TmdMarcasNaTela }
    Exit-TmdConfirmacao
    Update-TmdBarraAcao
}

# Os quadros não avisam a tela quando a marca muda por fora da caixinha: copia a marca dos alvos para as linhas na
# lista e redesenha (a rolagem fica onde está).
function Update-TmdMarcasNaTela {
    $c = $script:Tela.Controles
    $linhas = @($c.ListaAlvos.ItemsSource)
    foreach ($l in $linhas) {
        if ($l.Tipo -eq 'Alvo' -and $l.Alvo -and $l.Alvo.PSObject.Properties['Selecionado']) { $l.Selecionado = [bool]$l.Alvo.Selecionado }
        elseif ($l.Tipo -in 'Pasta', 'Secao' -and $l.Membros) {
            # O selo da pasta diz o que está escolhido dentro dela.
            foreach ($m in $l.Membros) { if ($m.Alvo -and $m.Alvo.PSObject.Properties['Selecionado']) { $m.Selecionado = [bool]$m.Alvo.Selecionado } }
            $nova = New-LinhaPasta -Tipo $l.Tipo -Nome $l.Nome -Categoria $l.Categoria -Membros $l.Membros
            $l.Selo = $nova.Selo; $l.TemSelo = [bool]$nova.Selo
        }
    }
    $script:Estado.RedesenhandoMarcas = $true
    try { $c.ListaAlvos.Items.Refresh() } finally { $script:Estado.RedesenhandoMarcas = $false }
}

# Valor escolhido para um item que pede valor (PedeValor): fica no alvo (vai junto para o módulo) e aparece no selo.
function Set-TmdValorEscolhido {
    param([Parameter(Mandatory)]$Linha, [double]$Valor, [switch]$SemRedesenhar)
    $pede = Get-ValorPropriedade $Linha.Alvo 'PedeValor'
    $texto = '{0}{1}' -f $Valor.ToString('0.#', [Globalization.CultureInfo]::GetCultureInfo('pt-BR')), $pede.Unidade
    $Linha.Alvo.ValorEscolhido = $Valor
    $Linha.Alvo.Selo = $texto
    $Linha.Selo = $texto
    $Linha.TemSelo = $true
    if (-not $Linha.Selecionado) { Set-TmdSelecao -Linha $Linha -Selecionado $true -Redesenhar; return }
    if (-not $SemRedesenhar) { Update-TmdMarcasNaTela; Update-TmdBarraAcao }
}

# O clique veio de dentro da caixinha de um quadro? (ela já marca sozinha; o quadro não deve marcar de novo)
function Test-TmdCliqueNaCaixa {
    param($Origem)
    $o = $Origem
    while ($o -and -not ($o -is [System.Windows.Controls.ListBoxItem])) {
        if ($o -is [System.Windows.Controls.CheckBox]) { return $true }
        $o = if ($o -is [System.Windows.Media.Visual] -or $o -is [System.Windows.Media.Media3D.Visual3D]) { [System.Windows.Media.VisualTreeHelper]::GetParent($o) } else { $null }
    }
    $false
}

function Select-TmdPreset {
    param([Parameter(Mandatory)][string]$Preset)
    $n = Set-SelecaoPreset -Alvos $script:Estado.Alvos -Preset $Preset
    Exit-TmdConfirmacao
    Update-TmdBusca
    Update-TmdBarraAcao
    if ($Preset -ne 'Nenhum') { Set-TmdStatus "Preset $($Preset): $n marcado(s) · $((Get-TmdResumoAtual).Texto) · nada é alterado sem confirmação" }
}

function Get-TmdResumoAtual {
    # Mesmo cache da tela só em página que escreve (lá as linhas também têm caixa).
    $cache = if ((Get-ValorPropriedade (Get-TmdModuloAtual) 'Escreve') -eq $true) { $script:Estado.CacheLinhas } else { $null }
    Get-ResumoSelecao -Linhas (ConvertTo-LinhaAlvo -Alvos $script:Estado.Alvos -Escreve -Cache $cache)
}

function Update-TmdBarraAcao {
    $m = Get-TmdModuloAtual
    if (-not $m -or -not $m.Escreve -or $script:Estado.Confirmando) { return }
    # Página com grupos de escolha única: diz o que está escolhido em cada um ("Fonte: Arial · Tamanho: automático").
    $grupos = @(Get-ValorPropriedade $m 'Grupos' | Where-Object { $_ })
    $resumo = if ($grupos.Count -gt 0) { Get-ResumoGrupos -Grupos $grupos -Alvos $script:Estado.Alvos } else { (Get-TmdResumoAtual).Texto }
    Set-TmdStatus "$resumo · nada é alterado sem confirmação"
}

function Exit-TmdConfirmacao {
    $c = $script:Tela.Controles
    $script:Estado.Confirmando = $false
    $m = Get-TmdModuloAtual
    $c.BotaoAplicar.Content = if ($m -and $m.RotuloAcao) { $m.RotuloAcao } else { 'Aplicar' }
    $c.BotaoSimular.Content = 'Simular'
}

# Simular: roda já. Durante a confirmação, o mesmo botão vira "Voltar".
function Invoke-TmdBotaoSimular {
    if ($script:Estado.Confirmando) {
        Exit-TmdConfirmacao
        Update-TmdBarraAcao
        return
    }
    Start-TmdAcao -Simular $true
}

# Primeiro clique mostra o resumo e pede confirmação; o segundo (Confirmar) executa.
function Invoke-TmdBotaoAplicar {
    $resumo = Get-TmdResumoAtual
    if ($resumo.Quantidade -eq 0) {
        Set-TmdStatus 'Escolha pelo menos um item.' 'Aviso'
        return
    }
    if (-not $script:Estado.Confirmando) {
        $m = Get-TmdModuloAtual
        $script:Estado.Confirmando = $true
        $script:Tela.Controles.BotaoAplicar.Content = 'Confirmar'
        $script:Tela.Controles.BotaoSimular.Content = 'Voltar'
        $alvos = if ($resumo.Quantidade -eq 1) { '1 item' } else { "$($resumo.Quantidade) itens" }
        $tamanho = if ($resumo.Bytes -gt 0) { " ($(Format-TamanhoTela $resumo.Bytes))" } else { '' }
        $aviso = Get-AvisoConfirmacao -Resumo $resumo -Especial ((Get-ValorPropriedade $m 'Especial') -eq $true)
        $avisoModulo = [string](Get-ValorPropriedade $m 'AvisoConfirmacao')
        if ($avisoModulo) { $aviso += " $avisoModulo" }
        Set-TmdStatus "$($m.RotuloAcao): $alvos$tamanho.$aviso Confirmar?" 'Aviso'
        return
    }
    Exit-TmdConfirmacao
    Start-TmdAcao -Simular $false
}

function Start-TmdAcao {
    param([bool]$Simular)

    $resumo = Get-TmdResumoAtual
    if ($resumo.Quantidade -eq 0) {
        Set-TmdStatus 'Escolha pelo menos um item.' 'Aviso'
        return
    }
    $c = $script:Tela.Controles
    $nome = $script:Estado.ModuloAtual
    Set-TmdOcupado $true
    $c.BotaoCancelar.Visibility = 'Collapsed'
    $c.BotaoSimular.IsEnabled = $false
    $c.BotaoAplicar.IsEnabled = $false
    Set-TmdStatus $(if ($Simular) { 'Simulando…' } else { 'Executando…' })
    $especial = (Get-ValorPropriedade (Get-TmdModuloAtual) 'Especial') -eq $true
    if ($especial) {
        $codigo = $script:ScriptDesfazer
        $parametros = @{ Nucleo = $script:Estado.Nucleo; Raiz = $script:Estado.Raiz; Ids = [string[]]@($resumo.Alvos | ForEach-Object { $_.IdAjuste }); Simular = $Simular }
    }
    else {
        $codigo = $script:ScriptExecutarAcao
        $parametros = @{ Nucleo = $script:Estado.Nucleo; Raiz = $script:Estado.Raiz; Nome = $nome; Alvos = $resumo.Alvos; Simular = $Simular }
    }
    $script:Estado.TarefaAcao = Start-TmdTarefa -Script $codigo -Parametros $parametros `
        -Contexto @{
        Nome = $nome; Simular = $Simular; DaParaDesfazer = ($resumo.Reversiveis -eq $resumo.Quantidade)
        Acao = $(if ($especial) { 'desfazer' } elseif (Get-ValorPropriedade (Get-TmdModuloAtual) 'Resultado') { Get-ValorPropriedade (Get-TmdModuloAtual) 'Resultado' } else { 'liberar' })
        Inicio = Get-Date
    } `
        -AoProgresso {
        param($registro, $contexto)
        $verbo = if ($contexto.Acao -eq 'desfazer') { 'Desfazendo' } else { 'Executando' }
        $p = ConvertFrom-TmdProgresso -Registro $registro -Decorrido ((Get-Date) - $contexto.Inicio) -Verbo $verbo
        $barra = $script:Tela.Controles.BarraTarefa
        $barra.IsIndeterminate = $p.Indeterminado
        if (-not $p.Indeterminado) { $barra.Value = $p.Porcento }
        Set-TmdStatus $p.Texto
    } `
        -AoTerminar {
        param($saida, $erro)
        $contexto = $args[1]   # 3º argumento (avisos) não é usado aqui; o 4º é o contexto
        $c = $script:Tela.Controles
        $script:Estado.TarefaAcao = $null
        Set-TmdOcupado $false
        $c.BotaoSimular.IsEnabled = $true
        $c.BotaoAplicar.IsEnabled = $true
        if ($erro) {
            Set-TmdStatus "Erro: $erro" 'Perigo'
            return
        }
        $texto = Get-TextoResultado -Resultados @($saida) -Simulado $contexto.Simular -Acao $contexto.Acao -DaParaDesfazer $contexto.DaParaDesfazer
        if ($contexto.Simular) {
            Set-TmdStatus $texto.Texto $texto.Cor
            return
        }
        # Uma ação pode mudar o que outras páginas mostram (ajustes e atualizações, programas e desinstalar...).
        Clear-TmdCache
        if ($script:Estado.ModuloAtual -eq $contexto.Nome) {
            # Relê a página para mostrar o que sobrou, mantendo o resultado na barra de status.
            Open-TmdPagina -Nome $contexto.Nome -StatusDepois $texto -Forcar
        }
        else {
            Set-TmdStatus $texto.Texto $texto.Cor
        }
    }
}

function Stop-TmdCargaPagina {
    param([switch]$Silencioso)
    $t = $script:Estado.TarefaPagina
    # Esperando uma leitura antecipada: só deixa de esperar; ela termina sozinha e vai para o cache.
    if ($null -eq $t -and -not $script:Estado.Esperando) { return }
    $script:Estado.Esperando = $null
    if ($t) { Stop-TmdTarefa -Tarefa $t }
    $script:Estado.TarefaPagina = $null
    Set-TmdOcupado $false
    if (-not $Silencioso) {
        Show-TmdMensagem -Icone ([string][char]0xE711) -Titulo 'Cancelado' -Texto 'Use Atualizar (F5) para tentar de novo.'
        Set-TmdStatus 'Cancelado.'
    }
}

# Quantos quadros da grade vão no primeiro desenho (numa tela grande cabem ~40).
$script:QuadrosPrimeiroDesenho = 48
# A partir de quantos itens uma página com 4+ categorias vira pastas (abaixo disso, seções com os quadros à vista).
$script:ItensParaPastas = 40

# -Inteira: põe a lista toda de uma vez (quem chama precisa achar um item nela logo em seguida, ex.: fechar pasta).
function Update-TmdBusca {
    param([switch]$Inteira)
    $c = $script:Tela.Controles
    $busca = $c.CampoBusca.Text
    $c.DicaBusca.Visibility = if ($busca) { 'Collapsed' } else { 'Visible' }
    if ($null -ne $script:Estado.TarefaPagina -or $script:Estado.Esperando -or -not $script:Estado.ModuloAtual) { return }
    $modulo = @($script:Estado.Modulos | Where-Object { $_.Nome -eq $script:Estado.ModuloAtual })[0]
    if ($modulo.Estado -ne 'ok') { return }

    $linhas = ConvertTo-LinhaAlvo -Alvos $script:Estado.Alvos -Busca $busca -Escreve:$modulo.Escreve -Cache $script:Estado.CacheLinhas
    if (Test-TmdEmGrade) {
        Set-TmdImagensLinha -Linhas $linhas
        foreach ($l in $linhas) { $l.Grande = $false }
        # Pastas de alternativas só na grade e sem busca (a busca acha o que está dentro delas).
        # Página longa com muitas categorias (Programas, Ajustes, Fonte): as categorias viram pastas e, dentro, os itens
        # ficam separados por tipo. Página curta (Limpar, Status, Reparos): seções com os quadros à vista, porque esconder
        # um ou dois itens numa pasta só atrapalha. Com poucas categorias (Desinstalar): só as pastas de alternativas.
        if (-not $busca) {
            $longa = @($linhas | Where-Object { $_.Tipo -eq 'Alvo' }).Count -ge $script:ItensParaPastas
            if ($longa -and @($linhas | Where-Object { $_.Tipo -eq 'Categoria' }).Count -ge 4) { $linhas = ConvertTo-LinhasPorCategoria -Linhas $linhas -Aberta $script:Estado.PastaAberta }
            else { $linhas = ConvertTo-LinhasComPastas -Linhas $linhas -PastaAberta $script:Estado.PastaAberta }
        }
    }
    if ($linhas.Count -eq 0) {
        if ($busca) {
            Show-TmdMensagem -Icone ([string][char]0xE721) -Titulo 'Nada encontrado' -Texto "Nenhum item desta página corresponde a “$busca”."
        }
        else {
            if ((Get-ValorPropriedade $modulo 'Especial') -eq $true) {
                Show-TmdMensagem -Icone ([string][char]0xE81C) -Titulo 'Nada feito ainda' -Texto 'O que o Tamanduá fizer de verdade (limpar, aplicar, instalar) aparece aqui, com a data. Simulações não entram.'
            }
            else { Show-TmdMensagem -Icone ([string][char]0xE73E) -Titulo 'Nada a fazer aqui' -Texto 'Esta página não achou nenhum item nesta máquina.' }
        }
        return
    }
    # Grade grande: a grade do WPF desenha todos os quadros de uma vez (não tem um painel que desenhe só os
    # visíveis). Põe os primeiros (mais do que cabem na tela) e o resto logo depois do primeiro desenho, com
    # prioridade baixa: a página aparece antes e a lista completa vem em seguida.
    $primeiros = $script:QuadrosPrimeiroDesenho
    if (-not $Inteira -and (Test-TmdEmGrade) -and $linhas.Count -gt $primeiros) {
        $colecao = [System.Collections.ObjectModel.ObservableCollection[object]]::new()
        for ($i = 0; $i -lt $primeiros; $i++) { $colecao.Add($linhas[$i]) }
        $resto = $linhas[$primeiros..($linhas.Count - 1)]
        $lista = $c.ListaAlvos
        $lista.ItemsSource = $colecao
        # GetNewClosure: o bloco leva $lista, $colecao e $resto (variáveis $script: não valem dentro dele).
        [void]$script:Tela.Janela.Dispatcher.BeginInvoke([Action] {
                # Outra página ou outra busca já trocou a lista: este resto não vale mais.
                if ([object]::ReferenceEquals($lista.ItemsSource, $colecao)) { foreach ($l in $resto) { $colecao.Add($l) } }
            }.GetNewClosure(), [Windows.Threading.DispatcherPriority]::Background)
    }
    else { $c.ListaAlvos.ItemsSource = $linhas }
    $c.PainelMensagem.Visibility = 'Collapsed'
    $c.ListaAlvos.Visibility = 'Visible'
}

# ---------- Grade ou lista ----------

# A página atual está em grade? (módulo pede grade e o usuário não trocou para lista nele)
function Test-TmdEmGrade {
    $m = Get-TmdModuloAtual
    $m -and (Get-ValorPropriedade $m 'Visualizacao') -eq 'Grade' -and $script:Estado.Visao[$m.Nome] -ne 'Lista'
}

# Troca o jeito de mostrar a lista (modelo, painel e estilo de item) e o botão de grade/lista.
function Set-TmdVisao {
    $c = $script:Tela.Controles
    $m = Get-TmdModuloAtual
    $podeGrade = $m -and (Get-ValorPropriedade $m 'Visualizacao') -eq 'Grade'
    $c.BotaoVisao.Visibility = if ($podeGrade) { 'Visible' } else { 'Collapsed' }
    if (Test-TmdEmGrade) {
        $c.ListaAlvos.ItemTemplate = $script:Tela.Janela.FindResource('ModeloGrade')
        $c.ListaAlvos.ItemsPanel = $script:Tela.Janela.FindResource('PainelGrade')
        $c.ListaAlvos.SetResourceReference([Windows.Controls.ItemsControl]::ItemContainerStyleProperty, 'ItemAlvoGrade')
        $c.IconeVisao.Text = [string][char]0xE8FD
        $c.BotaoVisao.ToolTip = 'Ver em lista'
    }
    else {
        $c.ListaAlvos.ItemTemplate = $script:VisaoLista.Modelo
        $c.ListaAlvos.ItemsPanel = $script:VisaoLista.Painel
        $c.ListaAlvos.SetResourceReference([Windows.Controls.ItemsControl]::ItemContainerStyleProperty, 'ItemAlvo')
        $c.IconeVisao.Text = [string][char]0xE80A
        $c.BotaoVisao.ToolTip = 'Ver em grade'
    }
}

function Switch-TmdVisao {
    $m = Get-TmdModuloAtual
    if (-not $m) { return }
    $script:Estado.Visao[$m.Nome] = if (Test-TmdEmGrade) { 'Lista' } else { 'Grade' }
    if ($script:Preferencias) { $script:Preferencias.Visao[$m.Nome] = $script:Estado.Visao[$m.Nome]; Save-TmdPreferencias }
    Set-TmdVisao
    Update-TmdBusca
}

# PNG do ícone -> imagem do WPF. Guardada por módulo e item: a busca refaz as linhas a cada tecla.
$script:CacheImagens = @{}
function Set-TmdImagensLinha {
    param([object[]]$Linhas)
    foreach ($l in $Linhas) {
        if (-not $l.IconePng -or $l.IconePng.Length -lt 8) { continue }
        $chave = "$($script:Estado.ModuloAtual)|$($l.Id)"
        $imagem = $script:CacheImagens[$chave]
        if (-not $imagem) {
            try {
                # ::new e não New-Object: este embrulha num PSObject, e o Binding do WPF não converte isso em imagem.
                $imagem = [Windows.Media.Imaging.BitmapImage]::new()
                $imagem.BeginInit()
                $imagem.CacheOption = [Windows.Media.Imaging.BitmapCacheOption]::OnLoad
                $imagem.StreamSource = New-Object IO.MemoryStream(, $l.IconePng)
                $imagem.EndInit()
                $imagem.Freeze()
                $script:CacheImagens[$chave] = $imagem
            }
            catch { continue }
        }
        $l.Imagem = $imagem.PSObject.BaseObject
        $l.TemImagem = $true
    }
}

function Show-TmdMensagem {
    param([string]$Icone, [string]$Titulo, [string]$Texto, [string]$Tom = 'TextoSutil')
    $c = $script:Tela.Controles
    $c.ListaAlvos.ItemsSource = $null
    $c.ListaAlvos.Visibility = 'Collapsed'
    $c.PainelMensagem.Visibility = 'Visible'
    $c.IconeMensagem.Text = $Icone
    $c.IconeMensagem.Foreground = $script:Tela.Janela.FindResource($Tom)
    $c.TituloMensagem.Text = $Titulo
    $c.TextoMensagem.Text = $Texto
}

function Show-TmdDetalhe {
    $c = $script:Tela.Controles
    $linha = $c.ListaAlvos.SelectedItem
    # Pasta selecionada (teclado) só mostra o que tem dentro; abrir é com clique ou Enter.
    if ($null -eq $linha -or $linha.Tipo -notin 'Alvo', 'Pasta', 'Secao', 'Voltar') {
        $c.PainelDetalhe.Visibility = 'Collapsed'
        $c.PainelSemSelecao.Visibility = 'Visible'
        return
    }
    $c.PainelSemSelecao.Visibility = 'Collapsed'
    $c.PainelDetalhe.Visibility = 'Visible'
    $c.DetalheNome.Text = $linha.Nome
    $c.DetalheCategoria.Text = $linha.Categoria
    if ($linha.Tipo -ne 'Alvo') {
        $d = [pscustomobject]@{ Sobre = $linha.Detalhe; Selos = @(); Problema = ''; Solucao = ''; Tom = ''; Mudancas = '' }
        $c.DetalheEstado.Text = if ($linha.Tipo -ne 'Voltar') { "$($linha.Selo) · clique ou Enter para abrir" } else { 'clique, Enter ou Esc para voltar' }
        $c.DetalheId.Text = ''
    }
    else {
        $d = Get-DetalheAlvo -Linha $linha
        $c.DetalheEstado.Text = Get-TextoEstadoAlvo -Linha $linha
        $c.DetalheId.Text = "id: $($linha.Id)"
    }
    Show-TmdCartoesDetalhe -Detalhe $d
    # Prévia de texto (fontes: o quadro tem "Aa" desenhado numa fonte) e o valor que o item pede (tamanho personalizado).
    $previa = $linha.Tipo -eq 'Alvo' -and $linha.Amostra -eq 'Aa'
    $c.CartaoAmostra.Visibility = if ($previa) { 'Visible' } else { 'Collapsed' }
    if ($previa) { $c.TextoAmostra.FontFamily = New-Object Windows.Media.FontFamily($linha.AmostraFonte) }
    $pede = if ($linha.Tipo -eq 'Alvo' -and $linha.Alvo) { Get-ValorPropriedade $linha.Alvo 'PedeValor' } else { $null }
    $c.CartaoValor.Visibility = if ($pede) { 'Visible' } else { 'Collapsed' }
    if ($pede) {
        $valor = Get-ValorPropriedade $linha.Alvo 'ValorEscolhido'
        if ($null -eq $valor) { $valor = $pede.Padrao }
        $script:Estado.MostrandoValor = $true
        try {
            $c.TituloValor.Text = $pede.Titulo
            $c.UnidadeValor.Text = $pede.Unidade
            $c.ReguaValor.Minimum = [double]$pede.Minimo
            $c.ReguaValor.Maximum = [double]$pede.Maximo
            $c.ReguaValor.TickFrequency = [double]$pede.Passo
            $c.ReguaValor.SmallChange = [double]$pede.Passo
            $c.ReguaValor.LargeChange = 5
            $c.ReguaValor.Value = [double]$valor
            $c.CampoValor.Text = ([double]$valor).ToString('0.#', [Globalization.CultureInfo]::GetCultureInfo('pt-BR'))
        }
        finally { $script:Estado.MostrandoValor = $false }
    }
}

# Número digitado no campo do cartão de valor (aceita vírgula ou ponto). Texto que não é número: fica como estava.
function Read-TmdCampoValor {
    $n = 0.0
    $texto = $script:Tela.Controles.CampoValor.Text.Trim() -replace ',', '.'
    if ([double]::TryParse($texto, [Globalization.NumberStyles]::Float, [Globalization.CultureInfo]::InvariantCulture, [ref]$n)) { Set-TmdValorDoCartao -Valor ([math]::Round($n, 1)) }
}

# Régua ou campo do cartão de valor mudou: grava no item selecionado (e marca ele).
function Set-TmdValorDoCartao {
    param([double]$Valor)
    if ($script:Estado.MostrandoValor -or $script:Estado.RedesenhandoMarcas) { return }
    $c = $script:Tela.Controles
    $linha = $c.ListaAlvos.SelectedItem
    if (-not $linha -or $linha.Tipo -ne 'Alvo' -or -not $linha.Alvo -or -not (Get-ValorPropriedade $linha.Alvo 'PedeValor')) { return }
    $pede = Get-ValorPropriedade $linha.Alvo 'PedeValor'
    $Valor = [math]::Min([double]$pede.Maximo, [math]::Max([double]$pede.Minimo, $Valor))
    $atual = Get-ValorPropriedade $linha.Alvo 'ValorEscolhido'
    if ($null -ne $atual -and [double]$atual -eq $Valor -and $linha.Selecionado) { return }
    Set-TmdValorEscolhido -Linha $linha -Valor $Valor
    # A lista redesenhada pode trocar o item selecionado; volta para este, para o cartão continuar aberto.
    if ($c.ListaAlvos.SelectedItem -ne $linha) { $c.ListaAlvos.SelectedItem = $linha }
    $script:Estado.MostrandoValor = $true
    try {
        $c.ReguaValor.Value = $Valor
        $c.CampoValor.Text = $Valor.ToString('0.#', [Globalization.CultureInfo]::GetCultureInfo('pt-BR'))
    }
    finally { $script:Estado.MostrandoValor = $false }
}

# Desenha os selos e cartões do painel de detalhes a partir de Get-DetalheAlvo.
function Show-TmdCartoesDetalhe {
    param([Parameter(Mandatory)]$Detalhe)
    $c = $script:Tela.Controles
    $c.DetalheTexto.Text = $Detalhe.Sobre
    $c.DetalheSelos.Children.Clear()
    foreach ($s in @($Detalhe.Selos)) {
        $texto = New-Object Windows.Controls.TextBlock
        $texto.Text = $s.Texto; $texto.FontSize = 11
        $texto.SetResourceReference([Windows.Controls.TextBlock]::ForegroundProperty, $s.Tom)
        $selo = New-Object Windows.Controls.Border
        $selo.CornerRadius = New-Object Windows.CornerRadius(4); $selo.Padding = New-Object Windows.Thickness(7, 1, 7, 1)
        $selo.Margin = New-Object Windows.Thickness(0, 0, 6, 4)
        $selo.SetResourceReference([Windows.Controls.Border]::BackgroundProperty, $s.Fundo)
        $selo.Child = $texto
        if ($s.Dica) { $selo.ToolTip = $s.Dica }
        [void]$c.DetalheSelos.Children.Add($selo)
    }
    $c.DetalheSelos.Visibility = if (@($Detalhe.Selos).Count -gt 0) { 'Visible' } else { 'Collapsed' }
    if ($Detalhe.Problema -or $Detalhe.Solucao) {
        $c.CartaoProblema.Visibility = 'Visible'
        $c.DetalheProblema.Text = $Detalhe.Problema
        $c.DetalheSolucao.Text = $Detalhe.Solucao
        $c.DetalheProblema.Visibility = if ($Detalhe.Problema) { 'Visible' } else { 'Collapsed' }
        $c.TituloProblema.Visibility = $c.DetalheProblema.Visibility
        $c.TituloSolucao.Visibility = if ($Detalhe.Solucao) { 'Visible' } else { 'Collapsed' }
        # Arriscado em vermelho, Atenção em amarelo; o resto com a cor normal do cartão.
        $fundo = switch ($Detalhe.Tom) { 'Perigo' { 'PerigoFundo' } 'Aviso' { 'AvisoFundo' } default { 'Superficie' } }
        $c.CartaoProblema.SetResourceReference([Windows.Controls.Border]::BackgroundProperty, $fundo)
        $c.CartaoProblema.SetResourceReference([Windows.Controls.Border]::BorderBrushProperty, $(if ($Detalhe.Tom) { $Detalhe.Tom } else { 'Borda' }))
    }
    else { $c.CartaoProblema.Visibility = 'Collapsed' }
    $c.CartaoMudancas.Visibility = if ($Detalhe.Mudancas) { 'Visible' } else { 'Collapsed' }
    $c.DetalheMudancas.Text = $Detalhe.Mudancas
}

# Abre a pasta (-Nome) ou fecha (vazio). Ao fechar, a lista volta no lugar da pasta, não no topo.
function Open-TmdPasta {
    param([string]$Nome)
    $c = $script:Tela.Controles
    $anterior = $script:Estado.PastaAberta
    $script:Estado.PastaAberta = $Nome
    # Inteira: logo abaixo a lista é rolada até a pasta, que pode estar depois dos primeiros quadros.
    Update-TmdBusca -Inteira
    $c.ListaAlvos.SelectedItem = $null
    $linhas = @($c.ListaAlvos.ItemsSource)
    $alvo = if (-not $Nome -and $anterior) { @($linhas | Where-Object { $_.Tipo -in 'Pasta', 'Secao' -and $_.Nome -eq $anterior })[0] } else { $linhas[0] }
    if ($alvo) { $c.ListaAlvos.ScrollIntoView($alvo) }
    Show-TmdDetalhe
}

# Linha (DataContext) do quadro onde o evento do mouse aconteceu, ou $null.
function Get-TmdLinhaDoEvento {
    param($Origem)
    $e = $Origem
    while ($e -and -not ($e -is [System.Windows.Controls.ListBoxItem])) {
        $e = if ($e -is [System.Windows.Media.Visual] -or $e -is [System.Windows.Media.Media3D.Visual3D]) { [System.Windows.Media.VisualTreeHelper]::GetParent($e) } else { $null }
    }
    if ($e) { $e.DataContext } else { $null }
}

# Avisa quem abriu a janela (testes, captura de tela) uma única vez, quando a primeira página terminou.
function Complete-TmdCargaInicial {
    # Com a lista provisória na tela, "carregou" ainda não é verdade: avisa quando a de verdade chegar.
    if ($script:Estado.ListaProvisoria) { $script:Estado.CargaPendente = $true; return }
    if ($script:Estado.JaAvisouCarga -or -not $script:Estado.AoCarregar) { return }
    $script:Estado.JaAvisouCarga = $true
    # Prioridade mais baixa que a do resto da grade (Update-TmdBusca): quem é avisado já acha a lista completa.
    $aviso = $script:Estado.AoCarregar
    $tela = $script:Tela
    [void]$tela.Janela.Dispatcher.BeginInvoke([Action] { & $aviso $tela }.GetNewClosure(), [Windows.Threading.DispatcherPriority]::ContextIdle)
}
