# Trabalho fora da thread da janela. Cada tarefa roda num runspace próprio; um relógio da janela
# chama Update-TmdTarefa, que entrega o resultado na thread da janela. Assim nada de WPF é tocado de outra thread.

$script:Tarefas = [System.Collections.Generic.List[object]]::new()

function Start-TmdTarefa {
    param(
        [Parameter(Mandatory)][scriptblock]$Script,
        [hashtable]$Parametros = @{},
        [Parameter(Mandatory)][scriptblock]$AoTerminar
    )

    $ps = [powershell]::Create()
    # Passa o texto, não o scriptblock: um scriptblock fica preso ao runspace onde foi criado.
    [void]$ps.AddScript($Script.ToString())
    foreach ($k in $Parametros.Keys) { [void]$ps.AddParameter($k, $Parametros[$k]) }
    $tarefa = [pscustomobject]@{ PS = $ps; Async = $ps.BeginInvoke(); AoTerminar = $AoTerminar; Cancelada = $false }
    $script:Tarefas.Add($tarefa)
    $tarefa
}

function Stop-TmdTarefa {
    param([Parameter(Mandatory)]$Tarefa)
    if ($Tarefa.Cancelada) { return }
    $Tarefa.Cancelada = $true
    [void]$Tarefa.PS.BeginStop($null, $null)
}

# Entrega as tarefas concluídas: chama AoTerminar(saida, erro, avisos). Tarefa cancelada é descartada.
function Update-TmdTarefa {
    foreach ($t in @($script:Tarefas)) {
        if (-not $t.Async.IsCompleted) { continue }
        [void]$script:Tarefas.Remove($t)
        $saida = $null
        $erro = $null
        $avisos = @()
        try {
            $saida = @($t.PS.EndInvoke($t.Async))
            $avisos = @($t.PS.Streams.Warning | ForEach-Object { $_.Message })
        }
        catch {
            $ex = $_.Exception
            while ($ex.InnerException) { $ex = $ex.InnerException }
            $erro = $ex.Message
        }
        finally {
            $t.PS.Dispose()
        }
        if (-not $t.Cancelada) { & $t.AoTerminar $saida $erro $avisos }
    }
}

function Stop-TmdTodasTarefas {
    foreach ($t in @($script:Tarefas)) { Stop-TmdTarefa -Tarefa $t }
}

# Scripts que rodam nos runspaces de tarefa. Importam o núcleo do zero e devolvem só dados (sem scriptblocks).
$script:ScriptCarregarModulos = {
    param([string]$Nucleo, [string]$Raiz)
    $ErrorActionPreference = 'Stop'
    Import-Module -Name $Nucleo -Force -DisableNameChecking -Global
    foreach ($m in Get-TmdModulo -Raiz $Raiz) {
        [pscustomobject]@{
            Nome      = $m.Nome
            Titulo    = $m.Titulo
            Grupo     = $m.Grupo
            Descricao = $m.Descricao
            Estado    = $m.Estado
            Motivo    = $m.Motivo
            Escreve   = [bool]($m.Manifesto -and $m.Manifesto['Escreve'])
        }
    }
}

$script:ScriptBuscarAlvos = {
    param([string]$Nucleo, [string]$Raiz, [string]$Nome)
    $ErrorActionPreference = 'Stop'
    Import-Module -Name $Nucleo -Force -DisableNameChecking -Global
    $m = Get-TmdModulo -Raiz $Raiz -Nome $Nome
    if (-not $m -or $m.Estado -ne 'ok') { throw "o módulo $Nome não está disponível" }
    & $m.Modulo.ExportedFunctions['Find-Alvos']
}
