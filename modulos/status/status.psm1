# Painel do sistema. Só leitura.
# Get-LeituraSistema é o único ponto que consulta o Windows; o resto é conversão pura, testável sem o sistema real.

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Limites de alerta. Disco: % livre; os outros: % usado.
$script:Limites = @{
    CpuAtencao       = 80;  CpuCritico       = 95
    MemoriaAtencao   = 80;  MemoriaCritico   = 92
    DiscoAtencao     = 15;  DiscoCritico     = 7;  DiscoCriticoBytes = 2GB
    BateriaAtencao   = 20;  BateriaCritico   = 10
    DiasLigadoAtencao = 14
}

function Test-Requisitos {
    try {
        Get-CimInstance -ClassName Win32_OperatingSystem -Property Caption | Out-Null
        @{ Ok = $true; Motivo = '' }
    }
    catch {
        @{ Ok = $false; Motivo = "não foi possível ler o sistema via CIM: $($_.Exception.Message)" }
    }
}

function Find-Alvos {
    ConvertTo-AlvoStatus -Leitura (Get-LeituraSistema)
}

# Cada seção é lida isolada: se uma falhar, vira $null e as outras continuam.
# Seções de lista devolvem @() quando não há nada (ex.: desktop sem bateria) e $null quando a leitura falhou.
function Get-LeituraSistema {
    # A CPU é medida no intervalo em que as outras seções são lidas: não fica parada esperando.
    $cpu = Invoke-Secao { Start-TmdMedidaCpu }
    $os = Invoke-Secao {
        Get-CimInstance -ClassName Win32_OperatingSystem -Property Caption, BuildNumber, LastBootUpTime, TotalVisibleMemorySize, FreePhysicalMemory
    }
    $sistema = $null
    $memoria = $null
    if ($os) {
        $sistema = [pscustomobject]@{ Nome = $os.Caption; Build = $os.BuildNumber; Inicio = $os.LastBootUpTime }
        $memoria = [pscustomobject]@{ TotalBytes = [int64]$os.TotalVisibleMemorySize * 1KB; LivreBytes = [int64]$os.FreePhysicalMemory * 1KB }
    }
    $leitura = [pscustomobject]@{
        Agora      = Get-Date
        Sistema    = $sistema
        Memoria    = $memoria
        Cpu        = $null
        Discos     = Invoke-Secao -Lista {
            Get-CimInstance -ClassName Win32_LogicalDisk -Filter 'DriveType = 3' | ForEach-Object {
                [pscustomobject]@{ Letra = $_.DeviceID; Rotulo = $_.VolumeName; TotalBytes = [int64]$_.Size; LivreBytes = [int64]$_.FreeSpace }
            }
        }
        Rede       = Invoke-Secao -Lista {
            Get-CimInstance -ClassName Win32_NetworkAdapterConfiguration -Filter 'IPEnabled = TRUE' | ForEach-Object {
                $ipv4 = @($_.IPAddress | Where-Object { $_ -match '^\d{1,3}(\.\d{1,3}){3}$' })
                [pscustomobject]@{ Indice = $_.Index; Nome = $_.Description; IPv4 = if ($ipv4.Count -gt 0) { $ipv4[0] } }
            }
        }
        Bateria    = Invoke-Secao -Lista {
            Get-CimInstance -ClassName Win32_Battery | ForEach-Object {
                # BatteryStatus 2 = na tomada; 6 a 9 = carregando.
                [pscustomobject]@{ Percentual = [int]$_.EstimatedChargeRemaining; Carregando = $_.BatteryStatus -in 2, 6, 7, 8, 9 }
            }
        }
        Processos  = Invoke-Secao -Lista {
            Get-Process | Sort-Object WorkingSet64 -Descending | Select-Object -First 5 | ForEach-Object {
                [pscustomobject]@{ Nome = $_.ProcessName; MemoriaBytes = [int64]$_.WorkingSet64 }
            }
        }
    }
    if ($cpu) { $leitura.Cpu = Invoke-Secao { [pscustomobject]@{ Percentual = Get-TmdUsoCpu -Desde $cpu } } }
    $leitura
}

function Invoke-Secao {
    param([Parameter(Mandatory, Position = 0)][scriptblock]$Bloco, [switch]$Lista)

    try {
        $resultado = & $Bloco
        if ($Lista) { return , @($resultado) }
        $resultado
    }
    catch {
        $null
    }
}

function ConvertTo-AlvoStatus {
    param([Parameter(Mandatory)]$Leitura)

    $itens = [System.Collections.Generic.List[object]]::new()
    $l = $script:Limites

    if ($Leitura.Sistema) {
        $s = $Leitura.Sistema
        $itens.Add((New-ItemStatus 'sistema-windows' 'Windows' 'Sistema' "$($s.Nome) (build $($s.Build))"))
        $ligado = $Leitura.Agora - $s.Inicio
        $detalhe = Format-Duracao $ligado
        $nivel = 'Normal'
        if ($ligado.TotalDays -gt $l.DiasLigadoAtencao) {
            $nivel = 'Atencao'
            $detalhe += ' - reinicie para aplicar atualizações'
        }
        $itens.Add((New-ItemStatus 'sistema-ligado' 'Ligado há' 'Sistema' $detalhe $nivel))
    }
    else {
        $itens.Add((New-ItemStatus 'sistema-windows' 'Windows' 'Sistema' -Desconhecido))
    }

    if ($Leitura.Cpu) {
        $p = $Leitura.Cpu.Percentual
        $itens.Add((New-ItemStatus 'cpu' 'CPU' 'Desempenho' "$p%" (Get-Nivel $p $l.CpuAtencao $l.CpuCritico) $p))
    }
    else {
        $itens.Add((New-ItemStatus 'cpu' 'CPU' 'Desempenho' -Desconhecido))
    }

    if ($Leitura.Memoria -and $Leitura.Memoria.TotalBytes -gt 0) {
        $m = $Leitura.Memoria
        $usado = $m.TotalBytes - $m.LivreBytes
        $p = [int][Math]::Round(100 * $usado / $m.TotalBytes)
        $detalhe = "$(Format-TmdTamanho $usado) de $(Format-TmdTamanho $m.TotalBytes) ($p%)"
        $itens.Add((New-ItemStatus 'memoria' 'Memória' 'Desempenho' $detalhe (Get-Nivel $p $l.MemoriaAtencao $l.MemoriaCritico) $p))
    }
    else {
        $itens.Add((New-ItemStatus 'memoria' 'Memória' 'Desempenho' -Desconhecido))
    }

    if ($null -eq $Leitura.Discos) {
        $itens.Add((New-ItemStatus 'discos' 'Discos' 'Discos' -Desconhecido))
    }
    foreach ($d in @($Leitura.Discos | Where-Object { $_ -and $_.TotalBytes -gt 0 })) {
        $livre = [int][Math]::Round(100 * $d.LivreBytes / $d.TotalBytes)
        $nivel = 'Normal'
        if ($livre -lt $l.DiscoCritico -or $d.LivreBytes -lt $l.DiscoCriticoBytes) { $nivel = 'Critico' }
        elseif ($livre -lt $l.DiscoAtencao) { $nivel = 'Atencao' }
        $nome = if ($d.Rotulo) { "Disco $($d.Letra) ($($d.Rotulo))" } else { "Disco $($d.Letra)" }
        $detalhe = "$(Format-TmdTamanho $d.LivreBytes) livres de $(Format-TmdTamanho $d.TotalBytes) ($livre% livre)"
        $id = 'disco-' + ($d.Letra -replace '[^A-Za-z]', '').ToLowerInvariant()
        $itens.Add((New-ItemStatus $id $nome 'Discos' $detalhe $nivel (100 - $livre)))
    }

    if ($null -eq $Leitura.Rede) {
        $itens.Add((New-ItemStatus 'rede' 'Rede' 'Rede' -Desconhecido))
    }
    elseif ($Leitura.Rede.Count -eq 0) {
        $itens.Add((New-ItemStatus 'rede' 'Rede' 'Rede' 'sem conexão ativa' 'Atencao'))
    }
    foreach ($r in @($Leitura.Rede | Where-Object { $_ })) {
        $ip = if ($r.IPv4) { $r.IPv4 } else { 'sem IPv4' }
        $itens.Add((New-ItemStatus "rede-$($r.Indice)" $r.Nome 'Rede' $ip))
    }

    if ($null -eq $Leitura.Bateria) {
        $itens.Add((New-ItemStatus 'bateria' 'Bateria' 'Energia' -Desconhecido))
    }
    foreach ($b in @($Leitura.Bateria | Where-Object { $_ })) {
        $nivel = 'Normal'
        if (-not $b.Carregando) { $nivel = Get-Nivel (100 - $b.Percentual) (100 - $l.BateriaAtencao) (100 - $l.BateriaCritico) }
        $estado = if ($b.Carregando) { 'na tomada' } else { 'na bateria' }
        $itens.Add((New-ItemStatus 'bateria' 'Bateria' 'Energia' "$($b.Percentual)% ($estado)" $nivel $b.Percentual))
        break
    }

    if ($null -eq $Leitura.Processos) {
        $itens.Add((New-ItemStatus 'processos' 'Processos' 'Processos que mais usam memória' -Desconhecido))
    }
    $n = 0
    foreach ($p in @($Leitura.Processos | Where-Object { $_ })) {
        $n++
        $itens.Add((New-ItemStatus "processo-$n" $p.Nome 'Processos que mais usam memória' (Format-TmdTamanho $p.MemoriaBytes)))
    }

    $itens.Insert(0, (Get-ItemSaude -Itens $itens))
    $itens.ToArray()
}

# Nota de 0 a 100: cada ponto de atenção tira 10, cada crítico tira 25.
function Get-ItemSaude {
    param([Parameter(Mandatory)][AllowEmptyCollection()]$Itens)

    $atencao = @($Itens | Where-Object { $_.Nivel -eq 'Atencao' }).Count
    $critico = @($Itens | Where-Object { $_.Nivel -eq 'Critico' }).Count
    $nota = [Math]::Max(0, 100 - 10 * $atencao - 25 * $critico)
    $nivel = if ($nota -ge 80) { 'Normal' } elseif ($nota -ge 50) { 'Atencao' } else { 'Critico' }
    $detalhe = "$nota / 100"
    $problemas = $atencao + $critico
    if ($problemas -eq 1) { $detalhe += ' - 1 ponto de atenção' }
    elseif ($problemas -gt 1) { $detalhe += " - $problemas pontos de atenção" }
    New-ItemStatus 'saude' 'Saúde' 'Resumo' $detalhe $nivel $nota
}

function Get-Nivel {
    param([double]$Valor, [double]$Atencao, [double]$Critico)
    if ($Valor -ge $Critico) { return 'Critico' }
    if ($Valor -ge $Atencao) { return 'Atencao' }
    'Normal'
}

function Format-Duracao {
    param([Parameter(Mandatory)][timespan]$Duracao)
    if ($Duracao.TotalDays -ge 1) { return '{0} d {1} h' -f [int][Math]::Floor($Duracao.TotalDays), $Duracao.Hours }
    if ($Duracao.TotalHours -ge 1) { return '{0} h {1} min' -f $Duracao.Hours, $Duracao.Minutes }
    '{0} min' -f [int][Math]::Floor($Duracao.TotalMinutes)
}

function New-ItemStatus {
    param(
        [Parameter(Mandatory, Position = 0)][string]$Id,
        [Parameter(Mandatory, Position = 1)][string]$Nome,
        [Parameter(Mandatory, Position = 2)][string]$Categoria,
        [Parameter(Position = 3)][string]$Detalhe = '',
        [Parameter(Position = 4)][string]$Nivel = 'Normal',
        [Parameter(Position = 5)]$Valor = $null,
        [switch]$Desconhecido
    )
    [pscustomobject]@{
        Id        = $Id
        Nome      = $Nome
        Categoria = $Categoria
        Estado    = if ($Desconhecido) { 'Desconhecido' } else { 'NaoSeAplica' }
        Detalhe   = if ($Desconhecido) { 'não foi possível ler' } else { $Detalhe }
        Nivel     = $Nivel
        Valor     = $Valor
    }
}

Export-ModuleMember -Function Test-Requisitos, Find-Alvos
