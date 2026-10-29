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
    }
    $c = $Tela.Controles

    $admin = Test-TmdAdmin
    $c.IconeAdmin.ToolTip = if ($admin) { 'Rodando como administrador' } else { 'Rodando sem permissão de administrador' }

    $c.ListaModulos.Add_SelectionChanged({ Invoke-TmdProtegido { Open-TmdPaginaSelecionada } })
    $c.ListaAlvos.Add_SelectionChanged({ Invoke-TmdProtegido { Show-TmdDetalhe } })
    $c.CampoBusca.Add_TextChanged({ Invoke-TmdProtegido { Update-TmdBusca } })
    $c.BotaoAtualizar.Add_Click({ Invoke-TmdProtegido { Open-TmdPagina -Nome $script:Estado.ModuloAtual -Caminho $script:Estado.Caminho } })
    # Duplo clique (ou Enter) num item navegável abre a pasta dele na mesma página.
    $c.ListaAlvos.Add_MouseDoubleClick({ Invoke-TmdProtegido { Open-TmdItemSelecionado } })
    $c.ListaAlvos.Add_KeyDown({
            $evento = $args[1]
            if ($evento.Key -eq 'Return') { Invoke-TmdProtegido { Open-TmdItemSelecionado }; $evento.Handled = $true }
        })
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
            }
        })
    $Tela.Janela.Add_PreviewKeyDown({
            $e = $args[1]
            if ($e.Key -eq 'F' -and [System.Windows.Input.Keyboard]::Modifiers -eq 'Control') {
                [void]$script:Tela.Controles.CampoBusca.Focus()
                $e.Handled = $true
            }
            elseif ($e.Key -eq 'Escape' -and $script:Tela.Controles.CampoBusca.IsKeyboardFocused) {
                $script:Tela.Controles.CampoBusca.Text = ''
                $e.Handled = $true
            }
            elseif ($e.Key -eq 'F5') {
                Invoke-TmdProtegido { Open-TmdPagina -Nome $script:Estado.ModuloAtual -Caminho $script:Estado.Caminho }
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
    $Tela.Janela.Add_Closed({ $script:Relogio.Stop() })
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
    $c.BotaoCancelar.Visibility = if ($Ocupado) { 'Visible' } else { 'Collapsed' }
    $c.BotaoAtualizar.IsEnabled = -not $Ocupado
}

function Start-TmdCargaModulos {
    Set-TmdStatus 'Carregando módulos…'
    Set-TmdOcupado $true
    Show-TmdMensagem -Icone ([string][char]0xE895) -Titulo 'Carregando módulos' -Texto 'Verificando o que está disponível nesta máquina.'
    [void](Start-TmdTarefa -Script $script:ScriptCarregarModulos `
            -Parametros @{ Nucleo = $script:Estado.Nucleo; Raiz = $script:Estado.Raiz } `
            -AoTerminar {
            param($saida, $erro, $avisos)
            Set-TmdOcupado $false
            if ($erro) {
                Show-TmdMensagem -Icone $script:MarcadorEstado.quebrado -Titulo 'Não foi possível carregar os módulos' -Texto (Format-Frase $erro) -Tom 'Perigo'
                Set-TmdStatus "Erro: $erro" 'Perigo'
                Complete-TmdCargaInicial
                return
            }
            $modulos = @($saida)
            $disponiveis = @($modulos | Where-Object { $_.Estado -eq 'ok' }).Count
            $texto = "$disponiveis de $($modulos.Count) módulos disponíveis"
            $script:Estado.Modulos = $modulos + $script:PaginaHistorico
            $script:Tela.Controles.ListaModulos.ItemsSource = ConvertTo-ItemNavegacao -Modulos $script:Estado.Modulos
            if ($avisos) { Set-TmdStatus "$texto · $($avisos -join ' · ')" 'Aviso' } else { Set-TmdStatus $texto }
            Select-TmdModuloInicial
        })
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
    $item = $script:Tela.Controles.ListaModulos.SelectedItem
    if ($null -eq $item -or $item.Tipo -ne 'Modulo') { return }
    Open-TmdPagina -Nome $item.Nome
}

function Get-TmdModuloAtual {
    @($script:Estado.Modulos | Where-Object { $_.Nome -eq $script:Estado.ModuloAtual })[0]
}

function Open-TmdItemSelecionado {
    $linha = $script:Tela.Controles.ListaAlvos.SelectedItem
    if ($null -eq $linha -or $linha.Tipo -ne 'Alvo' -or -not $linha.Alvo) { return }
    if ((Get-ValorPropriedade $linha.Alvo 'Navegavel') -ne $true) { return }
    Open-TmdPagina -Nome $script:Estado.ModuloAtual -Caminho ([string](Get-ValorPropriedade $linha.Alvo 'Caminho'))
}

# -StatusDepois: texto (e cor) para a barra de status quando a página terminar de carregar, no lugar do padrão.
# -Caminho: pasta aberta, em módulos que navegam (analisar). Trocar de módulo volta ao início dele.
function Open-TmdPagina {
    param([string]$Nome, $StatusDepois, [string]$Caminho = '')
    if (-not $Nome) { return }

    $modulo = @($script:Estado.Modulos | Where-Object { $_.Nome -eq $Nome })[0]
    $c = $script:Tela.Controles
    Stop-TmdCargaPagina -Silencioso
    $script:Estado.ModuloAtual = $Nome
    $script:Estado.Caminho = $Caminho
    $script:Estado.Alvos = @()
    Exit-TmdConfirmacao
    $c.TituloPagina.Text = $modulo.Titulo
    $c.SubtituloPagina.Text = if ($Caminho) { "$($modulo.Grupo) · $Caminho" }
    elseif ($modulo.Descricao) { "$($modulo.Grupo) · $($modulo.Descricao)" }
    else { $modulo.Grupo }
    $c.BotaoSimular.Visibility = if ($modulo.Escreve) { 'Visible' } else { 'Collapsed' }
    $c.BotaoAplicar.Visibility = if ($modulo.Escreve) { 'Visible' } else { 'Collapsed' }
    $c.BotaoSimular.IsEnabled = $false
    $c.BotaoAplicar.IsEnabled = $false
    $c.PainelPresets.Visibility = 'Collapsed'
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
    Show-TmdMensagem -Icone ([string][char]0xE895) -Titulo "Carregando $($modulo.Titulo)" -Texto 'Isso roda em segundo plano; a janela continua respondendo.'
    Set-TmdStatus 'Lendo…'
    Set-TmdOcupado $true
    $especial = (Get-ValorPropriedade $modulo 'Especial') -eq $true
    $codigo = if ($especial) { $script:ScriptHistorico } else { $script:ScriptBuscarAlvos }
    $parametros = if ($especial) { @{ Nucleo = $script:Estado.Nucleo } } else { @{ Nucleo = $script:Estado.Nucleo; Raiz = $script:Estado.Raiz; Nome = $Nome; Caminho = $Caminho } }
    $script:Estado.TarefaPagina = Start-TmdTarefa -Script $codigo -Parametros $parametros `
        -Contexto @{ StatusDepois = $StatusDepois; Especial = $especial } `
        -AoTerminar {
        param($saida, $erro)
        $contexto = $args[1]   # 3º argumento (avisos) não é usado aqui; o 4º é o contexto
        $c = $script:Tela.Controles
        $script:Estado.TarefaPagina = $null
        Set-TmdOcupado $false
        if ($erro) {
            Show-TmdMensagem -Icone $script:MarcadorEstado.quebrado -Titulo 'O módulo falhou' -Texto (Format-Frase $erro) -Tom 'Perigo'
            Set-TmdStatus "Erro: $erro" 'Perigo'
        }
        else {
            # @( ) por fora: "$x = if (...) { @(...) }" desmonta o array e um item só vira escalar.
            $script:Estado.Alvos = @(if ($contexto.Especial) { ConvertTo-AlvoHistorico -Operacoes @($saida) } else { $saida })
            Update-TmdBusca
            $m = Get-TmdModuloAtual
            if ($contexto.StatusDepois) { Set-TmdStatus $contexto.StatusDepois.Texto $contexto.StatusDepois.Cor }
            elseif ($m.Escreve) { Update-TmdBarraAcao }
            else { Set-TmdStatus (Get-TextoStatusPagina -Quantidade $script:Estado.Alvos.Count -Escreve $false -Quando (Get-Date)) }
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
        Complete-TmdCargaInicial
    }
}

# Marca ou desmarca um alvo. A marca fica no próprio alvo, então sobrevive à busca.
function Set-TmdSelecao {
    param([Parameter(Mandatory)]$Linha, [bool]$Selecionado)
    if ($Linha.Tipo -ne 'Alvo') { return }
    $Linha.Selecionado = $Selecionado
    if ($Linha.Alvo -and $Linha.Alvo.PSObject.Properties['Selecionado']) { $Linha.Alvo.Selecionado = $Selecionado }
    Exit-TmdConfirmacao
    Update-TmdBarraAcao
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
    Get-ResumoSelecao -Linhas (ConvertTo-LinhaAlvo -Alvos $script:Estado.Alvos -Escreve)
}

function Update-TmdBarraAcao {
    $m = Get-TmdModuloAtual
    if (-not $m -or -not $m.Escreve -or $script:Estado.Confirmando) { return }
    Set-TmdStatus "$((Get-TmdResumoAtual).Texto) · nada é alterado sem confirmação"
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
        $parametros = @{ Nucleo = $script:Estado.Nucleo; Ids = [string[]]@($resumo.Alvos | ForEach-Object { $_.IdAjuste }); Simular = $Simular }
    }
    else {
        $codigo = $script:ScriptExecutarAcao
        $parametros = @{ Nucleo = $script:Estado.Nucleo; Raiz = $script:Estado.Raiz; Nome = $nome; Alvos = $resumo.Alvos; Simular = $Simular }
    }
    $script:Estado.TarefaAcao = Start-TmdTarefa -Script $codigo -Parametros $parametros `
        -Contexto @{
        Nome = $nome; Simular = $Simular; DaParaDesfazer = ($resumo.Reversiveis -eq $resumo.Quantidade)
        Acao = $(if ($especial) { 'desfazer' } elseif (Get-ValorPropriedade (Get-TmdModuloAtual) 'Resultado') { Get-ValorPropriedade (Get-TmdModuloAtual) 'Resultado' } else { 'liberar' })
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
        }
        elseif ($script:Estado.ModuloAtual -eq $contexto.Nome) {
            # Relê a página para mostrar o que sobrou, mantendo o resultado na barra de status.
            Open-TmdPagina -Nome $contexto.Nome -StatusDepois $texto
        }
        else {
            Set-TmdStatus $texto.Texto $texto.Cor
        }
    }
}

function Stop-TmdCargaPagina {
    param([switch]$Silencioso)
    $t = $script:Estado.TarefaPagina
    if ($null -eq $t) { return }
    Stop-TmdTarefa -Tarefa $t
    $script:Estado.TarefaPagina = $null
    Set-TmdOcupado $false
    if (-not $Silencioso) {
        Show-TmdMensagem -Icone ([string][char]0xE711) -Titulo 'Cancelado' -Texto 'Use Atualizar (F5) para tentar de novo.'
        Set-TmdStatus 'Cancelado.'
    }
}

function Update-TmdBusca {
    $c = $script:Tela.Controles
    $busca = $c.CampoBusca.Text
    $c.DicaBusca.Visibility = if ($busca) { 'Collapsed' } else { 'Visible' }
    if ($null -ne $script:Estado.TarefaPagina -or -not $script:Estado.ModuloAtual) { return }
    $modulo = @($script:Estado.Modulos | Where-Object { $_.Nome -eq $script:Estado.ModuloAtual })[0]
    if ($modulo.Estado -ne 'ok') { return }

    $linhas = ConvertTo-LinhaAlvo -Alvos $script:Estado.Alvos -Busca $busca -Escreve:$modulo.Escreve
    if ($linhas.Count -eq 0) {
        if ($busca) {
            Show-TmdMensagem -Icone ([string][char]0xE721) -Titulo 'Nada encontrado' -Texto "Nenhum item desta página corresponde a “$busca”."
        }
        else {
            Show-TmdMensagem -Icone ([string][char]0xE73E) -Titulo 'Nada a fazer aqui' -Texto 'O módulo não encontrou nenhum item.'
        }
        return
    }
    $c.ListaAlvos.ItemsSource = $linhas
    $c.PainelMensagem.Visibility = 'Collapsed'
    $c.ListaAlvos.Visibility = 'Visible'
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
    if ($null -eq $linha -or $linha.Tipo -ne 'Alvo') {
        $c.PainelDetalhe.Visibility = 'Collapsed'
        $c.PainelSemSelecao.Visibility = 'Visible'
        return
    }
    $c.PainelSemSelecao.Visibility = 'Collapsed'
    $c.PainelDetalhe.Visibility = 'Visible'
    $c.DetalheNome.Text = $linha.Nome
    $c.DetalheCategoria.Text = $linha.Categoria
    $mudancas = @(Get-ValorPropriedade $linha.Alvo 'Mudancas' | Where-Object { $_ })
    $c.DetalheTexto.Text = if ($mudancas.Count -gt 0) {
        "$($linha.Detalhe)`n`nO que acontece:`n• $($mudancas -join "`n• ")"
    }
    else { $linha.Detalhe }
    $c.DetalheEstado.Text = Get-TextoEstadoAlvo -Linha $linha
    $c.DetalheId.Text = "id: $($linha.Id)"
    if ((Get-ValorPropriedade $linha.Alvo 'Navegavel') -eq $true) {
        $c.DetalheEstado.Text = "Clique duas vezes (ou Enter) para abrir.`n$(Get-ValorPropriedade $linha.Alvo 'Caminho')"
    }
}

# Avisa quem abriu a janela (testes, captura de tela) uma única vez, quando a primeira página terminou.
function Complete-TmdCargaInicial {
    if ($script:Estado.JaAvisouCarga -or -not $script:Estado.AoCarregar) { return }
    $script:Estado.JaAvisouCarga = $true
    & $script:Estado.AoCarregar $script:Tela
}
