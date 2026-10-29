# Instaladores, imagens de disco e pacotes esquecidos em Downloads. Tudo vai para a Lixeira (dá para recuperar).
# Cada arquivo é um alvo. Antes de mandar para a Lixeira, confere de novo tamanho e data: se mudou, não mexe.

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Extensão -> tipo. Só estes arquivos podem ser alvo, nem que o pedido diga outra coisa.
$script:Tipos = @{
    '.exe'        = @{ Categoria = 'Instaladores'; Risco = 'Baixo' }
    '.msi'        = @{ Categoria = 'Instaladores'; Risco = 'Baixo' }
    '.msix'       = @{ Categoria = 'Instaladores'; Risco = 'Baixo' }
    '.msixbundle' = @{ Categoria = 'Instaladores'; Risco = 'Baixo' }
    '.appx'       = @{ Categoria = 'Instaladores'; Risco = 'Baixo' }
    '.appxbundle' = @{ Categoria = 'Instaladores'; Risco = 'Baixo' }
    '.iso'        = @{ Categoria = 'Imagens de disco'; Risco = 'Baixo' }
    '.img'        = @{ Categoria = 'Imagens de disco'; Risco = 'Medio' }
    '.zip'        = @{ Categoria = 'Arquivos compactados'; Risco = 'Medio' }
    '.7z'         = @{ Categoria = 'Arquivos compactados'; Risco = 'Medio' }
    '.rar'        = @{ Categoria = 'Arquivos compactados'; Risco = 'Medio' }
}
$script:OrdemCategorias = @('Instaladores', 'Imagens de disco', 'Arquivos compactados')
# Numa subpasta, arquivos que não sejam estes ao lado de um .exe (ex.: .dll) indicam programa portátil já extraído:
# apagar o .exe quebraria o programa. Esses vêm com risco médio e nunca marcados.
$script:ExtensoesInocentes = @('.txt', '.md', '.url', '.nfo', '.sha256', '.sig', '.asc')
# Só vem marcado: risco baixo e baixado há mais tempo que isso (o recente pode estar esperando para ser instalado).
$script:DiasParaMarcar = 7
$script:ProfundidadeMaxima = 3
# Busca grande demais (pasta gigante, rede lenta): nada vem marcado, para ninguém apagar às cegas.
$script:LimiteArquivos = 20000

function Test-Requisitos {
    $pasta = Get-PastaDownloads
    if (-not (Test-Path -LiteralPath $pasta)) { return @{ Ok = $false; Motivo = "pasta Downloads não encontrada ($pasta)" } }
    @{ Ok = $true; Motivo = '' }
}

# Downloads de verdade (pode ter sido mudada de lugar). TAMANDUA_DOWNLOADS_TESTE só vale dentro do TEMP.
function Get-PastaDownloads {
    $teste = $env:TAMANDUA_DOWNLOADS_TESTE
    if ($teste) {
        $temp = [IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\')
        $teste = [IO.Path]::GetFullPath($teste).TrimEnd('\')
        if ($teste.StartsWith($temp + '\', [StringComparison]::OrdinalIgnoreCase)) { return $teste }
    }
    try {
        $v = Get-ItemProperty -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Shell Folders' -Name '{374DE290-123F-4565-9164-39C4925E467B}' -ErrorAction Stop
        $p = [string]$v.'{374DE290-123F-4565-9164-39C4925E467B}'
        if ($p) { return [IO.Path]::GetFullPath($p).TrimEnd('\') }
    }
    catch { Write-Verbose "pasta Downloads não está no registro: $($_.Exception.Message)" }
    Join-Path ([Environment]::GetFolderPath('UserProfile')) 'Downloads'
}

function Find-Alvos {
    param([string]$Pasta = (Get-PastaDownloads))

    $pasta = [IO.Path]::GetFullPath($Pasta).TrimEnd('\')
    $busca = Get-ArquivoCandidato -Pasta $pasta
    $agora = Get-Date
    foreach ($f in $busca.Arquivos) {
        $tipo = $script:Tipos[$f.Extension.ToLowerInvariant()]
        $relativo = $f.FullName.Substring($pasta.Length + 1)
        $dias = [int][Math]::Floor(($agora - $f.LastWriteTime).TotalDays)
        $onde = Split-Path -Parent $relativo
        $detalhe = "$(Format-TmdTamanho $f.Length) · $(Format-Idade $dias)"
        if ($onde) { $detalhe += " · em $onde\" }
        $risco = $tipo.Risco
        $portatil = $onde -and $busca.PastasComOutros.ContainsKey($f.DirectoryName)
        if ($portatil) {
            $risco = 'Medio'
            $detalhe += ' · parece programa portátil (há outros arquivos na pasta)'
        }
        [pscustomobject]@{
            Id          = "arq:$($relativo.ToLowerInvariant())"
            Nome        = $f.Name
            Categoria   = $tipo.Categoria
            Caminho     = $f.FullName
            Tamanho     = [int64]$f.Length
            Estado      = 'NaoSeAplica'
            Detalhe     = $detalhe
            Nivel       = 'Normal'
            Valor       = $null
            Risco       = $risco
            Selecionado = (-not $busca.Incompleta) -and $risco -eq 'Baixo' -and $dias -ge $script:DiasParaMarcar
            Destino     = 'Lixeira'
            RequerAdmin = $false
            Reversivel  = $null
            # Identidade do arquivo na hora da busca; Invoke-Acao confere de novo antes de mexer.
            Modificado  = $f.LastWriteTimeUtc.Ticks
            Mudancas    = @("Vai para a Lixeira: $($f.FullName)", 'Dá para recuperar pela Lixeira do Windows.')
        }
    }
    if ($busca.Incompleta) {
        [pscustomobject]@{
            Id = 'aviso-busca'; Nome = 'Busca incompleta'; Categoria = 'Aviso'; Caminho = ''; Tamanho = [int64]0
            Estado = 'NaoSeAplica'; Detalhe = "Mais de $($script:LimiteArquivos) arquivos: nada foi marcado. Escolha você o que mandar para a Lixeira."
            Nivel = 'Atencao'; Valor = $null; Risco = 'Baixo'; Selecionado = $false; Selecionavel = $false
            Destino = 'NaoSeAplica'; RequerAdmin = $false; Reversivel = $null; Modificado = [int64]0; Mudancas = @()
        }
    }
}

function Invoke-Acao {
    param(
        [Parameter(Mandatory)][AllowEmptyCollection()][object[]]$Alvos,
        [switch]$Simular,
        [string]$Pasta = (Get-PastaDownloads)
    )

    $pasta = [IO.Path]::GetFullPath($Pasta).TrimEnd('\')
    foreach ($a in $Alvos) {
        $id = [string]$a.Id
        $erro = Test-AlvoValido -Alvo $a -Pasta $pasta
        if ($erro) {
            [pscustomobject]@{ Id = $id; Status = 'Ignorado'; Liberado = [int64]0; Motivo = $erro }
            continue
        }
        # O caminho sai do Id e da pasta, não do Caminho que veio no alvo.
        $caminho = Join-Path $pasta $id.Substring(4)
        Remove-TmdItem -Caminho $caminho -Raizes $pasta -Destino Lixeira -Simular:$Simular -Modulo 'instaladores' -Id $id
    }
}

# Devolve o motivo para não mexer, ou $null se está tudo certo.
function Test-AlvoValido {
    param([Parameter(Mandatory)]$Alvo, [Parameter(Mandatory)][string]$Pasta)

    $id = [string]$Alvo.Id
    if ($id -notlike 'arq:*' -or $id -match '\.\.') { return 'item inválido' }
    $caminho = Join-Path $Pasta $id.Substring(4)
    if (-not $script:Tipos.ContainsKey([IO.Path]::GetExtension($caminho).ToLowerInvariant())) { return 'não é instalador, imagem de disco nem arquivo compactado' }
    $f = New-Object IO.FileInfo $caminho
    if (-not $f.Exists) { return 'não existe mais' }
    $tamanho = $Alvo.PSObject.Properties['Tamanho']
    $modificado = $Alvo.PSObject.Properties['Modificado']
    if (-not $tamanho -or -not $modificado -or $f.Length -ne [int64]$tamanho.Value -or $f.LastWriteTimeUtc.Ticks -ne [int64]$modificado.Value) {
        return 'o arquivo mudou desde a busca; busque de novo antes'
    }
    $null
}

# Arquivos com extensão conhecida, até ProfundidadeMaxima níveis, sem entrar em links nem em pastas sem acesso.
function Get-ArquivoCandidato {
    param([Parameter(Mandatory)][string]$Pasta)

    $saida = [pscustomobject]@{ Arquivos = @(); Incompleta = $false; PastasComOutros = @{} }
    $raiz = New-Object IO.DirectoryInfo $Pasta
    if (-not $raiz.Exists) { return $saida }
    $achados = [System.Collections.Generic.List[IO.FileInfo]]::new()
    $vistos = 0
    $fila = [System.Collections.Generic.Queue[object]]::new()
    $fila.Enqueue(@($raiz, 0))
    while ($fila.Count -gt 0) {
        $dir, $nivel = $fila.Dequeue()
        try { $itens = $dir.GetFileSystemInfos() } catch { continue }
        foreach ($i in $itens) {
            if ($i.Attributes -band [IO.FileAttributes]::ReparsePoint) { continue }
            if ($i -is [IO.DirectoryInfo]) {
                if ($nivel + 1 -lt $script:ProfundidadeMaxima) { $fila.Enqueue(@($i, ($nivel + 1))) }
                continue
            }
            $vistos++
            if ($vistos -gt $script:LimiteArquivos) { $saida.Incompleta = $true; $fila.Clear(); break }
            $extensao = $i.Extension.ToLowerInvariant()
            if ($script:Tipos.ContainsKey($extensao)) { $achados.Add($i) }
            elseif ($extensao -notin $script:ExtensoesInocentes) { $saida.PastasComOutros[$dir.FullName] = $true }
        }
    }
    # Agrupado por tipo (um cabeçalho por categoria na tela) e, dentro do tipo, do maior para o menor.
    $saida.Arquivos = @($achados | Sort-Object @{ Expression = { [array]::IndexOf($script:OrdemCategorias, $script:Tipos[$_.Extension.ToLowerInvariant()].Categoria) } }, @{ Expression = 'Length'; Descending = $true })
    $saida
}

function Format-Idade {
    param([int]$Dias)
    if ($Dias -le 0) { return 'baixado hoje' }
    if ($Dias -eq 1) { return 'baixado ontem' }
    if ($Dias -lt 60) { return "baixado há $Dias dias" }
    if ($Dias -lt 730) { return "baixado há $([int][Math]::Floor($Dias / 30)) meses" }
    "baixado há $([int][Math]::Floor($Dias / 365)) anos"
}

Export-ModuleMember -Function Test-Requisitos, Find-Alvos, Invoke-Acao
