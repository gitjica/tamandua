<#
.SYNOPSIS
    Abre a interface, espera a primeira página carregar e salva um PNG do conteúdo da janela. Para revisar o visual.
.EXAMPLE
    .\ferramentas\capturar-interface.ps1 -Saida C:\temp\claro.png -Tema claro
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$Saida,
    [ValidateSet('claro', 'escuro')][string]$Tema = 'claro',
    # Módulo a abrir antes da captura (por padrão, o primeiro disponível).
    [string]$Modulo
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$raiz = Split-Path -Parent $PSScriptRoot
Import-Module (Join-Path $raiz 'interface\Interface.psm1') -Force -DisableNameChecking

$arquivo = [IO.Path]::GetFullPath($Saida)
$moduloInicial = $Modulo
$aoCarregar = {
    param($tela)
    if ($moduloInicial) {
        $item = @($tela.Controles.ListaModulos.ItemsSource | Where-Object { $_.Nome -eq $moduloInicial })[0]
        $tela.Controles.ListaModulos.SelectedItem = $item
    }
    # Deixa o WPF terminar layout e desenho antes de capturar.
    $tela.Janela.Dispatcher.Invoke([Action] {}, [Windows.Threading.DispatcherPriority]::ContextIdle)
    $conteudo = $tela.Janela.Content
    $imagem = New-Object Windows.Media.Imaging.RenderTargetBitmap([int]$conteudo.ActualWidth, [int]$conteudo.ActualHeight, 96, 96, [Windows.Media.PixelFormats]::Pbgra32)
    $imagem.Render($conteudo)
    $codificador = New-Object Windows.Media.Imaging.PngBitmapEncoder
    $codificador.Frames.Add([Windows.Media.Imaging.BitmapFrame]::Create($imagem))
    $fluxo = [IO.File]::Create($arquivo)
    try { $codificador.Save($fluxo) } finally { $fluxo.Close() }
    $tela.Janela.Close()
}.GetNewClosure()

Start-TmdInterface -Raiz $raiz -Tema $Tema -AoCarregar $aoCarregar -FecharAposSeg 30
Write-Output $arquivo
