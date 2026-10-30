# Decide se um caminho pode ser removido. Toda remoção passa por aqui antes (seção 7.1 do guia).
# Regra de ouro: na dúvida, recusa. Recusa nunca lança exceção; devolve o motivo.

# Pastas que não podem ser removidas nem ter um pai removido. O conteúdo delas pode (ex.: arquivos em Documentos de um projeto).
function Get-TmdPontoProtegido {
    $pastas = foreach ($nome in 'Windows', 'System', 'SystemX86', 'ProgramFiles', 'ProgramFilesX86', 'CommonApplicationData',
        'UserProfile', 'ApplicationData', 'LocalApplicationData', 'MyDocuments', 'Desktop', 'DesktopDirectory',
        'MyPictures', 'MyMusic', 'MyVideos', 'Favorites', 'StartMenu', 'Startup', 'Fonts') {
        [Environment]::GetFolderPath($nome)
    }
    $perfil = [Environment]::GetFolderPath('UserProfile')
    $outras = @(
        (Split-Path -Parent $perfil)                 # C:\Users
        (Join-Path $perfil 'Downloads')
        [IO.Path]::GetTempPath()
        $env:OneDrive, $env:OneDriveConsumer, $env:OneDriveCommercial
        $script:RaizPadrao
    )
    @($pastas) + $outras | Where-Object { $_ } | ForEach-Object { [IO.Path]::GetFullPath($_).TrimEnd('\') } | Select-Object -Unique
}

# Pastas cujo conteúdo inteiro é intocável, salvo as exceções.
function Get-TmdArvoreProtegida {
    $windows = [Environment]::GetFolderPath('Windows')
    $arvores = @(
        $windows
        [Environment]::GetFolderPath('ProgramFiles')
        [Environment]::GetFolderPath('ProgramFilesX86')
        $env:ProgramW6432
        [Environment]::GetFolderPath('MyPictures')
        [Environment]::GetFolderPath('MyMusic')
        [Environment]::GetFolderPath('MyVideos')
        $env:OneDrive, $env:OneDriveConsumer, $env:OneDriveCommercial
        $script:RaizPadrao
    )
    # Só pastas de descarte conhecidas, cada uma usada por uma categoria do limpar.
    $excecoes = @(
        (Join-Path $windows 'Temp')
        (Join-Path $windows 'SoftwareDistribution\Download')
        (Join-Path $windows 'Logs')
        (Join-Path $windows 'Minidump')
        (Join-Path $windows 'ServiceProfiles\NetworkService\AppData\Local\Microsoft\Windows\DeliveryOptimization\Cache')
    )
    $x86 = [Environment]::GetFolderPath('ProgramFilesX86')
    if ($x86) { foreach ($s in 'logs', 'dumps', 'appcache\httpcache') { $excecoes += Join-Path $x86 "Steam\$s" } }
    # Instaladores que o Windows Update reinstala sozinho (ajustes do WinUtil que os bloqueiam).
    $excecoes += Join-Path $windows 'Installer\Razer'
    foreach ($pf in @($env:ProgramW6432, [Environment]::GetFolderPath('ProgramFiles')) | Where-Object { $_ } | Select-Object -Unique) {
        $excecoes += Join-Path $pf 'LogiDownloadAssistant'
    }
    [pscustomobject]@{
        Arvores  = @($arvores | Where-Object { $_ } | ForEach-Object { [IO.Path]::GetFullPath($_).TrimEnd('\') } | Select-Object -Unique)
        Excecoes = @($excecoes | ForEach-Object { [IO.Path]::GetFullPath($_).TrimEnd('\') })
    }
}

# Arquivos do sistema que nunca são apagados, estejam onde estiverem.
$script:NomesProtegidos = @('pagefile.sys', 'hiberfil.sys', 'swapfile.sys', 'bootmgr', 'bootnxt', 'ntldr', 'boot.ini', 'bcd', 'bcd.log', 'ntuser.dat', 'usrclass.dat')

function Test-TmdNomeProtegido {
    param([string]$Caminho)
    $nome = [IO.Path]::GetFileName($Caminho).ToLowerInvariant()
    $nome -in $script:NomesProtegidos -or $nome -like 'ntuser.dat*' -or $nome -like 'usrclass.dat*'
}

function Test-TmdDentroDe {
    param([string]$Caminho, [string]$Pasta)
    $Caminho.StartsWith($Pasta + '\', [StringComparison]::OrdinalIgnoreCase)
}

function Test-TmdCaminhoSeguro {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][AllowEmptyString()][string]$Caminho,
        [Parameter(Mandatory)][string[]]$Raizes,
        # Padrões da lista de proteção; por padrão, lê a lista padrão + a do usuário.
        [string[]]$Protecao
    )

    $recusa = { param($m) [pscustomobject]@{ Ok = $false; Motivo = $m; Caminho = $Caminho } }

    if ([string]::IsNullOrWhiteSpace($Caminho)) { return & $recusa 'caminho vazio' }
    if ($Caminho.IndexOfAny([char[]]'*?') -ge 0) { return & $recusa 'caminho com curinga' }
    if ($Caminho.StartsWith('\\')) { return & $recusa 'caminho de rede ou de dispositivo não é aceito' }
    if ($Caminho -notmatch '^[A-Za-z]:\\') { return & $recusa 'o caminho precisa ser absoluto (ex.: C:\...)' }

    try { $completo = [IO.Path]::GetFullPath($Caminho).TrimEnd('\') }
    catch { return & $recusa "caminho inválido: $($_.Exception.Message)" }
    $recusa = { param($m) [pscustomobject]@{ Ok = $false; Motivo = $m; Caminho = $completo } }

    if ($completo.Length -le 2) { return & $recusa 'raiz de unidade' }
    if (Test-TmdNomeProtegido $completo) { return & $recusa 'arquivo do sistema que nunca é apagado' }

    # 1. Dentro de uma raiz permitida (e nunca a própria raiz).
    $raiz = $null
    foreach ($r in $Raizes) {
        if (-not $r) { continue }
        $rc = [IO.Path]::GetFullPath($r).TrimEnd('\')
        if (Test-TmdDentroDe $completo $rc) { $raiz = $rc; break }
    }
    if (-not $raiz) { return & $recusa 'fora das pastas permitidas para esta ação' }

    # 2. Não é pasta protegida nem pai de uma.
    foreach ($p in Get-TmdPontoProtegido) {
        if ($completo -eq $p -or (Test-TmdDentroDe $p $completo)) { return & $recusa "pasta protegida ($p)" }
    }
    $arvores = Get-TmdArvoreProtegida
    foreach ($a in $arvores.Arvores) {
        if (Test-TmdDentroDe $completo $a) {
            $liberado = @($arvores.Excecoes | Where-Object { Test-TmdDentroDe $completo $_ }).Count -gt 0
            if (-not $liberado) { return & $recusa "dentro de pasta protegida ($a)" }
        }
    }

    # 3. Nenhum link no caminho entre a raiz e o alvo: seguir um junction é como limpadores apagam a pasta errada.
    $atual = $completo
    while ($atual.Length -gt $raiz.Length) {
        $item = Get-Item -LiteralPath $atual -Force -ErrorAction SilentlyContinue
        if ($item -and ($item.Attributes -band [IO.FileAttributes]::ReparsePoint)) {
            return & $recusa "passa por um link ($atual); o Tamanduá não segue nem apaga links"
        }
        $atual = Split-Path -Parent $atual
    }

    # 4. Lista de proteção (padrão + usuário).
    if (-not $PSBoundParameters.ContainsKey('Protecao')) { $Protecao = @(Get-TmdListaProtecao) }
    foreach ($padrao in $Protecao) {
        if ($completo -like $padrao) { return & $recusa "está na lista de proteção ($padrao)" }
    }

    [pscustomobject]@{ Ok = $true; Motivo = ''; Caminho = $completo }
}
