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
        AoCarregar    = $AoCarregar
        JaAvisouCarga = $false
    }
    $c = $Tela.Controles

    $admin = Test-TmdAdmin
    $c.IconeAdmin.ToolTip = if ($admin) { 'Rodando como administrador' } else { 'Rodando sem permissão de administrador' }

    $c.ListaModulos.Add_SelectionChanged({ Invoke-TmdProtegido { Open-TmdPaginaSelecionada } })
    $c.ListaAlvos.Add_SelectionChanged({ Invoke-TmdProtegido { Show-TmdDetalhe } })
    $c.CampoBusca.Add_TextChanged({ Invoke-TmdProtegido { Update-TmdBusca } })
    $c.BotaoAtualizar.Add_Click({ Invoke-TmdProtegido { Open-TmdPagina -Nome $script:Estado.ModuloAtual } })
    $c.BotaoCancelar.Add_Click({ Invoke-TmdProtegido { Stop-TmdCargaPagina } })
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
                Invoke-TmdProtegido { Open-TmdPagina -Nome $script:Estado.ModuloAtual }
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
            $script:Estado.Modulos = @($saida)
            $script:Tela.Controles.ListaModulos.ItemsSource = ConvertTo-ItemNavegacao -Modulos $script:Estado.Modulos
            $disponiveis = @($script:Estado.Modulos | Where-Object { $_.Estado -eq 'ok' }).Count
            $texto = "$disponiveis de $($script:Estado.Modulos.Count) módulos disponíveis"
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
    $primeiro = @($itens | Where-Object { $_.Estado -eq 'ok' } | Select-Object -First 1)
    if ($primeiro.Count -eq 0) { $primeiro = @($itens[0]) }
    $script:Tela.Controles.ListaModulos.SelectedItem = $primeiro[0]
}

function Open-TmdPaginaSelecionada {
    $item = $script:Tela.Controles.ListaModulos.SelectedItem
    if ($null -eq $item -or $item.Tipo -ne 'Modulo') { return }
    Open-TmdPagina -Nome $item.Nome
}

function Open-TmdPagina {
    param([string]$Nome)
    if (-not $Nome) { return }

    $modulo = @($script:Estado.Modulos | Where-Object { $_.Nome -eq $Nome })[0]
    $c = $script:Tela.Controles
    Stop-TmdCargaPagina -Silencioso
    $script:Estado.ModuloAtual = $Nome
    $script:Estado.Alvos = @()
    $c.TituloPagina.Text = $modulo.Titulo
    $c.SubtituloPagina.Text = if ($modulo.Descricao) { "$($modulo.Grupo) · $($modulo.Descricao)" } else { $modulo.Grupo }
    $c.BotaoSimular.Visibility = if ($modulo.Escreve) { 'Visible' } else { 'Collapsed' }
    $c.BotaoAplicar.Visibility = if ($modulo.Escreve) { 'Visible' } else { 'Collapsed' }
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
    Show-TmdMensagem -Icone ([string][char]0xE895) -Titulo "Lendo $($modulo.Titulo.ToLower())" -Texto 'Isso roda em segundo plano; a janela continua respondendo.'
    Set-TmdStatus 'Lendo…'
    Set-TmdOcupado $true
    $script:Estado.TarefaPagina = Start-TmdTarefa -Script $script:ScriptBuscarAlvos `
        -Parametros @{ Nucleo = $script:Estado.Nucleo; Raiz = $script:Estado.Raiz; Nome = $Nome } `
        -AoTerminar {
        param($saida, $erro)
        $script:Estado.TarefaPagina = $null
        Set-TmdOcupado $false
        if ($erro) {
            Show-TmdMensagem -Icone $script:MarcadorEstado.quebrado -Titulo 'O módulo falhou' -Texto (Format-Frase $erro) -Tom 'Perigo'
            Set-TmdStatus "Erro: $erro" 'Perigo'
        }
        else {
            $script:Estado.Alvos = @($saida)
            Update-TmdBusca
            $m = @($script:Estado.Modulos | Where-Object { $_.Nome -eq $script:Estado.ModuloAtual })[0]
            Set-TmdStatus (Get-TextoStatusPagina -Quantidade $script:Estado.Alvos.Count -Escreve $m.Escreve -Quando (Get-Date))
        }
        Complete-TmdCargaInicial
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

    $linhas = ConvertTo-LinhaAlvo -Alvos $script:Estado.Alvos -Busca $busca
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
    $c.DetalheTexto.Text = $linha.Detalhe
    $c.DetalheEstado.Text = Get-TextoEstadoAlvo -Linha $linha
    $c.DetalheId.Text = "id: $($linha.Id)"
}

# Avisa quem abriu a janela (testes, captura de tela) uma única vez, quando a primeira página terminou.
function Complete-TmdCargaInicial {
    if ($script:Estado.JaAvisouCarga -or -not $script:Estado.AoCarregar) { return }
    $script:Estado.JaAvisouCarga = $true
    & $script:Estado.AoCarregar $script:Tela
}
