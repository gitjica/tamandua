# Programas instalados (pelas chaves Uninstall do registro) e os restos que eles deixam.
# Desinstalar = rodar o desinstalador do próprio programa e esperar ele sair da lista.
# Restos = pastas com o nome exato do programa em AppData/ProgramData, só de programas que o Tamanduá desinstalou; vão para a Lixeira.

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$script:ChavesUninstall = @(
    @{ Rotulo = 'HKLM64'; Hive = 'LocalMachine'; Visao = 'Registry64'; Caminho = 'SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall' }
    @{ Rotulo = 'HKLM32'; Hive = 'LocalMachine'; Visao = 'Registry32'; Caminho = 'SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall' }
    @{ Rotulo = 'HKCU'; Hive = 'CurrentUser'; Visao = 'Default'; Caminho = 'Software\Microsoft\Windows\CurrentVersion\Uninstall' }
)
# Coisas que outras dependem e que o Windows ou drivers precisam: risco alto (nunca marcado).
$script:PadraoSensivel = 'Visual C\+\+|\.NET|Windows|Microsoft Edge|WebView2|Driver|Intel\(R\)|NVIDIA|AMD Software|Realtek|Chipset|Runtime|Redistributable|Microsoft Update Health'
# Depois que o desinstalador termina, quanto tempo esperar o programa sumir da lista (alguns relançam a si mesmos e saem na hora).
$script:EsperaMaximaSeg = 90

function Test-Requisitos {
    @{ Ok = $true; Motivo = '' }
}

# ---------- Leitura (registro) ----------

# Programas listáveis: com nome e desinstalador, sem componentes de sistema nem atualizações.
function Get-RegistroPrograma {
    foreach ($fonte in $script:ChavesUninstall) {
        $base = [Microsoft.Win32.RegistryKey]::OpenBaseKey([Microsoft.Win32.RegistryHive]$fonte.Hive, [Microsoft.Win32.RegistryView]$fonte.Visao)
        try {
            $raiz = $base.OpenSubKey($fonte.Caminho, $false)
            if (-not $raiz) { continue }
            try {
                foreach ($nomeChave in $raiz.GetSubKeyNames()) {
                    $k = $raiz.OpenSubKey($nomeChave, $false)
                    if (-not $k) { continue }
                    try {
                        $nome = [string]$k.GetValue('DisplayName')
                        $desinstalar = [string]$k.GetValue('UninstallString')
                        if (-not $nome -or -not $desinstalar) { continue }
                        if ($k.GetValue('SystemComponent') -eq 1 -or $k.GetValue('ParentKeyName') -or ([string]$k.GetValue('ReleaseType')) -in 'Update', 'Hotfix', 'Security Update') { continue }
                        [pscustomobject]@{
                            Id            = "prog:$($fonte.Rotulo):$nomeChave"
                            Nome          = $nome.Trim()
                            Editor        = [string]$k.GetValue('Publisher')
                            Versao        = [string]$k.GetValue('DisplayVersion')
                            TamanhoKB     = [int64]($k.GetValue('EstimatedSize', 0))
                            Instalado     = [string]$k.GetValue('InstallDate')
                            Desinstalador = $desinstalar
                            ParaTodos     = $fonte.Hive -eq 'LocalMachine'
                            Icone         = [string]$k.GetValue('DisplayIcon')
                        }
                    }
                    finally { $k.Close() }
                }
            }
            finally { $raiz.Close() }
        }
        finally { $base.Close() }
    }
}

# Onde procurar restos. Variáveis de ambiente: os testes trocam por pastas da sandbox.
function Get-PastaResto {
    @($env:APPDATA, $env:LOCALAPPDATA, $env:ProgramData) | Where-Object { $_ -and (Test-Path -LiteralPath $_) } | ForEach-Object { [IO.Path]::GetFullPath($_).TrimEnd('\') }
}

function Get-ArquivoRestos {
    Join-Path (Get-TmdPastaDados) 'estado\restos.json'
}

# Restos guardados: { caminho; programa; raiz } de programas que o Tamanduá desinstalou.
function Read-Resto {
    $arquivo = Get-ArquivoRestos
    if (-not (Test-Path -LiteralPath $arquivo)) { return }
    try { foreach ($r in ([IO.File]::ReadAllText($arquivo, [Text.Encoding]::UTF8) | ConvertFrom-Json)) { $r } }
    catch { Write-Verbose "restos.json ilegível: $($_.Exception.Message)" }
}

function Save-Resto {
    param([AllowEmptyCollection()][object[]]$Restos)
    $arquivo = Get-ArquivoRestos
    [void][IO.Directory]::CreateDirectory((Split-Path -Parent $arquivo))
    $json = if ($Restos.Count -eq 0) { '[]' } else { ConvertTo-Json -InputObject @($Restos) -Depth 3 }
    [IO.File]::WriteAllText($arquivo, $json, (New-Object Text.UTF8Encoding $false))
}

function Find-Alvos {
    # Ordena pelo grupo antes do nome: a tela mostra um cabeçalho por grupo.
    foreach ($p in @(Get-RegistroPrograma | Sort-Object @{ Expression = { -not $_.ParaTodos } }, Nome)) {
        $sensivel = $p.Nome -match $script:PadraoSensivel
        $partes = @()
        if ($p.Editor) { $partes += $p.Editor }
        if ($p.Versao) { $partes += "versão $($p.Versao)" }
        if ($p.TamanhoKB -gt 0) { $partes += Format-TmdTamanho ($p.TamanhoKB * 1KB) }
        # InstallDate deveria ser aaaaMMdd, mas há programas que gravam qualquer coisa: só mostra se for data válida.
        $data = [datetime]::MinValue
        if ([datetime]::TryParseExact([string]$p.Instalado, 'yyyyMMdd', [Globalization.CultureInfo]::InvariantCulture, 'None', [ref]$data)) {
            $partes += "instalado em $($data.ToString('dd/MM/yyyy'))"
        }
        if ($sensivel) { $partes += 'outros programas ou o Windows podem depender disto' }
        [pscustomobject]@{
            Id          = $p.Id
            Nome        = $p.Nome
            Categoria   = if ($p.ParaTodos) { 'Programas (para todos os usuários)' } else { 'Programas (só seu usuário)' }
            Caminho     = ''
            Tamanho     = [int64]($p.TamanhoKB * 1KB)
            Estado      = 'NaoSeAplica'
            Detalhe     = $partes -join ' · '
            Nivel       = 'Normal'
            Valor       = $null
            Risco       = if ($sensivel) { 'Alto' } else { 'Medio' }
            Selecionado = $false
            Destino     = 'NaoSeAplica'
            RequerAdmin = $p.ParaTodos
            Reversivel  = $false
            Icone       = $p.Icone
            Mudancas    = @("Roda o desinstalador do programa: $($p.Desinstalador)", 'Depois, pastas com o nome dele em AppData/ProgramData aparecem em "Restos" para você decidir.')
        }
    }
    foreach ($r in @(Read-Resto)) {
        if (-not (Test-Path -LiteralPath $r.caminho)) { continue }
        $m = Measure-TmdTamanho -Caminho $r.caminho
        [pscustomobject]@{
            Id = "resto:$($r.caminho)"; Nome = (Split-Path -Leaf $r.caminho); Categoria = 'Restos de programas desinstalados'
            Caminho = $r.caminho; Tamanho = [int64]$m.Bytes; Estado = 'NaoSeAplica'
            Detalhe = "$(Format-TmdTamanho $m.Bytes) · sobrou de $($r.programa) · $($r.caminho)"
            Nivel = 'Normal'; Valor = $null; Risco = 'Medio'; Selecionado = $false; Destino = 'Lixeira'
            RequerAdmin = $false; Reversivel = $null; Mudancas = @("Vai para a Lixeira: $($r.caminho)", 'Pode ter configurações ou dados do programa; dá para recuperar pela Lixeira.')
        }
    }
}

# ---------- Ação ----------

function Invoke-Acao {
    param([Parameter(Mandatory)][AllowEmptyCollection()][object[]]$Alvos, [switch]$Simular)

    $programas = @{}
    foreach ($p in Get-RegistroPrograma) { $programas[$p.Id] = $p }
    foreach ($a in $Alvos) {
        $id = [string]$a.Id
        if ($id -like 'resto:*') { Invoke-RemoverResto -Id $id -Simular $Simular; continue }
        if (-not $programas.ContainsKey($id)) {
            New-ResultadoDesinstalar -Id $id -Nome $id -Status 'Ignorado' -Motivo 'não está mais na lista de programas instalados' -Simular $Simular
            continue
        }
        Invoke-Desinstalacao -Programa $programas[$id] -Simular $Simular
    }
}

function Invoke-Desinstalacao {
    param([Parameter(Mandatory)]$Programa, [bool]$Simular)

    $comando = Get-ComandoDesinstalar -Linha $Programa.Desinstalador
    if (-not $comando) {
        return New-ResultadoDesinstalar -Id $Programa.Id -Nome $Programa.Nome -Status 'Erro' -Motivo "não entendi o comando de desinstalação: $($Programa.Desinstalador)" -Simular $Simular
    }
    $texto = "$($comando.Arquivo) $($comando.Argumentos)".Trim()
    if ($Simular) { return New-ResultadoDesinstalar -Id $Programa.Id -Nome $Programa.Nome -Status 'Simulado' -Mudancas @("executa: $texto") -Simular $true }

    $codigo = Start-Desinstalador -Arquivo $comando.Arquivo -Argumentos $comando.Argumentos
    if ($codigo -eq 1602) { return New-ResultadoDesinstalar -Id $Programa.Id -Nome $Programa.Nome -Status 'Ignorado' -Motivo 'cancelado no desinstalador' -Simular $false }

    # Muitos desinstaladores se copiam para o TEMP e saem na hora: espera o programa sumir da lista.
    $limite = (Get-Date).AddSeconds($script:EsperaMaximaSeg)
    do {
        $ainda = @(Get-RegistroPrograma | Where-Object { $_.Id -eq $Programa.Id }).Count -gt 0
        if (-not $ainda -or (Get-Date) -ge $limite) { break }
        Start-Sleep -Seconds 2
    } while ($true)

    if ($ainda) {
        $motivo = if ($codigo -eq 0) { 'o desinstalador terminou, mas o programa continua na lista (cancelado?)' } else { "o desinstalador terminou com código $codigo e o programa continua na lista" }
        return New-ResultadoDesinstalar -Id $Programa.Id -Nome $Programa.Nome -Status 'Erro' -Motivo $motivo -Simular $false
    }
    $restos = @(Add-RestoPrograma -Programa $Programa)
    $motivo = @()
    if ($codigo -in 3010, 1641) { $motivo += 'reinicie o computador para concluir' }
    if ($restos.Count -gt 0) { $motivo += "$($restos.Count) pasta(s) de resto em ""Restos de programas desinstalados""" }
    New-ResultadoDesinstalar -Id $Programa.Id -Nome $Programa.Nome -Status 'Feito' -Motivo ($motivo -join '; ') -Mudancas @("executado: $texto") -Simular $false
}

# Separa executável e argumentos. MsiExec vira sempre "/x {GUID}" (o /I das chaves abriria o reparo).
function Get-ComandoDesinstalar {
    param([Parameter(Mandatory)][string]$Linha)
    $l = $Linha.Trim()
    $arquivo = $null
    $argumentos = ''
    if ($l -match '^"([^"]+)"\s*(.*)$') { $arquivo = $Matches[1]; $argumentos = $Matches[2] }
    elseif ($l -match '^(.+?\.exe)(\s+.*)?$') { $arquivo = $Matches[1]; $argumentos = "$($Matches[2])".Trim() }
    if (-not $arquivo) { return $null }
    if ((Split-Path -Leaf $arquivo) -ieq 'msiexec.exe' -or (Split-Path -Leaf $arquivo) -ieq 'msiexec') {
        if ($argumentos -notmatch '(\{[0-9A-Fa-f-]{36}\})') { return $null }
        return [pscustomobject]@{ Arquivo = 'msiexec.exe'; Argumentos = "/x $($Matches[1])" }
    }
    [pscustomobject]@{ Arquivo = $arquivo; Argumentos = $argumentos }
}

# Único ponto que roda um desinstalador (Mock nos testes). Devolve o código de saída.
function Start-Desinstalador {
    param([Parameter(Mandatory)][string]$Arquivo, [string]$Argumentos)
    $parametros = @{ FilePath = $Arquivo; Wait = $true; PassThru = $true }
    if ($Argumentos) { $parametros.ArgumentList = $Argumentos }
    (Start-Process @parametros).ExitCode
}

# Pastas com o nome exato do programa (sem versão nem arquitetura) nas pastas de dados. Guarda para a seção "Restos".
function Add-RestoPrograma {
    param([Parameter(Mandatory)]$Programa)
    $nomes = @(Get-NomeLimpo -Nome $Programa.Nome)
    if ($Programa.Editor) { $nomes += @(Get-NomeLimpo -Nome $Programa.Editor | ForEach-Object { "$_\$(Get-NomeLimpo -Nome $Programa.Nome)" }) }
    $achados = @(foreach ($raiz in Get-PastaResto) {
            foreach ($n in $nomes | Where-Object { $_ -and $_.Length -ge 4 }) {
                $c = Join-Path $raiz $n
                if (Test-Path -LiteralPath $c -PathType Container) { [pscustomobject]@{ caminho = $c; programa = $Programa.Nome; raiz = $raiz } }
            }
        })
    if ($achados.Count -eq 0) { return }
    $todos = @(Read-Resto) + $achados | Group-Object { $_.caminho.ToLowerInvariant() } | ForEach-Object { $_.Group[0] }
    Save-Resto -Restos @($todos)
    $achados
}

# "Obsidian 1.14.4 (x64)" -> "Obsidian"; "Acme Software, Inc." -> "Acme Software".
function Get-NomeLimpo {
    param([string]$Nome)
    $n = $Nome -replace '\s*\((x64|x86|64-bit|32-bit|user|machine)\)', '' -replace '\s+v?\d+(\.\d+)+.*$', '' -replace ',?\s+(Inc|LLC|Ltd|GmbH|Corporation|Corp)\.?$', ''
    $n = $n.Trim()
    if ($n.IndexOfAny([IO.Path]::GetInvalidFileNameChars()) -ge 0) { return '' }
    $n
}

function Invoke-RemoverResto {
    param([Parameter(Mandatory)][string]$Id, [bool]$Simular)
    $caminho = $Id.Substring(6)
    $restos = @(Read-Resto)
    $registro = @($restos | Where-Object { $_.caminho -eq $caminho })
    if ($registro.Count -eq 0) {
        return [pscustomobject]@{ Id = $Id; Status = 'Ignorado'; Liberado = [int64]0; Motivo = 'não é um resto guardado pelo Tamanduá'; Mudancas = @() }
    }
    $r = Remove-TmdItem -Caminho $caminho -Raizes $registro[0].raiz -Destino Lixeira -Simular:$Simular -Modulo 'desinstalar' -Id $Id
    if (-not $Simular -and $r.Status -in 'Feito') { Save-Resto -Restos @($restos | Where-Object { $_.caminho -ne $caminho }) }
    $r
}

function New-ResultadoDesinstalar {
    param([string]$Id, [string]$Nome, [string]$Status, [string]$Motivo = '', [string[]]$Mudancas = @(), [bool]$Simular)
    Write-TmdOperacao -Modulo 'desinstalar' -Id $Id -Acao 'desinstalar' -Caminho $Nome -Status $Status -Motivo $Motivo -Simulado $Simular
    [pscustomobject]@{ Id = $Id; Status = $Status; Liberado = [int64]0; Motivo = $Motivo; Mudancas = $Mudancas }
}

Export-ModuleMember -Function Test-Requisitos, Find-Alvos, Invoke-Acao
