# Trabalho fora da thread da janela. Cada tarefa roda num runspace próprio; um relógio da janela
# chama Update-TmdTarefa, que entrega o resultado na thread da janela. Assim nada de WPF é tocado de outra thread.

$script:Tarefas = [System.Collections.Generic.List[object]]::new()
$script:Conjunto = $null
$script:AberturaConjunto = $null
$script:Aquecimento = $null

# Runspaces reaproveitados entre tarefas: o núcleo e os módulos carregados numa tarefa continuam lá para a próxima,
# em vez de cada página abrir um runspace novo e importar tudo de novo. Até 4 tarefas ao mesmo tempo.
# -Nucleo: cada runspace já nasce com o núcleo importado, e os 2 primeiros são abertos em segundo plano
# enquanto a janela aparece (a janela chama isso logo ao iniciar).
function Initialize-TmdConjunto {
    param([string]$Nucleo)
    Close-TmdConjunto
    $sessao = [initialsessionstate]::CreateDefault()
    if ($Nucleo) { $sessao.ImportPSModule($Nucleo) }
    $script:Conjunto = [runspacefactory]::CreateRunspacePool($sessao)
    [void]$script:Conjunto.SetMaxRunspaces(4)
    [void]$script:Conjunto.SetMinRunspaces(2)
    $script:Conjunto.ThreadOptions = 'ReuseThread'
    $script:AberturaConjunto = $script:Conjunto.BeginOpen($null, $null)
    # Compila os tipos C# do núcleo enquanto a janela é desenhada (a primeira página, o Status, precisa deles).
    if ($Nucleo) {
        $aquecer = [powershell]::Create()
        [void]$aquecer.AddScript({ param($n) Import-Module -Name $n -DisableNameChecking; Initialize-TmdTipos; Remove-Module Tamandua.Nucleo }.ToString()).AddArgument($Nucleo)
        $script:Aquecimento = @{ PS = $aquecer; Async = $aquecer.BeginInvoke() }
    }
}

function Get-TmdConjunto {
    $estado = if ($script:Conjunto) { $script:Conjunto.RunspacePoolStateInfo.State } else { 'Closed' }
    if ($estado -notin 'Opened', 'Opening', 'BeforeOpen') { Initialize-TmdConjunto }
    # Ainda abrindo: a primeira tarefa espera terminar (normalmente já terminou quando a janela aparece).
    if ($script:Conjunto.RunspacePoolStateInfo.State -ne 'Opened') { $script:Conjunto.EndOpen($script:AberturaConjunto) }
    $script:Conjunto
}

function Close-TmdConjunto {
    if ($script:Aquecimento -and $script:Aquecimento.Async.IsCompleted) { $script:Aquecimento.PS.Dispose(); $script:Aquecimento = $null }
    if (-not $script:Conjunto) { return }
    [void]$script:Conjunto.BeginClose($null, $null)
    $script:Conjunto = $null
}

function Start-TmdTarefa {
    param(
        [Parameter(Mandatory)][scriptblock]$Script,
        [hashtable]$Parametros = @{},
        # Chamado com (saida, erro, avisos, contexto). Não use GetNewClosure: o bloco perderia acesso ao estado deste módulo.
        [Parameter(Mandatory)][scriptblock]$AoTerminar,
        # Dados que o AoTerminar precisa (ex.: qual página pediu), devolvidos como 4º argumento.
        $Contexto = $null,
        # Chamado com (registro de Write-Progress, contexto) a cada novo progresso, enquanto a tarefa roda.
        [scriptblock]$AoProgresso
    )

    $ps = [powershell]::Create()
    $ps.RunspacePool = Get-TmdConjunto
    # Passa o texto, não o scriptblock: um scriptblock fica preso ao runspace onde foi criado.
    [void]$ps.AddScript($Script.ToString())
    foreach ($k in $Parametros.Keys) { [void]$ps.AddParameter($k, $Parametros[$k]) }
    $tarefa = [pscustomobject]@{
        PS = $ps; Async = $ps.BeginInvoke(); AoTerminar = $AoTerminar; Contexto = $Contexto; Cancelada = $false
        AoProgresso = $AoProgresso; ProgressosVistos = 0; UltimoProgresso = $null
    }
    $script:Tarefas.Add($tarefa)
    $tarefa
}

# Último progresso ainda em andamento (ignora o "Completed"), ou $null se não chegou nada novo.
function Get-TmdNovoProgresso {
    param([Parameter(Mandatory)]$Tarefa)
    $registros = $Tarefa.PS.Streams.Progress
    $total = $registros.Count
    if ($total -le $Tarefa.ProgressosVistos) { return $null }
    $Tarefa.ProgressosVistos = $total
    for ($i = $total - 1; $i -ge 0; $i--) {
        $r = $registros[$i]
        if ($r.RecordType -ne 'Completed') { return $r }
    }
    $null
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
        if (-not $t.Async.IsCompleted) {
            # Chama a cada volta (não só quando muda), para o tempo decorrido andar mesmo num item demorado.
            if ($t.AoProgresso -and -not $t.Cancelada) {
                $p = Get-TmdNovoProgresso -Tarefa $t
                if ($p) { $t.UltimoProgresso = $p }
                if ($t.UltimoProgresso) { & $t.AoProgresso $t.UltimoProgresso $t.Contexto }
            }
            continue
        }
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

# Scripts que rodam nos runspaces de tarefa. Importam o núcleo só na primeira vez em cada runspace do conjunto
# (depois ele já está lá) e devolvem só dados (sem scriptblocks).
$script:ScriptCarregarModulos = {
    param([string]$Nucleo, [string]$Raiz)
    $ErrorActionPreference = 'Stop'
    if (-not (Get-Module Tamandua.Nucleo | Where-Object Path -eq $Nucleo)) { Import-Module -Name $Nucleo -Force -DisableNameChecking -Global }
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
            Visualizacao = if ($m.Manifesto -and $m.Manifesto['Visualizacao'] -eq 'Grade') { 'Grade' } else { 'Lista' }
            Dica      = if ($m.Manifesto -and $m.Manifesto['Dica']) { [string]$m.Manifesto['Dica'] } else { '' }
            # Grupos de escolha única (ex.: uma fonte e um tamanho); este bloco roda num runspace, sem as funções da janela.
            Grupos    = @(if ($m.Manifesto) {
                    foreach ($g in @($m.Manifesto['Grupos'])) {
                        if ($g -is [hashtable] -and $g['Nome']) { [pscustomobject]@{ Nome = [string]$g['Nome']; Rotulo = [string]$g['Rotulo']; Vazio = [string]$g['Vazio'] } }
                    }
                })
            NomeItens = if ($m.Manifesto -and $m.Manifesto['NomeItens']) { [string]$m.Manifesto['NomeItens'] } else { 'programa|programas' }
        }
    }
}

# Grupos de escolha única do manifesto (ex.: uma fonte e um tamanho), em objetos simples para a janela.
function ConvertTo-TmdGruposManifesto {
    param($Grupos)
    foreach ($g in @($Grupos)) {
        if (-not ($g -is [hashtable]) -or -not $g['Nome']) { continue }
        [pscustomobject]@{ Nome = [string]$g['Nome']; Rotulo = [string]$g['Rotulo']; Vazio = [string]$g['Vazio'] }
    }
}

# Barra lateral provisória, para a janela não ficar vazia enquanto os módulos carregam de verdade (~0,8 s: importar
# cada um e conferir os requisitos). Só lê o catálogo e os manifestos (~0,15 s, na própria janela); todo módulo vem
# como "ok" até a lista de verdade chegar e trocar esta. Qualquer problema: lista vazia, e a janela espera como antes.
function Get-TmdModulosProvisorios {
    param([Parameter(Mandatory)][string]$Raiz)
    try {
        $catalogo = Import-PowerShellDataFile -LiteralPath (Join-Path $Raiz 'nucleo\catalogo.psd1') -ErrorAction Stop
        foreach ($c in @($catalogo['Modulos'])) {
            if (-not ($c -is [hashtable]) -or -not $c['Nome']) { continue }
            $nome = [string]$c['Nome']
            $man = @{}
            try { $man = Import-PowerShellDataFile -LiteralPath (Join-Path $Raiz "modulos\$nome\modulo.psd1") -ErrorAction Stop } catch { $man = @{} }
            [pscustomobject]@{
                Nome = $nome; Titulo = $(if ($c['Titulo']) { [string]$c['Titulo'] } else { $nome }); Grupo = [string]$c['Grupo']
                Descricao = [string]$c['Descricao']; Estado = 'ok'; Motivo = $null
                Escreve = [bool]$man['Escreve']
                RotuloAcao = if ($man['RotuloAcao']) { [string]$man['RotuloAcao'] } else { 'Aplicar' }
                Resultado = if ($man['Resultado'] -eq 'Mudancas') { 'ajustar' } else { 'liberar' }
                AvisoConfirmacao = if ($man['AvisoConfirmacao']) { [string]$man['AvisoConfirmacao'] } else { '' }
                Visualizacao = if ($man['Visualizacao'] -eq 'Grade') { 'Grade' } else { 'Lista' }
                Dica = [string]$man['Dica']
                Grupos = if ($man['Grupos']) { @(ConvertTo-TmdGruposManifesto $man['Grupos']) } else { @() }
                NomeItens = if ($man['NomeItens']) { [string]$man['NomeItens'] } else { 'programa|programas' }
                Provisorio = $true
            }
        }
    }
    catch { Write-Verbose "sem barra lateral provisória: $($_.Exception.Message)" }
}

# Lê a primeira página do catálogo ao mesmo tempo que a lista de módulos carrega (ao abrir o programa).
# Confere os requisitos só desse módulo; se ele não estiver ok, devolve sem alvos e a janela segue o caminho normal.
$script:ScriptPrimeiraPagina = {
    param([string]$Nucleo, [string]$Raiz)
    $ErrorActionPreference = 'Stop'
    if (-not (Get-Module Tamandua.Nucleo | Where-Object Path -eq $Nucleo)) { Import-Module -Name $Nucleo -Force -DisableNameChecking -Global }
    $primeiro = @((Get-TmdCatalogo -Raiz $Raiz).Modulos)[0]
    if (-not $primeiro) { return }
    $m = Get-TmdModulo -Raiz $Raiz -Nome $primeiro['Nome']
    $ok = $m -and $m.Estado -eq 'ok'
    [pscustomobject]@{ Nome = [string]$primeiro['Nome']; Ok = [bool]$ok; Alvos = @(if ($ok) { Get-TmdAlvosParaTela -Info $m }) }
}

$script:ScriptHistorico = {
    param([string]$Nucleo)
    $ErrorActionPreference = 'Stop'
    if (-not (Get-Module Tamandua.Nucleo | Where-Object Path -eq $Nucleo)) { Import-Module -Name $Nucleo -Force -DisableNameChecking -Global }
    Get-TmdHistorico -Ultimos 300
}

$script:ScriptDesfazer = {
    param([string]$Nucleo, [string]$Raiz, [string[]]$Ids, [bool]$Simular)
    $ErrorActionPreference = 'Stop'
    if (-not (Get-Module Tamandua.Nucleo | Where-Object Path -eq $Nucleo)) { Import-Module -Name $Nucleo -Force -DisableNameChecking -Global }
    if ($Simular) { foreach ($id in $Ids) { Undo-TmdAjuste -Id $id -Simular -Modulo 'historico' } }
    # Ajuste que mexeu em HKLM, serviço ou tarefa precisa de admin para voltar: o núcleo pede o UAC uma vez.
    else { Undo-TmdAjusteComAdmin -Ids $Ids -Raiz $Raiz }
}

$script:ScriptExecutarAcao = {
    param([string]$Nucleo, [string]$Raiz, [string]$Nome, [object[]]$Alvos, [bool]$Simular)
    $ErrorActionPreference = 'Stop'
    if (-not (Get-Module Tamandua.Nucleo | Where-Object Path -eq $Nucleo)) { Import-Module -Name $Nucleo -Force -DisableNameChecking -Global }
    $m = Get-TmdModulo -Raiz $Raiz -Nome $Nome
    if (-not $m -or $m.Estado -ne 'ok') { throw "o módulo $Nome não está disponível" }
    # Pelo núcleo: módulo com RequerAdmin roda elevado (um pedido do UAC por lote).
    Invoke-TmdAcaoModulo -Info $m -Alvos $Alvos -Simular:$Simular -Raiz $Raiz
}

$script:ScriptBuscarAlvos = {
    param([string]$Nucleo, [string]$Raiz, [string]$Nome)
    $ErrorActionPreference = 'Stop'
    if (-not (Get-Module Tamandua.Nucleo | Where-Object Path -eq $Nucleo)) { Import-Module -Name $Nucleo -Force -DisableNameChecking -Global }
    # A janela já conferiu os requisitos ao carregar a lista de módulos.
    $m = Get-TmdModulo -Raiz $Raiz -Nome $Nome -SemRequisitos
    if (-not $m -or $m.Estado -ne 'ok') { throw "o módulo $Nome não está disponível" }
    Get-TmdAlvosParaTela -Info $m
}
