# Carrega o XAML, aplica o tema e devolve a janela com os controles nomeados. Não mostra nada.

$script:NomesControles = @(
    'BotaoTema', 'IconeTema', 'IconeAdmin', 'CampoBusca', 'DicaBusca', 'ListaModulos'
    'TituloPagina', 'SubtituloPagina', 'PainelPresets', 'ListaPresets', 'ListaAlvos', 'PainelMensagem', 'IconeMensagem', 'TituloMensagem', 'TextoMensagem'
    'PainelSemSelecao', 'PainelDetalhe', 'DetalheNome', 'DetalheCategoria', 'DetalheTexto', 'DetalheEstado', 'DetalheId'
    'BarraTarefa', 'BotaoAplicar', 'BotaoSimular', 'BotaoAtualizar', 'BotaoCancelar', 'TextoStatus'
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

function Test-TmdAdmin {
    $identidade = [Security.Principal.WindowsIdentity]::GetCurrent()
    (New-Object Security.Principal.WindowsPrincipal($identidade)).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}
