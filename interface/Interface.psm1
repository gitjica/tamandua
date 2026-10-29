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
        [int]$FecharAposSeg = 0
    )

    if ([Threading.Thread]::CurrentThread.GetApartmentState() -ne 'STA') {
        throw 'a interface precisa de um processo STA (rode com powershell.exe)'
    }
    if (-not $Tema) { $Tema = Get-TmdTemaWindows }
    $tela = New-TmdJanela -Raiz $Raiz -Tema $Tema
    Set-TmdTema -Tela $tela -Tema $Tema
    Initialize-TmdTela -Tela $tela -Raiz $Raiz -AoCarregar $AoCarregar
    if ($FecharAposSeg -gt 0) {
        $script:RelogioFechar = New-Object System.Windows.Threading.DispatcherTimer
        $script:RelogioFechar.Interval = [TimeSpan]::FromSeconds($FecharAposSeg)
        $script:RelogioFechar.Add_Tick({ $script:RelogioFechar.Stop(); $script:Tela.Janela.Close() })
        $script:RelogioFechar.Start()
    }
    [void]$tela.Janela.ShowDialog()
}

Export-ModuleMember -Function Start-TmdInterface
