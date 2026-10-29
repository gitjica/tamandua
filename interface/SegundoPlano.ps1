# Trabalho fora da thread da janela. Cada tarefa roda num runspace próprio; um relógio da janela
# chama Update-TmdTarefa, que entrega o resultado na thread da janela. Assim nada de WPF é tocado de outra thread.

$script:Tarefas = [System.Collections.Generic.List[object]]::new()

function Start-TmdTarefa {
    param(
        [Parameter(Mandatory)][scriptblock]$Script,
        [hashtable]$Parametros = @{},
        # Chamado com (saida, erro, avisos, contexto). Não use GetNewClosure: o bloco perderia acesso ao estado deste módulo.
        [Parameter(Mandatory)][scriptblock]$AoTerminar,
        # Dados que o AoTerminar precisa (ex.: qual página pediu), devolvidos como 4º argumento.
        $Contexto = $null
    )

    $ps = [powershell]::Create()
    # Passa o texto, não o scriptblock: um scriptblock fica preso ao runspace onde foi criado.
    [void]$ps.AddScript($Script.ToString())
    foreach ($k in $Parametros.Keys) { [void]$ps.AddParameter($k, $Parametros[$k]) }
    $tarefa = [pscustomobject]@{ PS = $ps; Async = $ps.BeginInvoke(); AoTerminar = $AoTerminar; Contexto = $Contexto; Cancelada = $false }
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
        if (-not $t.Cancelada) { & $t.AoTerminar $saida $erro $avisos $t.Contexto }
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
            RotuloAcao = if ($m.Manifesto -and $m.Manifesto['RotuloAcao']) { [string]$m.Manifesto['RotuloAcao'] } else { 'Aplicar' }
            Resultado = if ($m.Manifesto -and $m.Manifesto['Resultado'] -eq 'Mudancas') { 'ajustar' } else { 'liberar' }
            AvisoConfirmacao = if ($m.Manifesto -and $m.Manifesto['AvisoConfirmacao']) { [string]$m.Manifesto['AvisoConfirmacao'] } else { '' }
        }
    }
}

$script:ScriptHistorico = {
    param([string]$Nucleo)
    $ErrorActionPreference = 'Stop'
    Import-Module -Name $Nucleo -Force -DisableNameChecking -Global
    Get-TmdHistorico -Ultimos 300
}

$script:ScriptDesfazer = {
    param([string]$Nucleo, [string]$Raiz, [string[]]$Ids, [bool]$Simular)
    $ErrorActionPreference = 'Stop'
    Import-Module -Name $Nucleo -Force -DisableNameChecking -Global
    if ($Simular) { foreach ($id in $Ids) { Undo-TmdAjuste -Id $id -Simular -Modulo 'historico' } }
    # Ajuste que mexeu em HKLM, serviço ou tarefa precisa de admin para voltar: o núcleo pede o UAC uma vez.
    else { Undo-TmdAjusteComAdmin -Ids $Ids -Raiz $Raiz }
}

$script:ScriptExecutarAcao = {
    param([string]$Nucleo, [string]$Raiz, [string]$Nome, [object[]]$Alvos, [bool]$Simular)
    $ErrorActionPreference = 'Stop'
    Import-Module -Name $Nucleo -Force -DisableNameChecking -Global
    $m = Get-TmdModulo -Raiz $Raiz -Nome $Nome
    if (-not $m -or $m.Estado -ne 'ok') { throw "o módulo $Nome não está disponível" }
    # Pelo núcleo: módulo com RequerAdmin roda elevado (um pedido do UAC por lote).
    Invoke-TmdAcaoModulo -Info $m -Alvos $Alvos -Simular:$Simular -Raiz $Raiz
}

$script:ScriptBuscarAlvos = {
    param([string]$Nucleo, [string]$Raiz, [string]$Nome, [string]$Caminho)
    $ErrorActionPreference = 'Stop'
    Import-Module -Name $Nucleo -Force -DisableNameChecking -Global
    $m = Get-TmdModulo -Raiz $Raiz -Nome $Nome
    if (-not $m -or $m.Estado -ne 'ok') { throw "o módulo $Nome não está disponível" }
    $buscar = $m.Modulo.ExportedFunctions['Find-Alvos']
    # Módulos que navegam (ex.: analisar) recebem a pasta aberta.
    if ($Caminho -and $buscar.Parameters.ContainsKey('Caminho')) { & $buscar -Caminho $Caminho } else { & $buscar }
}
