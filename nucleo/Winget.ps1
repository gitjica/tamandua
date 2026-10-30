# winget: achar e, se faltar, instalar. Windows LTSC/IoT (e algumas instalações enxutas) vêm sem o "Instalador de
# Aplicativo" da Microsoft Store, que é quem traz o winget. Aqui ele é instalado pela versão oficial publicada no
# GitHub da Microsoft (microsoft/winget-cli), com as dependências, conferindo a assinatura digital antes.

# Caminho do winget, ou vazio. O alias fica em %LOCALAPPDATA%\Microsoft\WindowsApps, que nem sempre está no PATH
# deste processo (por exemplo, logo depois de instalar).
function Get-TmdCaminhoWinget {
    [CmdletBinding()]
    param()
    $c = Get-Command winget.exe -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($c) { return [string]$c.Source }
    $alias = Join-Path $env:LOCALAPPDATA 'Microsoft\WindowsApps\winget.exe'
    if (Test-Path -LiteralPath $alias -PathType Leaf) { return $alias }
    ''
}

function Test-TmdWinget {
    [CmdletBinding()]
    param()
    [bool](Get-TmdCaminhoWinget)
}

# Baixa (Mock nos testes). São ~300 MB (pacote ~210 MB + dependências ~90 MB): prazo de 30 min.
function Get-TmdDownloadWinget {
    param([Parameter(Mandatory)][string]$Url, [Parameter(Mandatory)][string]$Destino)
    [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
    $antes = $ProgressPreference
    $ProgressPreference = 'SilentlyContinue'   # a barra de progresso do Invoke-WebRequest deixa o download 10x mais lento
    try { Invoke-WebRequest -UseBasicParsing -Uri $Url -OutFile $Destino -UserAgent 'Tamandua' -TimeoutSec 1800 }
    finally { $ProgressPreference = $antes }
}

# Última versão publicada: endereços do pacote, das dependências e da licença (Mock nos testes).
function Get-TmdLancamentoWinget {
    $antes = $ProgressPreference
    $ProgressPreference = 'SilentlyContinue'
    try { $r = Invoke-RestMethod -Uri 'https://api.github.com/repos/microsoft/winget-cli/releases/latest' -UserAgent 'Tamandua' -TimeoutSec 60 }
    finally { $ProgressPreference = $antes }
    $achar = { param($padrao) @($r.assets | Where-Object { $_.name -like $padrao } | Select-Object -First 1 | ForEach-Object browser_download_url) }
    [pscustomobject]@{
        Versao       = [string]$r.tag_name
        Pacote       = [string]@(& $achar 'Microsoft.DesktopAppInstaller_8wekyb3d8bbwe.msixbundle')[0]
        Dependencias = [string]@(& $achar 'DesktopAppInstaller_Dependencies.zip')[0]
    }
}

# Instala o winget para o usuário atual. Já instalado: não faz nada. -Progresso: scriptblock que recebe o texto do passo.
function Install-TmdWinget {
    [CmdletBinding()]
    param([scriptblock]$Progresso = { param($t) Write-Verbose $t }, [string]$Modulo = 'programas')

    if (Test-TmdWinget) { return [pscustomobject]@{ Status = 'Feito'; Motivo = 'o winget já estava instalado' } }
    $pasta = Join-Path ([IO.Path]::GetTempPath()) "tamandua-winget-$([guid]::NewGuid().ToString('N'))"
    try {
        & $Progresso 'Procurando a versão mais nova do winget'
        $l = Get-TmdLancamentoWinget
        if (-not $l.Pacote -or -not $l.Dependencias) { throw 'não achei os arquivos do winget na página da Microsoft no GitHub' }
        [void][IO.Directory]::CreateDirectory($pasta)
        $pacote = Join-Path $pasta 'DesktopAppInstaller.msixbundle'
        $zip = Join-Path $pasta 'Dependencias.zip'
        & $Progresso "Baixando o winget $($l.Versao) (~210 MB)"
        Get-TmdDownloadWinget -Url $l.Pacote -Destino $pacote
        & $Progresso 'Baixando as dependências do winget (~90 MB)'
        Get-TmdDownloadWinget -Url $l.Dependencias -Destino $zip

        # Só instala o que a Microsoft assinou.
        $assinatura = Get-AuthenticodeSignature -LiteralPath $pacote
        if ($assinatura.Status -ne 'Valid' -or [string]$assinatura.SignerCertificate.Subject -notmatch 'O=Microsoft Corporation') {
            throw "o pacote baixado não tem a assinatura da Microsoft ($($assinatura.Status)); nada foi instalado"
        }

        & $Progresso 'Instalando o winget'
        $deps = Join-Path $pasta 'dependencias'
        Add-Type -AssemblyName System.IO.Compression.FileSystem
        [IO.Compression.ZipFile]::ExtractToDirectory($zip, $deps)
        $arq = switch ($env:PROCESSOR_ARCHITECTURE) { 'ARM64' { 'arm64' } 'x86' { 'x86' } default { 'x64' } }
        $dependencias = @(Get-ChildItem -LiteralPath $deps -Recurse -Filter '*.appx' | Where-Object { $_.FullName -match "\\$arq\\" -or $_.Name -match "_$($arq)_" } | ForEach-Object FullName)
        Add-AppxPackage -Path $pacote -DependencyPath $dependencias -ErrorAction Stop

        if (-not (Test-TmdWinget)) { throw 'o winget foi instalado, mas não respondeu; tente abrir o Tamanduá de novo' }
        Write-TmdOperacao -Modulo $Modulo -Id 'winget' -Acao 'instalar' -Caminho "winget $($l.Versao)" -Status 'Feito'
        [pscustomobject]@{ Status = 'Feito'; Motivo = "winget $($l.Versao) instalado" }
    }
    catch {
        $motivo = (Get-TmdExcecaoInterna $_.Exception).Message
        Write-TmdOperacao -Modulo $Modulo -Id 'winget' -Acao 'instalar' -Caminho 'winget' -Status 'Erro' -Motivo $motivo
        [pscustomobject]@{ Status = 'Erro'; Motivo = "não foi possível instalar o winget: $motivo" }
    }
    finally {
        # Só a pasta temporária que este instalador criou (tamandua-winget-*, direto na pasta temporária).
        $temp = [IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\')
        if ((Split-Path -Parent $pasta) -eq $temp -and (Split-Path -Leaf $pasta) -like 'tamandua-winget-*' -and (Test-Path -LiteralPath $pasta)) {
            Remove-Item -LiteralPath $pasta -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}
