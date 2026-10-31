# Carrega o XAML, aplica o tema e devolve a janela com os controles nomeados. Não mostra nada.

$script:NomesControles = @(
    'Logo', 'BotaoTema', 'IconeTema', 'IconeAdmin', 'CampoBusca', 'DicaBusca', 'ListaModulos'
    'TituloPagina', 'SubtituloPagina', 'BotaoVisao', 'IconeVisao','PainelPresets', 'ListaPresets', 'ListaAlvos', 'PainelMensagem', 'IconeMensagem', 'TituloMensagem', 'TextoMensagem'
    'PainelSemSelecao', 'PainelDetalhe', 'DetalheNome', 'DetalheCategoria', 'DetalheTexto', 'DetalheEstado', 'DetalheId'
    'DetalheSelos', 'CartaoProblema', 'TituloProblema', 'DetalheProblema', 'TituloSolucao', 'DetalheSolucao', 'CartaoMudancas', 'DetalheMudancas'
    'BarraTarefa', 'BotaoAplicar', 'BotaoSimular', 'BotaoAtualizar', 'BotaoCancelar', 'TextoStatus'
    'DicaPagina', 'TextoDicaPagina', 'FecharDica', 'CartaoAmostra', 'TextoAmostra', 'CartaoValor', 'TituloValor', 'UnidadeValor', 'CampoValor', 'ReguaValor', 'DicaValor'
)

function Import-TmdXaml {
    param([Parameter(Mandatory)][string]$Arquivo)
    $leitor = [System.Xml.XmlReader]::Create($Arquivo)
    try { [Windows.Markup.XamlReader]::Load($leitor) } finally { $leitor.Close() }
}

function New-TmdJanela {
    param([Parameter(Mandatory)][string]$Raiz, [ValidateSet('claro', 'escuro')][string]$Tema = 'claro')

    Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase
    $pasta = Join-Path $Raiz 'interface'
    $temas = @{
        claro  = Import-TmdXaml (Join-Path $pasta 'tema-claro.xaml')
        escuro = Import-TmdXaml (Join-Path $pasta 'tema-escuro.xaml')
    }
    $janela = Import-TmdXaml (Join-Path $pasta 'janela.xaml')
    $janela.Resources.MergedDictionaries.Add($temas[$Tema])
    $janela.Resources.MergedDictionaries.Add((Import-TmdXaml (Join-Path $pasta 'estilos.xaml')))

    $controles = @{}
    foreach ($nome in $script:NomesControles) {
        $c = $janela.FindName($nome)
        if ($null -eq $c) { throw "controle $nome não encontrado em janela.xaml" }
        $controles[$nome] = $c
    }
    [pscustomobject]@{ Janela = $janela; Controles = $controles; Temas = $temas; Tema = $Tema }
}

# Troca o dicionário de cores (sempre o primeiro); os estilos usam DynamicResource e acompanham.
function Set-TmdTema {
    param([Parameter(Mandatory)]$Tela, [Parameter(Mandatory)][ValidateSet('claro', 'escuro')][string]$Tema)

    $Tela.Janela.Resources.MergedDictionaries[0] = $Tela.Temas[$Tema]
    $Tela.Tema = $Tema
    # Sol no escuro (para voltar ao claro), lua no claro.
    $Tela.Controles.IconeTema.Text = if ($Tema -eq 'escuro') { [string][char]0xE706 } else { [string][char]0xE708 }
    Set-TmdBarraTituloEscura -Janela $Tela.Janela -Escura ($Tema -eq 'escuro')
}

# Preferências da janela, em <dados>\config\interface.json: tema escolhido no botão (sem escolha, segue o Windows),
# grade ou lista por página, tamanho da janela e as dicas de página fechadas. Só quando o programa abre de verdade
# (Start-TmdInterface -LembrarPreferencias): testes e capturas nunca leem nem gravam. Arquivo ilegível = padrão.
$script:ArquivoPreferencias = ''
$script:Preferencias = $null

function New-TmdPreferencias {
    @{ Tema = ''; Visao = @{}; Largura = 0; Altura = 0; Maximizada = $false; DicasFechadas = @(); UltimaPagina = '' }
}

function Read-TmdPreferencias {
    param([Parameter(Mandatory)][string]$Arquivo)
    $p = New-TmdPreferencias
    if (-not [IO.File]::Exists($Arquivo)) { return $p }
    try {
        $j = [IO.File]::ReadAllText($Arquivo, [Text.Encoding]::UTF8) | ConvertFrom-Json
        if ($j.PSObject.Properties['Tema'] -and [string]$j.Tema -in 'claro', 'escuro') { $p.Tema = [string]$j.Tema }
        if ($j.PSObject.Properties['Visao'] -and $j.Visao) {
            foreach ($v in $j.Visao.PSObject.Properties) { if ([string]$v.Value -in 'Grade', 'Lista') { $p.Visao[$v.Name] = [string]$v.Value } }
        }
        if ($j.PSObject.Properties['Largura']) { $p.Largura = [double]$j.Largura }
        if ($j.PSObject.Properties['Altura']) { $p.Altura = [double]$j.Altura }
        if ($j.PSObject.Properties['Maximizada']) { $p.Maximizada = [bool]$j.Maximizada }
        if ($j.PSObject.Properties['UltimaPagina'] -and [string]$j.UltimaPagina -match '^[a-z0-9-]+$') { $p.UltimaPagina = [string]$j.UltimaPagina }
        if ($j.PSObject.Properties['DicasFechadas']) { $p.DicasFechadas = @($j.DicasFechadas | ForEach-Object { [string]$_ }) }
    }
    catch { Write-Verbose "preferências ilegíveis, usando o padrão: $($_.Exception.Message)" }
    $p
}

# Grava as preferências atuais (se estiverem ligadas). Falhar aqui nunca atrapalha a janela.
function Save-TmdPreferencias {
    if (-not $script:ArquivoPreferencias -or -not $script:Preferencias) { return }
    try {
        [void][IO.Directory]::CreateDirectory((Split-Path -Parent $script:ArquivoPreferencias))
        [IO.File]::WriteAllText($script:ArquivoPreferencias, ($script:Preferencias | ConvertTo-Json -Depth 4), (New-Object Text.UTF8Encoding $false))
    }
    catch { Write-Verbose "não deu para guardar as preferências: $($_.Exception.Message)" }
}

# Tamanho guardado (cabendo na tela) e, ao fechar, guarda o de agora (o "normal", mesmo maximizada).
function Set-TmdTamanhoJanela {
    param([Parameter(Mandatory)]$Janela)
    $p = $script:Preferencias
    $area = [System.Windows.SystemParameters]::WorkArea
    if ($p.Largura -ge $Janela.MinWidth -and $p.Altura -ge $Janela.MinHeight) {
        $Janela.Width = [math]::Min($p.Largura, $area.Width)
        $Janela.Height = [math]::Min($p.Altura, $area.Height)
    }
    if ($p.Maximizada) { $Janela.WindowState = 'Maximized' }
    $Janela.Add_Closing({
            $j = $args[0]
            $normal = if ($j.WindowState -eq 'Normal') { New-Object Windows.Rect(0, 0, $j.ActualWidth, $j.ActualHeight) } else { $j.RestoreBounds }
            if (-not $normal.IsEmpty -and $normal.Width -gt 0) { $script:Preferencias.Largura = [math]::Round($normal.Width); $script:Preferencias.Altura = [math]::Round($normal.Height) }
            $script:Preferencias.Maximizada = $j.WindowState -eq 'Maximized'
            Save-TmdPreferencias
        })
}

# Tema do Windows para apps (Configurações > Personalização > Cores). Só leitura.
function Get-TmdTemaWindows {
    try {
        $v = Get-ItemProperty -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize' -Name AppsUseLightTheme -ErrorAction Stop
        if ($v.AppsUseLightTheme -eq 0) { return 'escuro' }
    }
    catch {
        Write-Verbose "Tema do Windows não encontrado: $($_.Exception.Message)"
    }
    'claro'
}

# Barra de título escura no Windows 10 20H1+ / 11. Puramente cosmético: falhou, segue sem.
function Set-TmdBarraTituloEscura {
    param([Parameter(Mandatory)]$Janela, [bool]$Escura)
    try {
        $handle = (New-Object System.Windows.Interop.WindowInteropHelper($Janela)).Handle
        if ($handle -eq [IntPtr]::Zero) { return }
        if (-not ('Tamandua.Dwm' -as [type])) {
            Add-Type -Namespace Tamandua -Name Dwm -MemberDefinition @'
[DllImport("dwmapi.dll")] public static extern int DwmSetWindowAttribute(IntPtr hwnd, int attr, ref int value, int size);
'@
        }
        $valor = [int]$Escura
        [void][Tamandua.Dwm]::DwmSetWindowAttribute($handle, 20, [ref]$valor, 4)
    }
    catch {
        Write-Verbose "Barra de título escura indisponível: $($_.Exception.Message)"
    }
}

# Identidade própria na barra de tarefas (senão o Windows agrupa com o PowerShell e usa o ícone dele) e o console.
function Initialize-TmdProcessoJanela {
    if ('Tamandua.Processo' -as [type]) { return }
    Add-Type -Namespace Tamandua -Name Processo -MemberDefinition @'
[DllImport("shell32.dll", CharSet = CharSet.Unicode)] public static extern int SetCurrentProcessExplicitAppUserModelID(string id);
[DllImport("kernel32.dll")] public static extern IntPtr GetConsoleWindow();
[DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr h, int comando);
'@
}

function Set-TmdIdentidadeApp {
    try { Initialize-TmdProcessoJanela; [void][Tamandua.Processo]::SetCurrentProcessExplicitAppUserModelID('Tamandua.Tamandua') }
    catch { Write-Verbose "sem identidade própria na barra de tarefas: $($_.Exception.Message)" }
}

# Ícone da janela (barra de tarefas, Alt+Tab): o mesmo logo do topo, desenhado em 64 px. Depois da janela carregada,
# quando o logo já tem as cores do tema.
function Set-TmdIconeJanela {
    param([Parameter(Mandatory)]$Tela)
    try {
        $lado = 64
        $visual = New-Object Windows.Media.DrawingVisual
        $dc = $visual.RenderOpen()
        $dc.DrawRectangle((New-Object Windows.Media.VisualBrush($Tela.Controles.Logo)), $null, (New-Object Windows.Rect(0, 0, $lado, $lado)))
        $dc.Close()
        $imagem = New-Object Windows.Media.Imaging.RenderTargetBitmap($lado, $lado, 96, 96, [Windows.Media.PixelFormats]::Pbgra32)
        $imagem.Render($visual)
        $imagem.Freeze()
        $Tela.Janela.Icon = $imagem
    }
    catch { Write-Verbose "sem ícone próprio: $($_.Exception.Message)" }
}

# Esconde o console de onde o programa foi aberto, se pediram (-EsconderConsole: Tamandua.cmd e a cópia de admin).
# Só depois da janela na tela, para nunca ficar sem nada visível; quem abriu pelo próprio terminal não pede isso.
function Hide-TmdConsole {
    if ($env:TAMANDUA_ESCONDER_CONSOLE -ne '1') { return }
    try {
        Initialize-TmdProcessoJanela
        $h = [Tamandua.Processo]::GetConsoleWindow()
        if ($h -ne [IntPtr]::Zero) { [void][Tamandua.Processo]::ShowWindow($h, 0) }
    }
    catch { Write-Verbose "console não escondido: $($_.Exception.Message)" }
}

function Test-TmdAdmin {
    $identidade = [Security.Principal.WindowsIdentity]::GetCurrent()
    (New-Object Security.Principal.WindowsPrincipal($identidade)).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}
