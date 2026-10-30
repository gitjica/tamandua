# ÚNICO lugar do Tamanduá que escreve registro, serviços, tarefas agendadas e scripts de sistema (seção 7.3 do guia).
# Cada mudança: ler -> salvar snapshot -> reg export -> escrever -> conferir. Falhou no meio: volta tudo que este ajuste mudou.

$script:TiposMudanca = 'Registro', 'Servico', 'Tarefa', 'Script'
$script:TiposValor = 'DWord', 'QWord', 'String', 'ExpandString', 'Binary', 'MultiString'
$script:Inicializacoes = 'Automatic', 'AutomaticDelayedStart', 'Manual', 'Disabled'

function Set-TmdAjuste {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Ajuste,
        [switch]$Simular,
        # Testes: HKCU:\ e HKLM:\ passam a apontar para dentro desta chave (que precisa estar em HKCU:\).
        [string]$RaizRegistro = '',
        [string]$Modulo = 'ajustes'
    )
    $id = [string](Get-Propriedade $Ajuste 'id')
    try { $resultado = Invoke-TmdAplicarAjuste -Ajuste $Ajuste -Simular $Simular -RaizRegistro $RaizRegistro }
    catch { $resultado = New-TmdResultadoAjuste -Id $id -Status 'Erro' -Motivo (Get-TmdExcecaoInterna $_.Exception).Message }
    Write-TmdOperacao -Modulo $Modulo -Id $id -Acao 'ajustar' -Caminho ([string](Get-Propriedade $Ajuste 'nome')) `
        -Status $resultado.Status -Motivo $resultado.Motivo -Simulado $Simular
    $resultado
}

function Invoke-TmdAplicarAjuste {
    param($Ajuste, [bool]$Simular, [string]$RaizRegistro)

    $id = [string](Get-Propriedade $Ajuste 'id')
    $mudancas = @(Get-TmdMudancaAjuste -Ajuste $Ajuste)
    # Área de testes: só registro, que vai todo para a chave de teste (serviço e script mexeriam no sistema de verdade).
    if ($RaizRegistro -and @($mudancas | Where-Object { $_.Tipo -in 'Servico', 'Tarefa' }).Count -gt 0) {
        throw "ajuste $id mexe em serviço ou tarefa: não roda na área de testes"
    }
    # Simular só lê (ler HKLM não precisa de admin); só escrever exige.
    if (-not $Simular -and (Get-Propriedade $Ajuste 'requerAdmin') -eq $true -and -not (Test-TmdAdministrador)) {
        return New-TmdResultadoAjuste -Id $id -Status 'Ignorado' -Motivo 'precisa de permissão de administrador'
    }

    # Só o que ainda não está como o ajuste quer. O que já está não entra no snapshot: não foi o Tamanduá que mudou.
    $pendentes = @(foreach ($m in $mudancas) {
            $atual = Read-TmdMudanca -Mudanca $m -RaizRegistro $RaizRegistro
            if (-not (Test-TmdMudancaNoAlvo -Mudanca $m -Estado $atual)) { [pscustomobject]@{ Mudanca = $m; Antes = $atual } }
        })
    $descricoes = @($pendentes | ForEach-Object { Format-TmdMudanca -Mudanca $_.Mudanca -Antes $_.Antes })
    if ($pendentes.Count -eq 0) { return New-TmdResultadoAjuste -Id $id -Status 'Feito' -Motivo 'já estava aplicado' }
    if ($Simular) { return New-TmdResultadoAjuste -Id $id -Status 'Simulado' -Mudancas $descricoes }

    # Snapshot primeiro. Se não der para salvar, nada é escrito (a exceção sobe).
    $snapshotOriginal = Read-TmdSnapshot -Id $id
    $entradas = [System.Collections.Generic.List[object]]::new()
    foreach ($e in $snapshotOriginal) { $entradas.Add($e) }
    $chaves = @($snapshotOriginal | ForEach-Object { $_.Chave })
    foreach ($p in $pendentes) {
        $entrada = New-TmdEntradaSnapshot -Mudanca $p.Mudanca -Antes $p.Antes -RaizRegistro $RaizRegistro -RequerAdmin ((Get-Propriedade $Ajuste 'requerAdmin') -eq $true)
        if ($chaves -notcontains $entrada.Chave) { $entradas.Add($entrada) }
    }
    Save-TmdSnapshot -Id $id -Entradas $entradas.ToArray()

    $feitas = [System.Collections.Generic.List[object]]::new()
    foreach ($p in $pendentes) {
        try {
            Backup-TmdRegistro -Mudanca $p.Mudanca -RaizRegistro $RaizRegistro -Id $id
            Write-TmdMudanca -Mudanca $p.Mudanca -RaizRegistro $RaizRegistro
            $depois = Read-TmdMudanca -Mudanca $p.Mudanca -RaizRegistro $RaizRegistro
            if (-not (Test-TmdMudancaNoAlvo -Mudanca $p.Mudanca -Estado $depois)) { throw "a conferência depois de escrever falhou ($(Format-TmdMudanca -Mudanca $p.Mudanca -Antes $p.Antes))" }
            $feitas.Add($p)
        }
        catch {
            $motivo = (Get-TmdExcecaoInterna $_.Exception).Message
            # Volta a que falhou e as que já tinham sido feitas, da última para a primeira.
            $voltar = @($p)
            for ($k = $feitas.Count - 1; $k -ge 0; $k--) { $voltar += $feitas[$k] }
            foreach ($v in $voltar) {
                try { Restore-TmdMudanca -Mudanca $v.Mudanca -Antes $v.Antes -RaizRegistro $RaizRegistro }
                catch { $motivo += "; não foi possível voltar $(Get-TmdChaveMudanca $v.Mudanca): $((Get-TmdExcecaoInterna $_.Exception).Message)" }
            }
            if ($snapshotOriginal.Count -gt 0) { Save-TmdSnapshot -Id $id -Entradas $snapshotOriginal } else { Remove-TmdSnapshot -Id $id }
            return New-TmdResultadoAjuste -Id $id -Status 'Erro' -Motivo "$motivo (nada ficou alterado)" -Mudancas $descricoes
        }
    }
    New-TmdResultadoAjuste -Id $id -Status 'Feito' -Mudancas $descricoes
}

# Desfaz pelo snapshot (valor que estava antes). Sem snapshot, usa o padrão do Windows do -Ajuste, avisando.
function Undo-TmdAjuste {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Id,
        $Ajuste,
        [switch]$Simular,
        [string]$RaizRegistro = '',
        [string]$Modulo = 'ajustes'
    )
    $nome = if ($Ajuste) { [string](Get-Propriedade $Ajuste 'nome') } else { $Id }
    try { $resultado = Invoke-TmdDesfazerAjuste -Id $Id -Ajuste $Ajuste -Simular $Simular -RaizRegistro $RaizRegistro }
    catch { $resultado = New-TmdResultadoAjuste -Id $Id -Status 'Erro' -Motivo (Get-TmdExcecaoInterna $_.Exception).Message }
    Write-TmdOperacao -Modulo $Modulo -Id $Id -Acao 'desfazer' -Caminho $nome -Status $resultado.Status -Motivo $resultado.Motivo -Simulado $Simular
    $resultado
}

function Invoke-TmdDesfazerAjuste {
    param([string]$Id, $Ajuste, [bool]$Simular, [string]$RaizRegistro)

    $entradas = Read-TmdSnapshot -Id $Id
    if ($entradas.Count -eq 0) {
        if (-not $Ajuste) { return New-TmdResultadoAjuste -Id $Id -Status 'Erro' -Motivo 'não há o que desfazer: nenhum estado salvo para este ajuste' }
        return Invoke-TmdRestaurarPadrao -Ajuste $Ajuste -Simular $Simular -RaizRegistro $RaizRegistro
    }
    $itens = @($entradas | ForEach-Object { ConvertFrom-TmdEntradaSnapshot -Entrada $_ })
    # Onde desfazer: o lugar salvo no snapshot; snapshots antigos, sem isso, usam o -RaizRegistro recebido.
    foreach ($it in $itens) { if (-not $it.Raiz) { $it.Raiz = $RaizRegistro } }
    $precisaAdmin = @($entradas | Where-Object { Test-TmdEntradaPrecisaAdmin $_ }).Count -gt 0
    $descricoes = @($itens | ForEach-Object { "volta $(Get-TmdChaveMudanca $_.Mudanca) para $(Format-TmdEstado -Mudanca $_.Mudanca -Estado $_.Antes)" })
    if ($Simular) { return New-TmdResultadoAjuste -Id $Id -Status 'Simulado' -Mudancas $descricoes }
    if ($precisaAdmin -and -not (Test-TmdAdministrador)) {
        return New-TmdResultadoAjuste -Id $Id -Status 'Ignorado' -Motivo 'precisa de permissão de administrador'
    }

    $falhas = [System.Collections.Generic.List[object]]::new()
    $motivos = @()
    for ($i = $itens.Count - 1; $i -ge 0; $i--) {
        $it = $itens[$i]
        try {
            Restore-TmdMudanca -Mudanca $it.Mudanca -Antes $it.Antes -RaizRegistro $it.Raiz
            if ($it.Mudanca.Tipo -ne 'Script') {
                $agora = Read-TmdMudanca -Mudanca $it.Mudanca -RaizRegistro $it.Raiz
                if (-not (Test-TmdEstadoIgual -Mudanca $it.Mudanca -A $agora -B $it.Antes)) { throw 'a conferência depois de voltar falhou' }
            }
        }
        catch {
            $falhas.Add($entradas[$i])
            $motivos += "$(Get-TmdChaveMudanca $it.Mudanca): $((Get-TmdExcecaoInterna $_.Exception).Message)"
        }
    }
    if ($falhas.Count -eq 0) {
        Remove-TmdSnapshot -Id $Id
        return New-TmdResultadoAjuste -Id $Id -Status 'Feito' -Mudancas $descricoes
    }
    # Guarda só o que não voltou, para tentar de novo depois.
    Save-TmdSnapshot -Id $Id -Entradas $falhas.ToArray()
    $status = if ($falhas.Count -lt $itens.Count) { 'Parcial' } else { 'Erro' }
    New-TmdResultadoAjuste -Id $Id -Status $status -Motivo ($motivos -join '; ') -Mudancas $descricoes
}

function Invoke-TmdRestaurarPadrao {
    param($Ajuste, [bool]$Simular, [string]$RaizRegistro)

    $id = [string](Get-Propriedade $Ajuste 'id')
    $aviso = 'restaurado o padrão do Windows (o valor anterior não estava salvo)'
    if ((Get-Propriedade $Ajuste 'requerAdmin') -eq $true -and -not (Test-TmdAdministrador)) {
        return New-TmdResultadoAjuste -Id $id -Status 'Ignorado' -Motivo 'precisa de permissão de administrador'
    }
    $mudancas = @(Get-TmdMudancaAjuste -Ajuste $Ajuste)
    $padroes = @(foreach ($m in $mudancas) { [pscustomobject]@{ Mudanca = $m; Antes = Get-TmdEstadoPadrao -Mudanca $m } })
    $descricoes = @($padroes | ForEach-Object { "volta $(Get-TmdChaveMudanca $_.Mudanca) para $(Format-TmdEstado -Mudanca $_.Mudanca -Estado $_.Antes)" })
    if ($Simular) { return New-TmdResultadoAjuste -Id $id -Status 'Simulado' -Motivo $aviso -Mudancas $descricoes }
    $motivos = @()
    foreach ($p in $padroes) {
        try { Restore-TmdMudanca -Mudanca $p.Mudanca -Antes $p.Antes -RaizRegistro $RaizRegistro }
        catch { $motivos += "$(Get-TmdChaveMudanca $p.Mudanca): $((Get-TmdExcecaoInterna $_.Exception).Message)" }
    }
    if ($motivos.Count -gt 0) { return New-TmdResultadoAjuste -Id $id -Status 'Erro' -Motivo ($motivos -join '; ') -Mudancas $descricoes }
    New-TmdResultadoAjuste -Id $id -Status 'Feito' -Motivo $aviso -Mudancas $descricoes
}

# Desfazer este ajuste precisa de admin? (registro em HKLM/HKU fora da área de testes, serviço, tarefa ou script de ajuste que pedia admin)
function Test-TmdDesfazerPrecisaAdmin {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Id)
    try { $entradas = Read-TmdSnapshot -Id $Id } catch { return $false }
    @($entradas | Where-Object { Test-TmdEntradaPrecisaAdmin $_ }).Count -gt 0
}

function Test-TmdRegistroDoSistema {
    param([string]$Caminho)
    $Caminho -like 'HKLM:*' -or $Caminho -like 'HKU:*'
}

function Test-TmdEntradaPrecisaAdmin {
    param($Entrada)
    switch ([string](Get-Propriedade $Entrada 'Tipo')) {
        'Registro' { return -not (Get-Propriedade $Entrada 'RaizRegistro') -and (Test-TmdRegistroDoSistema ([string](Get-Propriedade $Entrada 'Caminho'))) }
        'Script' { return (Get-Propriedade $Entrada 'RequerAdmin') -ne $false }
        default { return $true }
    }
}

# Ponto de restauração do Windows antes de mexer no sistema (o "Create Restore Point" do WinUtil). Liga a Proteção do
# Sistema no disco do Windows se estiver desligada e libera criar mesmo com outro ponto nas últimas 24 h (só durante a criação).
function New-TmdPontoRestauracao {
    [CmdletBinding()]
    param([string]$Id = 'seg-ponto-restauracao', [string]$Descricao = 'Tamanduá', [switch]$Simular, [string]$Modulo = 'ajustes')
    $resultado = if ($Simular) { New-TmdResultadoAjuste -Id $Id -Status 'Simulado' -Mudancas @("cria um ponto de restauração em $env:SystemDrive") }
    elseif (-not (Test-TmdAdministrador)) { New-TmdResultadoAjuste -Id $Id -Status 'Ignorado' -Motivo 'precisa de permissão de administrador' }
    else {
        try {
            Invoke-TmdCriarPontoRestauracao -Descricao $Descricao
            New-TmdResultadoAjuste -Id $Id -Status 'Feito' -Mudancas @("ponto de restauração criado em $env:SystemDrive")
        }
        catch { New-TmdResultadoAjuste -Id $Id -Status 'Erro' -Motivo (Get-TmdExcecaoInterna $_.Exception).Message }
    }
    Write-TmdOperacao -Modulo $Modulo -Id $Id -Acao 'criar' -Caminho 'Ponto de restauração' -Status $resultado.Status -Motivo $resultado.Motivo -Simulado ([bool]$Simular)
    $resultado
}

# Isolado para os testes trocarem por Mock.
function Invoke-TmdCriarPontoRestauracao {
    param([string]$Descricao)
    Enable-ComputerRestore -Drive "$env:SystemDrive\" -ErrorAction Stop
    $chave = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\SystemRestore'
    $nome = 'SystemRestorePointCreationFrequency'
    $antes = Read-TmdRegistro -Caminho $chave -Nome $nome
    Write-TmdRegistro -Caminho $chave -Nome $nome -Valor 0 -TipoValor 'DWord'
    try { Checkpoint-Computer -Description $Descricao -RestorePointType 'MODIFY_SETTINGS' -ErrorAction Stop }
    finally {
        if ($antes.Existe) { Write-TmdRegistro -Caminho $chave -Nome $nome -Valor $antes.Valor -TipoValor $antes.TipoValor }
        else { Remove-TmdValorRegistro -Caminho $chave -Nome $nome }
    }
}

# Aplicado | NaoAplicado | Parcial | Desconhecido, lido da máquina agora.
function Get-TmdEstadoAjuste {
    [CmdletBinding()]
    param([Parameter(Mandatory)]$Ajuste, [string]$RaizRegistro = '')
    try {
        $mudancas = @(Get-TmdMudancaAjuste -Ajuste $Ajuste)
        $noAlvo = 0
        foreach ($m in $mudancas) {
            if ($m.Tipo -eq 'Script' -and -not $m.Verificar) { return 'Desconhecido' }
            if (Test-TmdMudancaNoAlvo -Mudanca $m -Estado (Read-TmdMudanca -Mudanca $m -RaizRegistro $RaizRegistro)) { $noAlvo++ }
        }
        if ($noAlvo -eq $mudancas.Count) { return 'Aplicado' }
        if ($noAlvo -eq 0) { return 'NaoAplicado' }
        'Parcial'
    }
    catch { 'Desconhecido' }
}

function New-TmdResultadoAjuste {
    param([string]$Id, [string]$Status = 'Feito', [string]$Motivo = '', [string[]]$Mudancas = @())
    [pscustomobject]@{ Id = $Id; Status = $Status; Liberado = [int64]0; Motivo = $Motivo; Mudancas = $Mudancas }
}

# ---------- Definição das mudanças ----------

# Valida e normaliza as mudanças do ajuste. Ajuste mal definido lança: nada é aplicado.
function Get-TmdMudancaAjuste {
    param([Parameter(Mandatory)]$Ajuste)

    $id = [string](Get-Propriedade $Ajuste 'id')
    if (-not $id) { throw 'ajuste sem id' }
    $requerAdmin = (Get-Propriedade $Ajuste 'requerAdmin') -eq $true
    $lista = @(Get-Propriedade $Ajuste 'mudancas')
    if ($lista.Count -eq 0 -or $null -eq $lista[0]) { throw "ajuste $id sem mudanças" }
    $i = 0
    foreach ($d in $lista) {
        $i++
        $tipo = [string](Get-Propriedade $d 'tipo')
        if ($tipo -notin $script:TiposMudanca) { throw "ajuste $id, mudança $($i): tipo '$tipo' desconhecido" }
        $m = [pscustomobject]@{
            Indice = $i; Tipo = $tipo
            Caminho = [string](Get-Propriedade $d 'caminho'); Nome = [string](Get-Propriedade $d 'nome')
            Valor = Get-Propriedade $d 'valor'; TipoValor = [string](Get-Propriedade $d 'tipoValor')
            Padrao = Get-Propriedade $d 'padraoWindows'
            Inicializacao = [string](Get-Propriedade $d 'inicializacao'); Habilitada = Get-Propriedade $d 'habilitada'
            Aplicar = [string](Get-Propriedade $d 'aplicar'); Desfazer = [string](Get-Propriedade $d 'desfazer')
            Verificar = [string](Get-Propriedade $d 'verificar')
        }
        switch ($tipo) {
            'Registro' {
                if ($m.Caminho -notmatch '^(HKCU|HKLM|HKU):\\.+') { throw "ajuste $id, mudança $($i): caminho de registro precisa começar com HKCU:\, HKLM:\ ou HKU:\" }
                if ((Test-TmdRegistroDoSistema $m.Caminho) -and -not $requerAdmin) { throw "ajuste $id, mudança $($i): HKLM e HKU exigem requerAdmin" }
                if ($m.TipoValor -notin $script:TiposValor) { throw "ajuste $id, mudança $($i): tipoValor '$($m.TipoValor)' inválido" }
                if ($null -eq $m.Valor) { throw "ajuste $id, mudança $($i): falta o valor" }
            }
            'Servico' {
                if (-not $m.Nome -or $m.Inicializacao -notin $script:Inicializacoes) { throw "ajuste $id, mudança $($i): serviço precisa de nome e inicializacao válida" }
            }
            'Tarefa' {
                if (-not $m.Nome -or -not $m.Caminho -or -not ($m.Habilitada -is [bool])) { throw "ajuste $id, mudança $($i): tarefa precisa de caminho, nome e habilitada" }
            }
            'Script' {
                if (-not $m.Aplicar -or -not $m.Desfazer) { throw "ajuste $id, mudança $($i): script precisa de aplicar e desfazer" }
            }
        }
        $m
    }
}

function Get-TmdChaveMudanca {
    param([Parameter(Mandatory)]$Mudanca)
    switch ($Mudanca.Tipo) {
        'Registro' { return "$($Mudanca.Caminho)\$($Mudanca.Nome)" }
        'Servico' { return "serviço $($Mudanca.Nome)" }
        'Tarefa' { return "tarefa $($Mudanca.Caminho)$($Mudanca.Nome)" }
        default { return "script $($Mudanca.Indice)" }
    }
}

# ---------- Ler, escrever, comparar ----------

function Read-TmdMudanca {
    param([Parameter(Mandatory)]$Mudanca, [string]$RaizRegistro)
    switch ($Mudanca.Tipo) {
        'Registro' { return Read-TmdRegistro -Caminho $Mudanca.Caminho -Nome $Mudanca.Nome -RaizRegistro $RaizRegistro }
        'Servico' {
            $ini = Get-TmdServicoInicializacao -Nome $Mudanca.Nome
            return [pscustomobject]@{ Existe = $null -ne $ini; Inicializacao = $ini }
        }
        'Tarefa' {
            $hab = Get-TmdTarefaHabilitada -Caminho $Mudanca.Caminho -Nome $Mudanca.Nome
            return [pscustomobject]@{ Existe = $null -ne $hab; Habilitada = $hab }
        }
        'Script' {
            $aplicado = if ($Mudanca.Verificar) { [bool](& ([scriptblock]::Create($Mudanca.Verificar))) } else { $null }
            return [pscustomobject]@{ Existe = $true; Aplicado = $aplicado }
        }
    }
}

# A mudança já está como o ajuste quer? Serviço ou tarefa que não existe nesta máquina conta como "nada a fazer".
function Test-TmdMudancaNoAlvo {
    param([Parameter(Mandatory)]$Mudanca, [Parameter(Mandatory)]$Estado)
    switch ($Mudanca.Tipo) {
        'Registro' { return $Estado.Existe -and $Estado.TipoValor -eq $Mudanca.TipoValor -and (Test-TmdValorIgual -TipoValor $Mudanca.TipoValor -A $Estado.Valor -B $Mudanca.Valor) }
        'Servico' { return -not $Estado.Existe -or $Estado.Inicializacao -eq $Mudanca.Inicializacao }
        'Tarefa' { return -not $Estado.Existe -or $Estado.Habilitada -eq $Mudanca.Habilitada }
        'Script' { return $Estado.Aplicado -eq $true }
    }
}

function Test-TmdEstadoIgual {
    param($Mudanca, $A, $B)
    switch ($Mudanca.Tipo) {
        'Registro' {
            if ($A.Existe -ne $B.Existe) { return $false }
            if (-not $A.Existe) { return $true }
            return $A.TipoValor -eq $B.TipoValor -and (Test-TmdValorIgual -TipoValor $A.TipoValor -A $A.Valor -B $B.Valor)
        }
        'Servico' { return $A.Inicializacao -eq $B.Inicializacao }
        'Tarefa' { return $A.Habilitada -eq $B.Habilitada }
        default { return $true }
    }
}

function Write-TmdMudanca {
    param([Parameter(Mandatory)]$Mudanca, [string]$RaizRegistro)
    switch ($Mudanca.Tipo) {
        'Registro' { Write-TmdRegistro -Caminho $Mudanca.Caminho -Nome $Mudanca.Nome -Valor $Mudanca.Valor -TipoValor $Mudanca.TipoValor -RaizRegistro $RaizRegistro }
        'Servico' { Set-TmdServicoInicializacao -Nome $Mudanca.Nome -Inicializacao $Mudanca.Inicializacao }
        'Tarefa' { Set-TmdTarefaHabilitada -Caminho $Mudanca.Caminho -Nome $Mudanca.Nome -Habilitada ([bool]$Mudanca.Habilitada) }
        'Script' { & ([scriptblock]::Create($Mudanca.Aplicar)) | Out-Null }
    }
}

# Põe de volta o estado $Antes (inclusive "não existia": apaga o valor).
function Restore-TmdMudanca {
    param([Parameter(Mandatory)]$Mudanca, [Parameter(Mandatory)]$Antes, [string]$RaizRegistro)
    switch ($Mudanca.Tipo) {
        'Registro' {
            if ($Antes.Existe) { Write-TmdRegistro -Caminho $Mudanca.Caminho -Nome $Mudanca.Nome -Valor $Antes.Valor -TipoValor $Antes.TipoValor -RaizRegistro $RaizRegistro }
            else { Remove-TmdValorRegistro -Caminho $Mudanca.Caminho -Nome $Mudanca.Nome -RaizRegistro $RaizRegistro }
        }
        'Servico' { if ($Antes.Existe) { Set-TmdServicoInicializacao -Nome $Mudanca.Nome -Inicializacao $Antes.Inicializacao } }
        'Tarefa' { if ($Antes.Existe) { Set-TmdTarefaHabilitada -Caminho $Mudanca.Caminho -Nome $Mudanca.Nome -Habilitada ([bool]$Antes.Habilitada) } }
        'Script' { & ([scriptblock]::Create($Mudanca.Desfazer)) | Out-Null }
    }
}

function Get-TmdEstadoPadrao {
    param([Parameter(Mandatory)]$Mudanca)
    switch ($Mudanca.Tipo) {
        'Registro' {
            if ($null -eq $Mudanca.Padrao) { return [pscustomobject]@{ Existe = $false; Valor = $null; TipoValor = $Mudanca.TipoValor } }
            return [pscustomobject]@{ Existe = $true; Valor = $Mudanca.Padrao; TipoValor = $Mudanca.TipoValor }
        }
        'Servico' { return [pscustomobject]@{ Existe = $null -ne $Mudanca.Padrao; Inicializacao = [string]$Mudanca.Padrao } }
        'Tarefa' { return [pscustomobject]@{ Existe = $null -ne $Mudanca.Padrao; Habilitada = $Mudanca.Padrao -eq $true } }
        default { return [pscustomobject]@{ Existe = $true } }
    }
}

# Guarda também onde a mudança foi feita (RaizRegistro): desfazer volta no mesmo lugar, mesmo que quem desfaz não saiba.
function New-TmdEntradaSnapshot {
    param([Parameter(Mandatory)]$Mudanca, [Parameter(Mandatory)]$Antes, [string]$RaizRegistro = '', [bool]$RequerAdmin = $true)
    [pscustomobject]@{
        Chave = Get-TmdChaveMudanca $Mudanca; Tipo = $Mudanca.Tipo; Indice = $Mudanca.Indice; RaizRegistro = $RaizRegistro; RequerAdmin = $RequerAdmin
        Caminho = $Mudanca.Caminho; Nome = $Mudanca.Nome; Desfazer = $Mudanca.Desfazer
        Existia = [bool]$Antes.Existe
        Valor = if ($Mudanca.Tipo -eq 'Registro') { $Antes.Valor } else { $null }
        TipoValor = if ($Mudanca.Tipo -eq 'Registro') { $Antes.TipoValor } else { $null }
        Inicializacao = if ($Mudanca.Tipo -eq 'Servico') { $Antes.Inicializacao } else { $null }
        Habilitada = if ($Mudanca.Tipo -eq 'Tarefa') { $Antes.Habilitada } else { $null }
    }
}

function ConvertFrom-TmdEntradaSnapshot {
    param([Parameter(Mandatory)]$Entrada)
    $m = [pscustomobject]@{
        Indice = $Entrada.Indice; Tipo = $Entrada.Tipo; Caminho = $Entrada.Caminho; Nome = $Entrada.Nome
        TipoValor = $Entrada.TipoValor; Desfazer = $Entrada.Desfazer
    }
    $antes = switch ($Entrada.Tipo) {
        'Registro' { [pscustomobject]@{ Existe = [bool]$Entrada.Existia; Valor = $Entrada.Valor; TipoValor = $Entrada.TipoValor } }
        'Servico' { [pscustomobject]@{ Existe = [bool]$Entrada.Existia; Inicializacao = $Entrada.Inicializacao } }
        'Tarefa' { [pscustomobject]@{ Existe = [bool]$Entrada.Existia; Habilitada = $Entrada.Habilitada } }
        default { [pscustomobject]@{ Existe = $true } }
    }
    [pscustomobject]@{ Mudanca = $m; Antes = $antes; Raiz = [string](Get-Propriedade $Entrada 'RaizRegistro') }
}

function Format-TmdEstado {
    param($Mudanca, $Estado)
    switch ($Mudanca.Tipo) {
        'Registro' { if (-not $Estado.Existe) { return 'não existe' }; return (Format-TmdValor $Estado.Valor) }
        'Servico' { if (-not $Estado.Existe) { return 'não existe' }; return $Estado.Inicializacao }
        'Tarefa' { if (-not $Estado.Existe) { return 'não existe' }; if ($Estado.Habilitada) { return 'ativada' }; return 'desativada' }
        default { return 'como estava' }
    }
}

function Format-TmdMudanca {
    param([Parameter(Mandatory)]$Mudanca, $Antes)
    switch ($Mudanca.Tipo) {
        'Registro' { return "$(Get-TmdChaveMudanca $Mudanca): $(Format-TmdEstado $Mudanca $Antes) → $(Format-TmdValor $Mudanca.Valor)" }
        'Servico' { return "$(Get-TmdChaveMudanca $Mudanca): $(Format-TmdEstado $Mudanca $Antes) → $($Mudanca.Inicializacao)" }
        'Tarefa' { return "$(Get-TmdChaveMudanca $Mudanca): $(Format-TmdEstado $Mudanca $Antes) → $(if ($Mudanca.Habilitada) { 'ativada' } else { 'desativada' })" }
        default { return "executa: $($Mudanca.Aplicar)" }
    }
}

function Format-TmdValor {
    param($Valor)
    if ($null -eq $Valor) { return '(vazio)' }
    if ($Valor -is [array]) { return ($Valor -join ', ') }
    [string]$Valor
}

# ---------- Registro (.NET, caminho literal, visão de 64 bits) ----------

function Split-TmdCaminhoRegistro {
    param([Parameter(Mandatory)][string]$Caminho, [string]$RaizRegistro)
    if ($Caminho -notmatch '^(HKCU|HKLM|HKU):\\(.+)$') { throw "caminho de registro inválido: $Caminho" }
    $hive = $Matches[1]
    $sub = $Matches[2].TrimEnd('\')
    if ($RaizRegistro) {
        # Redirecionamento só existe para testes: nunca aponta para fora da área de testes.
        if ($RaizRegistro -notmatch '^HKCU:\\(Software\\TamanduaTestes\\.+)$') { throw 'RaizRegistro precisa estar em HKCU:\Software\TamanduaTestes\' }
        $sub = "$($Matches[1].TrimEnd('\'))\$hive\$sub"
        $hive = 'HKCU'
    }
    [pscustomobject]@{ Hive = $hive; Sub = $sub; Texto = "$hive\$sub" }
}

function Open-TmdBaseRegistro {
    param([Parameter(Mandatory)][string]$Hive)
    $h = switch ($Hive) { 'HKLM' { [Microsoft.Win32.RegistryHive]::LocalMachine } 'HKU' { [Microsoft.Win32.RegistryHive]::Users } default { [Microsoft.Win32.RegistryHive]::CurrentUser } }
    $visao = if ([Environment]::Is64BitOperatingSystem) { [Microsoft.Win32.RegistryView]::Registry64 } else { [Microsoft.Win32.RegistryView]::Default }
    [Microsoft.Win32.RegistryKey]::OpenBaseKey($h, $visao)
}

function Read-TmdRegistro {
    param([Parameter(Mandatory)][string]$Caminho, [AllowEmptyString()][string]$Nome, [string]$RaizRegistro)
    $c = Split-TmdCaminhoRegistro -Caminho $Caminho -RaizRegistro $RaizRegistro
    $base = Open-TmdBaseRegistro $c.Hive
    try {
        $chave = $base.OpenSubKey($c.Sub, $false)
        if (-not $chave) { return [pscustomobject]@{ Existe = $false; Valor = $null; TipoValor = $null } }
        try {
            if (@($chave.GetValueNames()) -notcontains $Nome) { return [pscustomobject]@{ Existe = $false; Valor = $null; TipoValor = $null } }
            [pscustomobject]@{
                Existe    = $true
                Valor     = $chave.GetValue($Nome, $null, [Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames)
                TipoValor = $chave.GetValueKind($Nome).ToString()
            }
        }
        finally { $chave.Close() }
    }
    finally { $base.Close() }
}

function Write-TmdRegistro {
    param([Parameter(Mandatory)][string]$Caminho, [AllowEmptyString()][string]$Nome, $Valor, [Parameter(Mandatory)][string]$TipoValor, [string]$RaizRegistro)
    $c = Split-TmdCaminhoRegistro -Caminho $Caminho -RaizRegistro $RaizRegistro
    $base = Open-TmdBaseRegistro $c.Hive
    try {
        $chave = $base.CreateSubKey($c.Sub)
        if (-not $chave) { throw "não foi possível abrir $($c.Texto) para escrita" }
        try { $chave.SetValue($Nome, (ConvertTo-TmdValorRegistro -Valor $Valor -TipoValor $TipoValor), [Microsoft.Win32.RegistryValueKind]$TipoValor) }
        finally { $chave.Close() }
    }
    finally { $base.Close() }
}

function Remove-TmdValorRegistro {
    param([Parameter(Mandatory)][string]$Caminho, [AllowEmptyString()][string]$Nome, [string]$RaizRegistro)
    $c = Split-TmdCaminhoRegistro -Caminho $Caminho -RaizRegistro $RaizRegistro
    $base = Open-TmdBaseRegistro $c.Hive
    try {
        $chave = $base.OpenSubKey($c.Sub, $true)
        if (-not $chave) { return }
        try { $chave.DeleteValue($Nome, $false) } finally { $chave.Close() }
    }
    finally { $base.Close() }
}

# JSON traz números como Int32/Int64 e listas como Object[]; o registro quer o tipo exato.
function ConvertTo-TmdValorRegistro {
    param($Valor, [Parameter(Mandatory)][string]$TipoValor)
    switch ($TipoValor) {
        'DWord' {
            $u = [uint32]([int64]$Valor -band [int64]4294967295)
            return [BitConverter]::ToInt32([BitConverter]::GetBytes($u), 0)
        }
        'QWord' { return [int64]$Valor }
        # A vírgula impede o PowerShell de desmontar o array no retorno (viraria Object[] e o SetValue recusa).
        'Binary' { return , ([byte[]]@($Valor)) }
        'MultiString' { return , ([string[]]@($Valor)) }
        default { return [string]$Valor }
    }
}

function Test-TmdValorIgual {
    param([string]$TipoValor, $A, $B)
    if ($null -eq $A -or $null -eq $B) { return $null -eq $A -and $null -eq $B }
    switch ($TipoValor) {
        'DWord' { return ([int64]$A -band [int64]4294967295) -eq ([int64]$B -band [int64]4294967295) }
        'QWord' { return [int64]$A -eq [int64]$B }
        'Binary' { return (@($A) -join ',') -eq (@($B) -join ',') }
        'MultiString' { return (@($A) -join "`0") -ceq (@($B) -join "`0") }
        default { return [string]$A -ceq [string]$B }
    }
}

# Rede de segurança extra: .reg da chave antes de mexer. Falhar aqui não impede o ajuste (o snapshot já está salvo).
function Backup-TmdRegistro {
    param([Parameter(Mandatory)]$Mudanca, [string]$RaizRegistro, [string]$Id)
    if ($Mudanca.Tipo -ne 'Registro') { return }
    try {
        $c = Split-TmdCaminhoRegistro -Caminho $Mudanca.Caminho -RaizRegistro $RaizRegistro
        $base = Open-TmdBaseRegistro $c.Hive
        try { $existe = $null -ne $base.OpenSubKey($c.Sub, $false) } finally { $base.Close() }
        if (-not $existe) { return }
        $pasta = Join-Path (Get-TmdPastaDados) 'backup'
        [void][IO.Directory]::CreateDirectory($pasta)
        $arquivo = Join-Path $pasta ('{0}-{1}-{2}.reg' -f (Get-Date -Format 'yyyyMMdd-HHmmss'), $Id, $Mudanca.Indice)
        & reg.exe export $c.Texto $arquivo /y /reg:64 | Out-Null
        if ($LASTEXITCODE -ne 0) { Write-Verbose "reg export falhou ($LASTEXITCODE) para $($c.Texto)" }
    }
    catch {
        Write-Verbose "backup do registro falhou: $($_.Exception.Message)"
    }
}

# ---------- Serviços e tarefas (isolados para os testes trocarem por Mock) ----------

# Lido do registro (Services\<nome>\Start): uma consulta CIM por serviço levava ~100 ms, e a página de ajustes lê dezenas.
function Get-TmdServicoInicializacao {
    param([Parameter(Mandatory)][string]$Nome)
    $chave = "HKLM:\SYSTEM\CurrentControlSet\Services\$Nome"
    $inicio = Read-TmdRegistro -Caminho $chave -Nome 'Start'
    if (-not $inicio.Existe) { return $null }
    switch ([int]$inicio.Valor) {
        2 {
            $atraso = Read-TmdRegistro -Caminho $chave -Nome 'DelayedAutostart'
            if ($atraso.Existe -and $atraso.Valor -eq 1) { return 'AutomaticDelayedStart' }
            return 'Automatic'
        }
        3 { return 'Manual' }
        4 { return 'Disabled' }
        default { return "Start=$($inicio.Valor)" }
    }
}

function Set-TmdServicoInicializacao {
    param([Parameter(Mandatory)][string]$Nome, [Parameter(Mandatory)][string]$Inicializacao)
    $mapa = @{ Automatic = 'auto'; AutomaticDelayedStart = 'delayed-auto'; Manual = 'demand'; Disabled = 'disabled' }
    $saida = & sc.exe config $Nome start= $mapa[$Inicializacao]
    if ($LASTEXITCODE -ne 0) { throw "sc.exe falhou ($LASTEXITCODE): $(@($saida) -join ' ')" }
}

function Get-TmdTarefaHabilitada {
    param([Parameter(Mandatory)][string]$Caminho, [Parameter(Mandatory)][string]$Nome)
    $t = Get-ScheduledTask -TaskPath $Caminho -TaskName $Nome -ErrorAction SilentlyContinue
    if (-not $t) { return $null }
    [string]$t.State -ne 'Disabled'
}

function Set-TmdTarefaHabilitada {
    param([Parameter(Mandatory)][string]$Caminho, [Parameter(Mandatory)][string]$Nome, [bool]$Habilitada)
    if ($Habilitada) { Enable-ScheduledTask -TaskPath $Caminho -TaskName $Nome | Out-Null }
    else { Disable-ScheduledTask -TaskPath $Caminho -TaskName $Nome | Out-Null }
}
