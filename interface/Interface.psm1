# Interface gráfica (WPF). Opcional: se esta pasta faltar ou falhar, o tamandua.ps1 cai no menu de texto.
# Só conversa com o núcleo por tarefas em segundo plano; não tem lógica de sistema.

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

foreach ($parte in 'Conversao', 'SegundoPlano', 'Janela', 'Paginas') {
    . (Join-Path $PSScriptRoot "$parte.ps1")
}

function Start-TmdInterface {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Raiz,
        [ValidateSet('', 'claro', 'escuro')][string]$Tema = '',
        # Chamado uma vez quando a primeira página termina de carregar; recebe a tela. Usado por testes e capturas.
        [scriptblock]$AoCarregar,
        # Fecha a janela sozinha depois desse tempo (0 = nunca). Garante que testes não fiquem presos numa janela aberta.
        [int]$FecharAposSeg = 0,
        # Lembra tema, grade/lista, tamanho da janela e dicas fechadas entre uma vez e outra (só o programa de verdade).
        [switch]$LembrarPreferencias
    )

    if ([Threading.Thread]::CurrentThread.GetApartmentState() -ne 'STA') {
        throw 'a interface precisa de um processo STA (rode com powershell.exe)'
    }
    $script:ArquivoPreferencias = ''
    $script:Preferencias = New-TmdPreferencias
    if ($LembrarPreferencias) {
        $dados = if ($env:TAMANDUA_DADOS) { $env:TAMANDUA_DADOS } else { Join-Path ([Environment]::GetFolderPath('LocalApplicationData')) 'Tamandua' }
        $script:ArquivoPreferencias = Join-Path $dados 'config\interface.json'
        $script:Preferencias = Read-TmdPreferencias -Arquivo $script:ArquivoPreferencias
    }
    if (-not $Tema) { $Tema = if ($script:Preferencias.Tema) { $script:Preferencias.Tema } else { Get-TmdTemaWindows } }
    Set-TmdIdentidadeApp
    $tela = New-TmdJanela -Raiz $Raiz -Tema $Tema
    $tela.Janela.Add_ContentRendered({ Set-TmdIconeJanela -Tela $script:Tela; Hide-TmdConsole })
    Set-TmdTema -Tela $tela -Tema $Tema
    Set-TmdTamanhoJanela -Janela $tela.Janela
    Initialize-TmdTela -Tela $tela -Raiz $Raiz -AoCarregar $AoCarregar
    foreach ($v in $script:Preferencias.Visao.Keys) { $script:Estado.Visao[$v] = $script:Preferencias.Visao[$v] }
    $script:Estado.PaginaInicial = $script:Preferencias.UltimaPagina
    if ($FecharAposSeg -gt 0) {
        $script:RelogioFechar = New-Object System.Windows.Threading.DispatcherTimer
        $script:RelogioFechar.Interval = [TimeSpan]::FromSeconds($FecharAposSeg)
        $script:RelogioFechar.Add_Tick({ $script:RelogioFechar.Stop(); $script:Tela.Janela.Close() })
        $script:RelogioFechar.Start()
        # Desliga junto com a janela: senão ele dispara depois e fecha a PRÓXIMA janela aberta neste processo.
        $tela.Janela.Add_Closed({ if ($script:RelogioFechar) { $script:RelogioFechar.Stop() } })
    }
    [void]$tela.Janela.ShowDialog()
}

Export-ModuleMember -Function Start-TmdInterface
