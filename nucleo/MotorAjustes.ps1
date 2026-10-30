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

# Primeira linha das mudanças de um ajuste que já está aplicado: marcado, ele é desfeito (e para onde volta).
function Get-TmdTextoDesfaz {
    param([Parameter(Mandatory)][string]$Id)
    $volta = if (Test-TmdAjusteReversivel -Id $Id) { 'volta ao valor que estava antes de o Tamanduá aplicar' }
    else { 'volta ao padrão do Windows (foi aplicado antes, por outra ferramenta ou versão, e o valor anterior não foi salvo)' }
    "Já está aplicado. Marcado, é DESFEITO: $volta."
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

# Ação única do catálogo ("acao": true, "executar": script): coisas que se fazem uma vez e não têm estado nem desfazer
# (ponto de restauração, Limpeza de Disco, apagar temporários, abrir o O&O). O script roda dentro do núcleo e pode
# devolver resultados de Remove-TmdItem: o espaço liberado é somado e o que foi pulado vira "Parcial".
function Invoke-TmdAcaoAjuste {
    [CmdletBinding()]
    param([Parameter(Mandatory)]$Ajuste, [switch]$Simular, [string]$Modulo = 'ajustes')
    $id = [string](Get-Propriedade $Ajuste 'id')
    $nome = [string](Get-Propriedade $Ajuste 'nome')
    $executar = [string](Get-Propriedade $Ajuste 'executar')
    $resultado = if (-not $executar) { New-TmdResultadoAjuste -Id $id -Status 'Erro' -Motivo 'ação sem "executar"' }
    elseif ($Simular) { New-TmdResultadoAjuste -Id $id -Status 'Simulado' -Mudancas @("executa uma vez: $nome") }
    elseif ((Get-Propriedade $Ajuste 'requerAdmin') -eq $true -and -not (Test-TmdAdministrador)) {
        New-TmdResultadoAjuste -Id $id -Status 'Ignorado' -Motivo 'precisa de permissão de administrador'
    }
    else {
        try {
            $saida = @(& ([scriptblock]::Create($executar)) | Where-Object { $_ -and $_.PSObject.Properties['Status'] })
            $r = New-TmdResultadoAjuste -Id $id -Status 'Feito'
            foreach ($s in $saida) { $r.Liberado += [int64](Get-Propriedade $s 'Liberado') }
            $pulados = @($saida | Where-Object { $_.Status -notin 'Feito', 'Simulado' -and $_.Motivo -ne 'não existe mais' })
            if ($pulados.Count -gt 0) { $r.Status = 'Parcial'; $r.Motivo = "$($pulados.Count) item(ns) pulado(s) (ex.: $($pulados[0].Motivo))" }
            $r
        }
        catch { New-TmdResultadoAjuste -Id $id -Status 'Erro' -Motivo (Get-TmdExcecaoInterna $_.Exception).Message }
    }
    Write-TmdOperacao -Modulo $Modulo -Id $id -Acao 'executar' -Caminho $nome -Status $resultado.Status -Liberado $resultado.Liberado `
        -Motivo $resultado.Motivo -Simulado ([bool]$Simular)
    $resultado
}

# ---------- Leituras rápidas para os "verificar" do catálogo (várias páginas perguntam a mesma coisa) ----------

$script:CacheLeitura = @{}

function Get-TmdLeituraGuardada {
    param([Parameter(Mandatory)][string]$Chave, [Parameter(Mandatory)][scriptblock]$Ler, [int]$Segundos = 20)
    $g = $script:CacheLeitura[$Chave]
    if ($g -and ([DateTime]::UtcNow - $g.Quando).TotalSeconds -lt $Segundos) {
        # Leitura que falhou (ex.: precisa de admin) também fica guardada: não vale tentar de novo na mesma página.
        if ($g.ContainsKey('Erro')) { throw $g['Erro'] }
        return , $g.Valor
    }
    $valor = @(& $Ler)
    $script:CacheLeitura[$Chave] = @{ Quando = [DateTime]::UtcNow; Valor = $valor }
    , $valor
}

# Leituras lentas do Windows (cada uma carrega um módulo e consulta o sistema: 0,5 a 3 s). Os "verificar" do catálogo
# usam Get-TmdLeitura <chave>, e Update-TmdLeiturasLentas lê todas ao mesmo tempo no começo da página de ajustes.
# Cada bloco tem que se virar sozinho (roda num runspace sem o núcleo).
$script:LeiturasLentas = [ordered]@{
    appx                   = { Get-AppxPackage -ErrorAction Stop | ForEach-Object { [string]$_.Name } }
    # Primeiro DNS IPv4 de cada placa física conectada. Física = a marca NCF_PHYSICAL (4) que o Get-NetAdapter -Physical
    # também usa, lida direto do registro; o DNS vem do .NET. ~0,1 s, contra ~2 s do Get-NetAdapter/Get-DnsClient (CIM).
    dns                    = {
        $classe = 'HKLM:\SYSTEM\CurrentControlSet\Control\Class\{4d36e972-e325-11ce-bfc1-08002be10318}'
        $fisicas = @{}
        foreach ($k in @(Get-ChildItem -LiteralPath $classe -ErrorAction SilentlyContinue)) {
            $p = Get-ItemProperty -LiteralPath $k.PSPath -ErrorAction SilentlyContinue
            if ($p -and $p.PSObject.Properties['NetCfgInstanceId'] -and $p.PSObject.Properties['Characteristics'] -and ([int]$p.Characteristics -band 4)) {
                $fisicas[[string]$p.NetCfgInstanceId] = $true
            }
        }
        foreach ($n in [Net.NetworkInformation.NetworkInterface]::GetAllNetworkInterfaces()) {
            if ([string]$n.OperationalStatus -ne 'Up' -or -not $fisicas.ContainsKey($n.Id)) { continue }
            $s = @($n.GetIPProperties().DnsAddresses | Where-Object { $_.AddressFamily -eq 'InterNetwork' } | ForEach-Object { $_.IPAddressToString })
            if ($s.Count -gt 0) { [string]$s[0] } else { '' }
        }
    }
    teredo                 = { [string](Get-NetTeredoConfiguration -ErrorAction Stop).Type }
    defenderAmostras       = { [int](Get-MpPreference -ErrorAction Stop).SubmitSamplesConsent }
    armazenamentoReservado = { [string](Get-WindowsReservedStorageState -ErrorAction Stop).ReservedStorageState }
    recall                 = { $f = Get-WindowsOptionalFeature -Online -FeatureName Recall -ErrorAction Stop; if ($f) { [string]$f.State } else { '' } }
}

function Get-TmdLeitura {
    param([Parameter(Mandatory)][string]$Chave)
    if (-not $script:LeiturasLentas.Contains($Chave)) { throw "leitura desconhecida: $Chave" }
    $segundos = if ($Chave -eq 'dns') { 10 } else { 20 }
    Get-TmdLeituraGuardada -Chave $Chave -Segundos $segundos -Ler $script:LeiturasLentas[$Chave]
}

# Faz todas as leituras lentas de uma vez, em paralelo, e guarda (inclusive as que falharam). Sempre lê de novo:
# a página de ajustes chama isto ao abrir, então o estado mostrado é o de agora, mesmo logo depois de aplicar.
function Update-TmdLeiturasLentas {
    [CmdletBinding()]
    param([string[]]$Chaves = @($script:LeiturasLentas.Keys))
    $conjunto = [runspacefactory]::CreateRunspacePool(1, [Math]::Max(1, $Chaves.Count))
    $conjunto.Open()
    try {
        $tarefas = foreach ($k in $Chaves) {
            $ps = [powershell]::Create()
            $ps.RunspacePool = $conjunto
            [void]$ps.AddScript("`$ErrorActionPreference = 'Stop'; $($script:LeiturasLentas[$k].ToString())")
            [pscustomobject]@{ Chave = $k; Ps = $ps; Espera = $ps.BeginInvoke() }
        }
        foreach ($t in $tarefas) {
            try {
                $valor = @($t.Ps.EndInvoke($t.Espera))
                if ($t.Ps.HadErrors -and $t.Ps.Streams.Error.Count -gt 0) { throw $t.Ps.Streams.Error[0].Exception }
                $script:CacheLeitura[$t.Chave] = @{ Quando = [DateTime]::UtcNow; Valor = $valor }
            }
            catch { $script:CacheLeitura[$t.Chave] = @{ Quando = [DateTime]::UtcNow; Erro = (Get-TmdExcecaoInterna $_.Exception).Message } }
            finally { $t.Ps.Dispose() }
        }
    }
    finally { $conjunto.Close(); $conjunto.Dispose() }
}

# App da Store instalado para o usuário atual? (uma leitura de Get-AppxPackage serve para os 34 apps do catálogo)
function Test-TmdAppxInstalado {
    param([Parameter(Mandatory)][string]$Nome)
    $nomes = Get-TmdLeitura -Chave 'appx'
    @($nomes | Where-Object { $_ -like $Nome }).Count -gt 0
}

# Remove um app da Store para todos os usuários e da imagem (contas novas não ganham de novo).
function Remove-TmdAppx {
    param([Parameter(Mandatory)][string]$Nome)
    foreach ($p in @(Get-AppxPackage -AllUsers -Name $Nome -ErrorAction Stop)) { Remove-AppxPackage -Package $p.PackageFullName -AllUsers -ErrorAction Stop }
    Get-AppxProvisionedPackage -Online -ErrorAction SilentlyContinue | Where-Object DisplayName -eq $Nome |
        Remove-AppxProvisionedPackage -Online -ErrorAction SilentlyContinue | Out-Null
    $script:CacheLeitura.Remove('appx')
}

# Reinstala um app pela Microsoft Store (winget, fonte msstore). "Já instalado" não é erro.
function Install-TmdAppxDaLoja {
    param([Parameter(Mandatory)][string]$IdLoja)
    $r = Invoke-TmdPrograma -Arquivo 'winget.exe' -Argumentos "install --id $IdLoja --source msstore --accept-package-agreements --accept-source-agreements --disable-interactivity" -Modulo 'ajustes' -Id $IdLoja
    $script:CacheLeitura.Remove('appx')
    if ($r.Codigo -ne 0 -and $r.Codigo -ne -1978335135) { throw "winget terminou com código $($r.Codigo)" }
}

# DNS IPv4 principal de cada placa de rede física conectada.
function Get-TmdDnsAtual {
    Get-TmdLeitura -Chave 'dns'
}

# Troca o DNS de todas as placas físicas conectadas (IPv4 e, se der, IPv6). Sem endereços: volta para o automático (DHCP).
function Set-TmdDns {
    param([string[]]$Ipv4 = @(), [string[]]$Ipv6 = @())
    $placas = @(Get-NetAdapter -Physical -ErrorAction Stop | Where-Object Status -eq 'Up')
    if ($placas.Count -eq 0) { throw 'nenhuma placa de rede conectada' }
    foreach ($a in $placas) {
        if ($Ipv4.Count -eq 0) { Set-DnsClientServerAddress -InterfaceIndex $a.ifIndex -ResetServerAddresses -ErrorAction Stop; continue }
        try { Set-DnsClientServerAddress -InterfaceIndex $a.ifIndex -ServerAddresses ($Ipv4 + $Ipv6) -ErrorAction Stop }
        catch { Set-DnsClientServerAddress -InterfaceIndex $a.ifIndex -ServerAddresses $Ipv4 -ErrorAction Stop }
    }
    $script:CacheLeitura.Remove('dns')
    Clear-DnsClientCache -ErrorAction SilentlyContinue
}

# Bloqueia (ou libera, com -Liberar) a escrita de "Todos" numa pasta: o Windows Update não consegue reinstalar o que ia nela.
function Set-TmdPastaBloqueada {
    param([Parameter(Mandatory)][string]$Pasta, [switch]$Liberar)
    if ($Liberar) {
        if (-not (Test-Path -LiteralPath $Pasta)) { return }
        $s = & icacls.exe $Pasta /remove:d '*S-1-1-0'
    }
    else {
        [void][IO.Directory]::CreateDirectory($Pasta)
        $s = & icacls.exe $Pasta /deny '*S-1-1-0:(W)'
    }
    if ($LASTEXITCODE -ne 0) { throw "icacls falhou: $(@($s) -join ' ')" }
}

function Test-TmdPastaBloqueada {
    param([Parameter(Mandatory)][string]$Pasta)
    if (-not (Test-Path -LiteralPath $Pasta)) { return $false }
    @((Get-Acl -LiteralPath $Pasta).Access | Where-Object {
            $_.AccessControlType -eq 'Deny' -and $_.IdentityReference.Translate([Security.Principal.SecurityIdentifier]).Value -eq 'S-1-1-0'
        }).Count -gt 0
}

# Chave inteira fora, com volta: antes de apagar, "reg export" para estado\chaves\<Id>.reg; Restore- importa de volta.
# (O motor guarda valores; uma chave como ".bmp\ShellNew" só some do menu "Novo" se a chave sumir.)
function Get-TmdArquivoChaveGuardada {
    param([Parameter(Mandatory)][string]$Id)
    if ($Id -notmatch '^[a-z0-9-]+$') { throw "id inválido para guardar chave: $Id" }
    Join-Path (Join-Path (Get-TmdPastaDados) 'estado\chaves') "$Id.reg"
}

function Remove-TmdChaveComCopia {
    param([Parameter(Mandatory)][string]$Caminho, [Parameter(Mandatory)][string]$Id)
    $c = Split-TmdCaminhoRegistro -Caminho $Caminho
    $base = Open-TmdBaseRegistro $c.Hive
    try {
        $chave = $base.OpenSubKey($c.Sub, $false)
        if (-not $chave) { return }
        $chave.Close()
        $arquivo = Get-TmdArquivoChaveGuardada -Id $Id
        [void][IO.Directory]::CreateDirectory((Split-Path -Parent $arquivo))
        # O reg.exe escreve "concluída com êxito" no stderr; no 5.1, com Stop, isso viraria exceção.
        $ErrorActionPreference = 'Continue'
        $s = & reg.exe export $c.Texto $arquivo /y /reg:64 2>&1
        $ErrorActionPreference = 'Stop'
        if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $arquivo)) { throw "não deu para guardar a cópia de $($c.Texto): $(@($s) -join ' ')" }
        $base.DeleteSubKeyTree($c.Sub, $false)
    }
    finally { $base.Close() }
}

function Restore-TmdChaveComCopia {
    param([Parameter(Mandatory)][string]$Id)
    $arquivo = Get-TmdArquivoChaveGuardada -Id $Id
    if (-not (Test-Path -LiteralPath $arquivo)) { throw "não há cópia guardada para $Id" }
    $ErrorActionPreference = 'Continue'
    $s = & reg.exe import $arquivo /reg:64 2>&1
    $ErrorActionPreference = 'Stop'
    if ($LASTEXITCODE -ne 0) { throw "reg import falhou: $(@($s) -join ' ')" }
    [IO.File]::Delete($arquivo)
}

function Test-TmdChaveExiste {
    param([Parameter(Mandatory)][string]$Caminho)
    $c = Split-TmdCaminhoRegistro -Caminho $Caminho
    $base = Open-TmdBaseRegistro $c.Hive
    try { $k = $base.OpenSubKey($c.Sub, $false); if ($k) { $k.Close(); return $true }; $false }
    finally { $base.Close() }
}

# Esconde (ou mostra) um arquivo: o "Enviar para" só lista o que não está oculto. Nada é apagado.
function Set-TmdArquivoOculto {
    param([Parameter(Mandatory)][string]$Caminho, [bool]$Oculto = $true)
    if (-not [IO.File]::Exists($Caminho)) { return }
    $a = [IO.File]::GetAttributes($Caminho)
    $novo = if ($Oculto) { $a -bor [IO.FileAttributes]::Hidden } else { $a -band (-bnot [IO.FileAttributes]::Hidden) }
    [IO.File]::SetAttributes($Caminho, $novo)
}

# Fecha o Explorador para ele reler o menu de contexto e garante que ele volte. O Windows só reabre sozinho quando o
# Explorador cai por conta própria, não quando outro programa o fecha: espera um pouco e, se não voltou, abre.
# Aberto daqui mesmo com admin, o explorer.exe se reabre como usuário comum (o /NOUACCHECK existe para o contrário),
# então a área de trabalho não fica rodando como administrador. Só mexe no Explorador da sessão de quem usa.
function Restart-TmdExplorador {
    [CmdletBinding()]
    param([int]$EsperaMs = 4000)
    $sessao = [Diagnostics.Process]::GetCurrentProcess().SessionId
    $daSessao = { @(Get-Process -Name explorer -ErrorAction SilentlyContinue | Where-Object { $_.SessionId -eq $sessao }) }
    $idsAntes = @(& $daSessao | ForEach-Object Id)
    if ($idsAntes.Count -gt 0) { Stop-Process -Id $idsAntes -Force -ErrorAction SilentlyContinue }
    $relogio = [Diagnostics.Stopwatch]::StartNew()
    while ($relogio.ElapsedMilliseconds -lt $EsperaMs) {
        Start-Sleep -Milliseconds 250
        if (@(& $daSessao | Where-Object { $idsAntes -notcontains $_.Id }).Count -gt 0) { return }
    }
    Start-Process -FilePath (Join-Path $env:SystemRoot 'explorer.exe')
}

# Apaga o conteúdo de uma pasta item por item pelo núcleo (Remove-TmdItem, com a própria pasta como única raiz).
# Os temporários do próprio Tamanduá (tamandua-*: pedido, resposta e progresso do processo elevado) ficam.
function Clear-TmdConteudoPasta {
    param([Parameter(Mandatory)][string]$Pasta, [string]$Modulo = 'ajustes', [string]$Id = '')
    if (-not [IO.Directory]::Exists($Pasta)) { return }
    $raiz = [IO.Path]::GetFullPath($Pasta).TrimEnd('\')
    foreach ($i in ([IO.DirectoryInfo]::new($raiz)).GetFileSystemInfos()) {
        if ($i.Name -like 'tamandua-*') { continue }
        Remove-TmdItem -Caminho $i.FullName -Raizes $raiz -Modulo $Modulo -Id $Id
    }
}

# Ponto de restauração do Windows (isolado para Mock). Liga a Proteção do Sistema no disco do Windows se estiver
# desligada e libera criar mesmo com outro ponto nas últimas 24 h, só durante a criação (o WinUtil deixa liberado).
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
