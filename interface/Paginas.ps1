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
        # Pasta de alternativas aberta na grade (nome do grupo), ou vazio.
        PastaAberta   = ''
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
    $c.CampoBusca.Add_TextChanged({ Invoke-TmdProtegido { Update-TmdBusca } })
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
            if (-not (Test-TmdAdmin)) { $texto += ' · sem administrador: o que tem escudo pede permissão na hora' }
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
    $script:Estado.PastaAberta = ''
    Exit-TmdConfirmacao
    $c.TituloPagina.Text = $modulo.Titulo
    $c.SubtituloPagina.Text = if ($modulo.Descricao) { "$($modulo.Grupo) · $($modulo.Descricao)" } else { $modulo.Grupo }
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
            $alvos = @(if ($contexto.Especial) { ConvertTo-AlvoHistorico -Operacoes @($saida) } else { $saida })
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
    $script:Estado.Geracao++
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

function Update-TmdBusca {
    $c = $script:Tela.Controles
    $busca = $c.CampoBusca.Text
    $c.DicaBusca.Visibility = if ($busca) { 'Collapsed' } else { 'Visible' }
    if ($null -ne $script:Estado.TarefaPagina -or $script:Estado.Esperando -or -not $script:Estado.ModuloAtual) { return }
    $modulo = @($script:Estado.Modulos | Where-Object { $_.Nome -eq $script:Estado.ModuloAtual })[0]
    if ($modulo.Estado -ne 'ok') { return }

    $linhas = ConvertTo-LinhaAlvo -Alvos $script:Estado.Alvos -Busca $busca -Escreve:$modulo.Escreve
    if (Test-TmdEmGrade) {
        Set-TmdImagensLinha -Linhas $linhas
        # Pastas de alternativas só na grade e sem busca (a busca acha o que está dentro delas).
        if (-not $busca) { $linhas = ConvertTo-LinhasComPastas -Linhas $linhas -PastaAberta $script:Estado.PastaAberta }
    }
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
    # Clique numa pasta abre; no "Voltar", fecha. Depois do evento de seleção, para não trocar a lista no meio dele.
    if ($linha -and $linha.Tipo -in 'Pasta', 'Voltar') {
        Open-TmdPasta -Nome $(if ($linha.Tipo -eq 'Pasta') { $linha.Nome } else { '' })
        return
    }
    if ($null -eq $linha -or $linha.Tipo -ne 'Alvo') {
        $c.PainelDetalhe.Visibility = 'Collapsed'
        $c.PainelSemSelecao.Visibility = 'Visible'
        return
    }
    $c.PainelSemSelecao.Visibility = 'Collapsed'
    $c.PainelDetalhe.Visibility = 'Visible'
    $c.DetalheNome.Text = $linha.Nome
    $c.DetalheCategoria.Text = $linha.Categoria
    $c.DetalheTexto.Text = Get-TextoDetalheAlvo -Linha $linha
    $c.DetalheEstado.Text = Get-TextoEstadoAlvo -Linha $linha
    $c.DetalheId.Text = "id: $($linha.Id)"
}

function Open-TmdPasta {
    param([string]$Nome)
    $script:Estado.PastaAberta = $Nome
    [void]$script:Tela.Janela.Dispatcher.BeginInvoke([Action] { Invoke-TmdProtegido { Update-TmdBusca; Show-TmdDetalhe } })
}

# Avisa quem abriu a janela (testes, captura de tela) uma única vez, quando a primeira página terminou.
function Complete-TmdCargaInicial {
    if ($script:Estado.JaAvisouCarga -or -not $script:Estado.AoCarregar) { return }
    $script:Estado.JaAvisouCarga = $true
    & $script:Estado.AoCarregar $script:Tela
}
