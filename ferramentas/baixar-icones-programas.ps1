<#
.SYNOPSIS
    Baixa o ícone de cada programa de modulos\programas\programas.json para modulos\programas\icones\<id>.png
    (64x64). Ferramenta de desenvolvimento: o Tamanduá só lê os PNGs que já estão no projeto, nunca baixa nada.
.DESCRIPTION
    Fontes, na ordem: o ícone do pacote no Chocolatey (campo "choco" do catálogo) e o ícone do site do programa
    (campo "site", pelo serviço de favicons do Google, em 128 px). SVG fica de fora (o .NET não desenha SVG).
    Toda imagem baixada é decodificada e desenhada de novo num PNG limpo de 64x64: o que vai para o projeto nunca é
    o arquivo baixado. A origem de cada ícone fica em icones\fontes.json.
.EXAMPLE
    .\ferramentas\baixar-icones-programas.ps1            # só os que faltam
    .\ferramentas\baixar-icones-programas.ps1 -Forcar    # baixa todos de novo
    .\ferramentas\baixar-icones-programas.ps1 -Ids zoom  # só estes
#>
[CmdletBinding()]
param([switch]$Forcar, [string[]]$Ids)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$raiz = Split-Path -Parent $PSScriptRoot
$pasta = Join-Path $raiz 'modulos\programas\icones'
[void][IO.Directory]::CreateDirectory($pasta)
$arquivoFontes = Join-Path $pasta 'fontes.json'
$fontes = [ordered]@{}
if (Test-Path -LiteralPath $arquivoFontes) {
    $lido = [IO.File]::ReadAllText($arquivoFontes, [Text.Encoding]::UTF8) | ConvertFrom-Json
    foreach ($p in $lido.PSObject.Properties) { $fontes[$p.Name] = $p.Value }
}
# O Wikimedia recusa pedido sem um User-Agent que diga quem é.
$script:Agente = 'Tamandua-icones/1.0 (https://github.com/gitjica/tamandua)'

function Get-Bytes([string]$Url) {
    try {
        $r = Invoke-WebRequest -UseBasicParsing -Uri $Url -UserAgent $script:Agente -TimeoutSec 30
        if ($r.Content -is [byte[]]) { return , $r.Content }
        , [Text.Encoding]::UTF8.GetBytes([string]$r.Content)
    }
    catch { $null }
}

# URL do ícone do pacote no Chocolatey (a versão mais nova), ou vazio.
function Get-IconeChoco([string]$Pacote) {
    if (-not $Pacote) { return '' }
    $url = "https://community.chocolatey.org/api/v2/Packages()?`$filter=(tolower(Id)%20eq%20'$($Pacote.ToLowerInvariant())')%20and%20IsLatestVersion"
    $b = Get-Bytes $url
    if (-not $b) { return '' }
    try {
        $xml = [xml][Text.Encoding]::UTF8.GetString($b)
        $ns = New-Object Xml.XmlNamespaceManager($xml.NameTable)
        $ns.AddNamespace('d', 'http://schemas.microsoft.com/ado/2007/08/dataservices')
        $n = $xml.SelectSingleNode('//d:IconUrl', $ns)
        if ($n) { return [string]$n.InnerText }
    }
    catch { Write-Verbose "resposta do Chocolatey para $Pacote ilegível" }
    ''
}

# Ícones que a página do site declara (apple-touch-icon e <link rel="icon" sizes=...>), do maior para o menor.
function Get-IconesSite([string]$Site) {
    if (-not $Site) { return @() }
    $b = Get-Bytes $Site
    if (-not $b) { return @() }
    $html = [Text.Encoding]::UTF8.GetString($b)
    $achados = foreach ($m in [regex]::Matches($html, '<link\b[^>]*>', 'IgnoreCase')) {
        $tag = $m.Value
        if ($tag -notmatch 'rel\s*=\s*["'']?[^"''>]*(apple-touch-icon|icon)') { continue }
        if ($tag -notmatch 'href\s*=\s*["'']([^"'']+)["'']') { continue }
        $href = [Net.WebUtility]::HtmlDecode($Matches[1])
        if ($href -match '\.svg(\?|$)') { continue }
        $lado = if ($tag -match 'sizes\s*=\s*["'']?(\d+)x\d+') { [int]$Matches[1] } elseif ($tag -match 'apple-touch-icon') { 180 } else { 16 }
        try { [pscustomobject]@{ Url = ([uri]::new([uri]$Site, $href)).AbsoluteUri; Lado = $lado } }
        catch { Write-Verbose "endereço de ícone inválido em $Site`: $href" }
    }
    @($achados | Where-Object Lado -ge 48 | Sort-Object Lado -Descending | ForEach-Object Url | Select-Object -Unique)
}

# Bytes de imagem -> Bitmap (PNG, JPG, GIF, BMP ou ICO, pegando o maior tamanho do ICO). $null se não for imagem.
function ConvertTo-Bitmap([byte[]]$Bytes) {
    if (-not $Bytes -or $Bytes.Length -lt 16) { return $null }
    $texto = [Text.Encoding]::ASCII.GetString($Bytes, 0, [Math]::Min(256, $Bytes.Length))
    if ($texto -match '<svg|<\?xml|<html') { return $null }
    $ms = New-Object IO.MemoryStream(, $Bytes)
    try {
        if ($Bytes[0] -eq 0 -and $Bytes[1] -eq 0 -and $Bytes[2] -eq 1 -and $Bytes[3] -eq 0) {
            return (New-Object Drawing.Icon($ms, 256, 256)).ToBitmap()
        }
        $img = [Drawing.Image]::FromStream($ms)
        return New-Object Drawing.Bitmap($img)
    }
    catch { return $null }
}

# Desenha num PNG novo de 64x64, centralizado, sem distorcer.
function Save-Png64([Drawing.Bitmap]$Origem, [string]$Destino) {
    $lado = 64
    $escala = [Math]::Min($lado / $Origem.Width, $lado / $Origem.Height)
    $w = [int][Math]::Round($Origem.Width * $escala); $h = [int][Math]::Round($Origem.Height * $escala)
    $novo = New-Object Drawing.Bitmap($lado, $lado, [Drawing.Imaging.PixelFormat]::Format32bppArgb)
    $g = [Drawing.Graphics]::FromImage($novo)
    try {
        $g.Clear([Drawing.Color]::Transparent)
        $g.InterpolationMode = [Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
        $g.SmoothingMode = [Drawing.Drawing2D.SmoothingMode]::HighQuality
        $g.PixelOffsetMode = [Drawing.Drawing2D.PixelOffsetMode]::HighQuality
        $g.DrawImage($Origem, [int](($lado - $w) / 2), [int](($lado - $h) / 2), $w, $h)
        $novo.Save($Destino, [Drawing.Imaging.ImageFormat]::Png)
    }
    finally { $g.Dispose(); $novo.Dispose() }
}

# Onde o automático erra (site no GitHub dá o logo do GitHub, favicon de 16 px, nada no Chocolatey): endereços
# conferidos à mão, tentados antes de tudo. Special:FilePath do Wikimedia devolve o SVG já desenhado em PNG.
$script:Manuais = @{
    gimp           = @('https://commons.wikimedia.org/wiki/Special:FilePath/The_GIMP_icon_-_gnome.svg?width=128')
    '7zip'         = @('https://commons.wikimedia.org/wiki/Special:FilePath/7-Zip_Icon.svg?width=128')
    libreoffice    = @('https://commons.wikimedia.org/wiki/Special:FilePath/LibreOffice_icon_3.3.1_48_px.svg?width=128', 'https://commons.wikimedia.org/wiki/Special:FilePath/LibreOffice_Logo_Flat.svg?width=128')
    qtox           = @('https://commons.wikimedia.org/wiki/Special:FilePath/QTox_logo.svg?width=128', 'https://github.com/qTox.png?size=128')
    glazewm        = @('https://github.com/glzr-io.png?size=128')
    gsudo          = @('https://raw.githubusercontent.com/gerardog/gsudo/master/docs/static/img/gsudo.png', 'https://raw.githubusercontent.com/gerardog/gsudo/master/src/gsudo/icon/gsudo.ico')
    overwolf       = @('https://www.google.com/s2/favicons?domain=curseforge.com&sz=128')
    signalrgb      = @('https://github.com/SignalRGB.png?size=128')
    whatsapp       = @('https://commons.wikimedia.org/wiki/Special:FilePath/WhatsApp.svg?width=128')
    revo           = @('https://www.revouninstaller.com/apple-touch-icon.png', 'https://www.google.com/s2/favicons?domain=revouninstaller.com&sz=128')
    policyplus     = @('https://raw.githubusercontent.com/Fleex255/PolicyPlus/master/PolicyPlus/PolicyPlus.ico')
    blurautoclicker = @('https://github.com/Blur009.png?size=128')
}

$catalogo = @([IO.File]::ReadAllText((Join-Path $raiz 'modulos\programas\programas.json'), [Text.Encoding]::UTF8) | ConvertFrom-Json | ForEach-Object { $_ })
$faltaram = [System.Collections.Generic.List[string]]::new()
foreach ($p in $catalogo) {
    if ($Ids -and $Ids -notcontains $p.id) { continue }
    $destino = Join-Path $pasta "$($p.id).png"
    if ((Test-Path -LiteralPath $destino) -and -not $Forcar) { continue }
    $candidatos = [System.Collections.Generic.List[string]]::new()
    if ($script:Manuais.ContainsKey($p.id)) { foreach ($u in $script:Manuais[$p.id]) { $candidatos.Add($u) } }
    $choco =Get-IconeChoco ([string]$p.choco)
    if ($choco) { $candidatos.Add($choco) }
    foreach ($u in Get-IconesSite ([string]$p.site)) { $candidatos.Add($u) }
    # Site no GitHub: o favicon é o logo do GitHub, não o do programa. Melhor ficar sem (a tela mostra a inicial).
    if ($p.site -and $p.site -notmatch '^https?://(www\.)?github\.com/') { $candidatos.Add("https://www.google.com/s2/favicons?domain_url=$([uri]::EscapeDataString([string]$p.site))&sz=128") }
    $feito = $false
    foreach ($url in $candidatos) {
        $bmp = ConvertTo-Bitmap (Get-Bytes $url)
        if (-not $bmp) { continue }
        try {
            # Favicon minúsculo fica borrado; só aceita se não houver outra opção depois.
            if ($bmp.Width -lt 32 -and $url -ne $candidatos[-1]) { continue }
            Save-Png64 -Origem $bmp -Destino $destino
            $fontes[$p.id] = [ordered]@{ url = $url; tamanhoOriginal = "$($bmp.Width)x$($bmp.Height)" }
            $feito = $true
        }
        finally { $bmp.Dispose() }
        if ($feito) { break }
    }
    if ($feito) { Write-Host "ok    $($p.id)  ($($fontes[$p.id].tamanhoOriginal) de $(([uri]$fontes[$p.id].url).Host))" }
    else { $faltaram.Add($p.id); Write-Host "FALTA $($p.id)" -ForegroundColor Yellow }
}
[IO.File]::WriteAllText($arquivoFontes, (ConvertTo-Json -InputObject $fontes -Depth 3), (New-Object Text.UTF8Encoding $false))
if ($faltaram.Count -gt 0) { Write-Host "Sem ícone: $($faltaram -join ', ')" -ForegroundColor Yellow }
