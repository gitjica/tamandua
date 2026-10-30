# Limpeza por categorias: temporários, relatórios de falha e logs, caches do Windows, navegadores (só cache),
# programas, lançadores de jogos e Lixeira. Várias categorias vieram do swept (github.com/vladcodex/swept).
# Cada categoria vira um alvo. Quem apaga é o núcleo (Remove-TmdItem), sempre com a pasta da categoria como
# única raiz permitida; a Lixeira é esvaziada pelo núcleo (Clear-TmdLixeira).

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Pastas de cache de cada perfil do Chrome, Edge e Brave (todos Chromium).
$script:CachesChromium = 'Cache', 'Code Cache', 'GPUCache', 'Media Cache'
$script:ExplicacaoNavegador = 'Só o cache (páginas, imagens e scripts guardados). Histórico, senhas, cookies e logins ficam como estão. O navegador precisa estar fechado.'

# Nova categoria = nova entrada aqui + testes. Pastas recebe as bases (ver Get-Bases) e devolve uma ou mais pastas.
# Campos opcionais: Padrao (vem marcada), Risco, RequerAdmin, IdadeMinimaHoras, Filtro (só arquivos com esses nomes,
# em qualquer subpasta), Programa + Processos (fechado para limpar), SoSeExistir (some se nenhuma pasta existir).
$script:Categorias = @(
    @{
        Id = 'temp-usuario'; Nome = 'Temporários do usuário'; Categoria = 'Temporários'; Padrao = $true; IdadeMinimaHoras = 24
        Pastas = { param($b) $b.Temp }
        Explicacao = 'Arquivos temporários deixados por programas e instaladores. O que foi mexido nas últimas 24 horas fica, porque pode estar em uso.'
    }
    @{
        Id = 'temp-windows'; Nome = 'Temporários do Windows'; Categoria = 'Temporários'; Padrao = $true; IdadeMinimaHoras = 24; RequerAdmin = $true
        Pastas = { param($b) Join-Path $b.Windows 'Temp' }
        Explicacao = 'Temporários de serviços e instaladores que rodam como sistema. O que foi mexido nas últimas 24 horas fica.'
    }
    @{
        Id = 'crashdumps'; Nome = 'Despejos de falha'; Categoria = 'Relatórios de falha e logs'; Padrao = $true
        Pastas = { param($b) Join-Path $b.Local 'CrashDumps' }
        Explicacao = 'Cópias da memória de programas que travaram. Só servem para quem for investigar o travamento.'
    }
    @{
        Id = 'relatorios-erro'; Nome = 'Relatórios de erro'; Categoria = 'Relatórios de falha e logs'; Padrao = $true
        Pastas = { param($b) foreach ($s in 'ReportArchive', 'ReportQueue') { Join-Path $b.Local "Microsoft\Windows\WER\$s" } }
        Explicacao = 'Relatórios que o Windows guarda quando um programa trava, já enviados ou que não serão enviados.'
    }
    @{
        Id = 'relatorios-erro-sistema'; Nome = 'Relatórios de erro do sistema'; Categoria = 'Relatórios de falha e logs'; Padrao = $true; RequerAdmin = $true
        Pastas = { param($b) foreach ($s in 'ReportArchive', 'ReportQueue') { Join-Path $b.ProgramData "Microsoft\Windows\WER\$s" } }
        Explicacao = 'Os mesmos relatórios de erro, de serviços e programas que rodam para todos os usuários.'
    }
    @{
        Id = 'minidump'; Nome = 'Despejos de tela azul'; Categoria = 'Relatórios de falha e logs'; RequerAdmin = $true
        Pastas = { param($b) Join-Path $b.Windows 'Minidump' }
        Explicacao = 'Arquivos gravados quando o Windows trava com tela azul. Guarde se ainda estiver investigando uma tela azul.'
    }
    @{
        Id = 'logs-windows'; Nome = 'Logs antigos do Windows'; Categoria = 'Relatórios de falha e logs'; RequerAdmin = $true; IdadeMinimaHoras = 168; Filtro = @('*.log')
        Pastas = { param($b) Join-Path $b.Windows 'Logs' }
        Explicacao = 'Arquivos .log com mais de 7 dias em Windows\Logs (atualizações, DISM, CBS...). Só servem para diagnosticar problemas antigos.'
    }
    @{
        Id = 'windows-update'; Nome = 'Downloads do Windows Update'; Categoria = 'Caches do Windows'; RequerAdmin = $true; IdadeMinimaHoras = 168
        Pastas = { param($b) Join-Path $b.Windows 'SoftwareDistribution\Download' }
        Explicacao = 'Pacotes de atualizações já baixados, com mais de 7 dias. Uma atualização ainda pendente pode precisar ser baixada de novo.'
    }
    @{
        Id = 'otimizacao-entrega'; Nome = 'Cache da Otimização de Entrega'; Categoria = 'Caches do Windows'; Padrao = $true; RequerAdmin = $true
        Pastas = { param($b) Join-Path $b.Windows 'ServiceProfiles\NetworkService\AppData\Local\Microsoft\Windows\DeliveryOptimization\Cache' }
        Explicacao = 'Pedaços de atualizações guardados para compartilhar com outros PCs. O Windows baixa de novo se precisar.'
    }
    @{
        Id = 'shaders'; Nome = 'Cache de shaders da placa de vídeo'; Categoria = 'Caches do Windows'; Risco = 'Medio'; SoSeExistir = $true
        Pastas = { param($b) foreach ($s in 'D3DSCache', 'NVIDIA\DXCache', 'NVIDIA\GLCache', 'AMD\DxCache', 'AMD\DxcCache', 'Intel\ShaderCache') { Join-Path $b.Local $s } }
        Explicacao = 'Shaders já compilados por jogos e programas. São recriados sozinhos, mas os jogos podem engasgar nas primeiras partidas. Útil depois de trocar o driver de vídeo.'
    }
    @{
        Id = 'chrome'; Nome = 'Google Chrome'; Categoria = 'Navegadores (só cache)'; Padrao = $true; SoSeExistir = $true; Programa = 'o Chrome'; Processos = @('chrome')
        Pastas = { param($b) Get-PastaCacheChromium (Join-Path $b.Local 'Google\Chrome\User Data') }
        Explicacao = $script:ExplicacaoNavegador
    }
    @{
        Id = 'edge'; Nome = 'Microsoft Edge'; Categoria = 'Navegadores (só cache)'; Padrao = $true; SoSeExistir = $true; Programa = 'o Edge'; Processos = @('msedge')
        Pastas = { param($b) Get-PastaCacheChromium (Join-Path $b.Local 'Microsoft\Edge\User Data') }
        Explicacao = $script:ExplicacaoNavegador + ' O Edge costuma ficar aberto em segundo plano: desligue "Aumento de desempenho na inicialização" nas configurações dele.'
    }
    @{
        Id = 'brave'; Nome = 'Brave'; Categoria = 'Navegadores (só cache)'; Padrao = $true; SoSeExistir = $true; Programa = 'o Brave'; Processos = @('brave')
        Pastas = { param($b) Get-PastaCacheChromium (Join-Path $b.Local 'BraveSoftware\Brave-Browser\User Data') }
        Explicacao = $script:ExplicacaoNavegador
    }
    @{
        Id = 'firefox'; Nome = 'Mozilla Firefox'; Categoria = 'Navegadores (só cache)'; Padrao = $true; SoSeExistir = $true; Programa = 'o Firefox'; Processos = @('firefox')
        Pastas = { param($b) Get-PastaCacheFirefox (Join-Path $b.Local 'Mozilla\Firefox\Profiles') }
        Explicacao = $script:ExplicacaoNavegador
    }
    @{
        Id = 'discord'; Nome = 'Discord'; Categoria = 'Programas'; Padrao = $true; SoSeExistir = $true; Programa = 'o Discord'; Processos = @('Discord', 'DiscordCanary', 'DiscordPTB')
        Pastas = { param($b) foreach ($v in 'discord', 'discordcanary', 'discordptb') { foreach ($s in 'Cache', 'Code Cache', 'GPUCache') { Join-Path $b.Roaming "$v\$s" } } }
        Explicacao = 'Imagens, vídeos e scripts guardados pelo Discord. Conversas e configurações ficam.'
    }
    @{
        Id = 'spotify'; Nome = 'Spotify'; Categoria = 'Programas'; Padrao = $true; SoSeExistir = $true; Programa = 'o Spotify'; Processos = @('Spotify')
        Pastas = {
            param($b)
            Join-Path $b.Local 'Spotify\Data'
            Get-SubpastaComo -Pasta (Join-Path $b.Local 'Packages') -Padrao 'SpotifyAB.SpotifyMusic_*' -Sufixo 'LocalCache\Spotify\Data'
        }
        Explicacao = 'Músicas guardadas enquanto você ouve (cache de streaming). As baixadas para ouvir offline ficam.'
    }
    @{
        Id = 'steam'; Nome = 'Steam'; Categoria = 'Lançadores de jogos'; Padrao = $true; SoSeExistir = $true; Programa = 'a Steam'; Processos = @('steam')
        Pastas = { param($b) if ($b.Steam) { foreach ($s in 'logs', 'dumps', 'appcache\httpcache') { Join-Path $b.Steam $s } } }
        Explicacao = 'Logs, relatórios de falha e cache das páginas da loja. Jogos, saves e downloads não são tocados.'
    }
    @{
        Id = 'epic'; Nome = 'Epic Games'; Categoria = 'Lançadores de jogos'; Padrao = $true; SoSeExistir = $true; Programa = 'a Epic Games'; Processos = @('EpicGamesLauncher')
        Pastas = {
            param($b)
            Join-Path $b.Local 'EpicGamesLauncher\Saved\Logs'
            Get-SubpastaComo -Pasta (Join-Path $b.Local 'EpicGamesLauncher\Saved') -Padrao 'webcache*'
        }
        Explicacao = 'Logs e cache das páginas da loja. Jogos não são tocados.'
    }
    @{
        Id = 'battlenet'; Nome = 'Battle.net'; Categoria = 'Lançadores de jogos'; Padrao = $true; SoSeExistir = $true; Programa = 'o Battle.net'; Processos = @('Battle.net')
        Pastas = { param($b) Join-Path $b.Local 'Battle.net\Cache' }
        Explicacao = 'Cache do aplicativo da Blizzard. Jogos não são tocados.'
    }
    @{
        Id = 'ubisoft'; Nome = 'Ubisoft Connect'; Categoria = 'Lançadores de jogos'; Padrao = $true; SoSeExistir = $true; Programa = 'o Ubisoft Connect'; Processos = @('upc', 'UbisoftConnect')
        Pastas = { param($b) Join-Path $b.Local 'Ubisoft Game Launcher\cache' }
        Explicacao = 'Cache do aplicativo da Ubisoft. Jogos não são tocados.'
    }
    @{
        Id = 'lixeira'; Nome = 'Esvaziar a Lixeira'; Categoria = 'Lixeira'; Especial = 'Lixeira'
        Pastas = { }
        Explicacao = 'Apaga de vez o que está na Lixeira, em todas as unidades. Não tem volta: confira antes o que há nela.'
    }
)

# Campos opcionais com o valor padrão, para o resto do código não precisar testar cada um.
$script:PadraoCategoria = @{ Padrao = $false; Risco = 'Baixo'; RequerAdmin = $false; IdadeMinimaHoras = 0; Filtro = @(); Programa = ''; Processos = @(); SoSeExistir = $false; Especial = '' }
foreach ($c in $script:Categorias) { foreach ($k in $script:PadraoCategoria.Keys) { if (-not $c.ContainsKey($k)) { $c[$k] = $script:PadraoCategoria[$k] } } }

function Test-Requisitos {
    @{ Ok = $true; Motivo = '' }
}

# Pastas-base das categorias. Testes: TAMANDUA_LIMPAR_RAIZ (dentro da pasta temporária real do usuário) troca todas
# por subpastas dela (Windows, ProgramData, Local, Roaming, Steam) e nada pede admin; o TEMP segue o do processo.
function Get-Bases {
    $teste = $env:TAMANDUA_LIMPAR_RAIZ
    if ($teste) {
        $tempReal = Join-Path ([Environment]::GetFolderPath('LocalApplicationData')) 'Temp'
        $teste = [IO.Path]::GetFullPath($teste).TrimEnd('\')
        if (-not $teste.StartsWith($tempReal + '\', [StringComparison]::OrdinalIgnoreCase)) { throw 'TAMANDUA_LIMPAR_RAIZ precisa estar dentro da pasta temporária' }
        return @{
            Teste = $true; Temp = [IO.Path]::GetTempPath(); Windows = "$teste\Windows"; ProgramData = "$teste\ProgramData"
            Local = "$teste\Local"; Roaming = "$teste\Roaming"; Steam = "$teste\Steam"
        }
    }
    @{
        Teste = $false; Temp = [IO.Path]::GetTempPath(); Windows = [Environment]::GetFolderPath('Windows'); ProgramData = $env:ProgramData
        Local = $env:LOCALAPPDATA; Roaming = $env:APPDATA; Steam = Get-PastaSteam
    }
}

# Onde a Steam está instalada (o registro dela diz; senão, o lugar padrão).
function Get-PastaSteam {
    try {
        $p = (Get-ItemProperty -LiteralPath 'HKCU:\Software\Valve\Steam' -Name SteamPath -ErrorAction Stop).SteamPath
        if ($p) { return [IO.Path]::GetFullPath(($p -replace '/', '\')).TrimEnd('\') }
    }
    catch { Write-Verbose 'Steam não está no registro' }
    $x86 = [Environment]::GetFolderPath('ProgramFilesX86')
    if ($x86) { Join-Path $x86 'Steam' }
}

# Perfis do navegador: "Default", "Profile N" ou qualquer pasta com o arquivo Preferences. Links são ignorados.
function Get-PastaCacheChromium {
    param([string]$Dados)
    if (-not [IO.Directory]::Exists($Dados)) { return }
    foreach ($perfil in ([IO.DirectoryInfo]::new($Dados)).GetDirectories()) {
        if ($perfil.Attributes -band [IO.FileAttributes]::ReparsePoint) { continue }
        if ($perfil.Name -ne 'Default' -and $perfil.Name -notmatch '^Profile \d+$' -and -not [IO.File]::Exists((Join-Path $perfil.FullName 'Preferences'))) { continue }
        foreach ($s in $script:CachesChromium) { Join-Path $perfil.FullName $s }
    }
}

function Get-PastaCacheFirefox {
    param([string]$Perfis)
    if (-not [IO.Directory]::Exists($Perfis)) { return }
    foreach ($perfil in ([IO.DirectoryInfo]::new($Perfis)).GetDirectories()) {
        if ($perfil.Attributes -band [IO.FileAttributes]::ReparsePoint) { continue }
        foreach ($s in 'cache2', 'startupCache', 'thumbnails') { Join-Path $perfil.FullName $s }
    }
}

# Subpastas de -Pasta cujo nome bate com -Padrao (mais -Sufixo, se houver). Links são ignorados.
function Get-SubpastaComo {
    param([string]$Pasta, [string]$Padrao, [string]$Sufixo = '')
    if (-not [IO.Directory]::Exists($Pasta)) { return }
    foreach ($d in ([IO.DirectoryInfo]::new($Pasta)).GetDirectories($Padrao)) {
        if ($d.Attributes -band [IO.FileAttributes]::ReparsePoint) { continue }
        if ($Sufixo) { Join-Path $d.FullName $Sufixo } else { $d.FullName }
    }
}

# Nomes dos processos da categoria que estão abertos agora (Mock nos testes).
function Get-ProcessoAberto {
    param([string[]]$Nomes)
    if (-not $Nomes -or $Nomes.Count -eq 0) { return @() }
    @(Get-Process -Name $Nomes -ErrorAction SilentlyContinue | ForEach-Object ProcessName | Select-Object -Unique)
}

# -Pastas troca as pastas de uma categoria (por Id). Usado pelos testes.
function Resolve-PastaCategoria {
    param([Parameter(Mandatory)][hashtable]$Categoria, [hashtable]$Pastas, [hashtable]$Bases)
    $lista = if ($Pastas -and $Pastas.ContainsKey($Categoria.Id)) { @($Pastas[$Categoria.Id]) } else { @(& $Categoria.Pastas $Bases) }
    @($lista | Where-Object { $_ } | ForEach-Object { [IO.Path]::GetFullPath($_).TrimEnd('\') } | Select-Object -Unique)
}

function Find-Alvos {
    param([hashtable]$Pastas = @{})

    $bases = Get-Bases
    $admin = Test-TmdAdministrador
    foreach ($c in $script:Categorias) {
        if ($c.Especial -eq 'Lixeira') { New-AlvoLixeira -Categoria $c; continue }
        $todas = Resolve-PastaCategoria -Categoria $c -Pastas $Pastas -Bases $bases
        $existentes = @($todas | Where-Object { [IO.Directory]::Exists($_) })
        if ($c.SoSeExistir -and $existentes.Count -eq 0) { continue }
        $requerAdmin = $c.RequerAdmin -and -not $bases.Teste
        # Sem admin, o Windows esconde algumas dessas pastas (parecem não existir): o tamanho fica para quando limpar.
        $invisivel = $requerAdmin -and -not $admin -and $existentes.Count -eq 0

        $quantidade = 0; $recentes = 0; $links = 0; $semAcesso = 0; $bytes = [int64]0
        foreach ($p in $existentes) {
            $itens = Get-ItemElegivel -Pasta $p -IdadeMinimaHoras $c.IdadeMinimaHoras -Filtro $c.Filtro
            if ($itens.SemAcesso) { $semAcesso++; continue }
            $quantidade += $itens.Elegiveis.Count
            $recentes += $itens.Recentes
            $links += $itens.Links
            # Sem filtro de idade nem de nome, o que sai é a pasta inteira: mede de uma vez (mais rápido).
            if ($c.IdadeMinimaHoras -eq 0 -and $c.Filtro.Count -eq 0) { $bytes += (Measure-TmdTamanho -Caminho $p).Bytes }
            else { foreach ($i in $itens.Elegiveis) { $bytes += (Measure-TmdTamanho -Caminho $i.FullName).Bytes } }
        }

        $abertos = @(Get-ProcessoAberto -Nomes $c.Processos)
        $detalhe = if ($invisivel -or ($semAcesso -gt 0 -and $quantidade -eq 0)) { 'o tamanho só aparece rodando como administrador' }
        elseif ($existentes.Count -eq 0) { 'pasta não existe' }
        elseif ($quantidade -eq 0) { 'nada para limpar' }
        else { "$(Format-TmdTamanho $bytes) em $(Format-Quantidade $quantidade)" }
        if ($recentes -gt 0) { $detalhe += " · $recentes recente(s) mantido(s)" }
        if ($abertos.Count -gt 0) { $detalhe = "feche $($c.Programa) para limpar · $detalhe" }

        $onde = if ($existentes.Count -gt 0) { $existentes } else { $todas }
        $mudancas = @("Apaga $(if ($invisivel) { 'o conteúdo' } else { Format-Quantidade $quantidade }) dentro de: $($onde -join '; ')", $c.Explicacao)
        if ($links -gt 0) { $mudancas += "$links link(s) ignorado(s): o Tamanduá não segue links" }
        $temAlgo = $quantidade -gt 0 -or $invisivel -or ($semAcesso -gt 0 -and $requerAdmin)

        [pscustomobject]@{
            Id           = $c.Id
            Nome         = $c.Nome
            Categoria    = $c.Categoria
            Caminho      = @($existentes + $todas)[0]
            Tamanho      = $bytes
            Estado       = 'NaoSeAplica'
            Detalhe      = $detalhe
            Nivel        = 'Normal'
            Valor        = $null
            Risco        = $c.Risco
            Selecionado  = $c.Padrao -and $temAlgo -and $abertos.Count -eq 0
            Selecionavel = $abertos.Count -eq 0
            Destino      = 'Permanente'
            RequerAdmin  = $requerAdmin
            Reversivel   = $false
            Mudancas     = $mudancas
        }
    }
}

function New-AlvoLixeira {
    param([Parameter(Mandatory)][hashtable]$Categoria)
    $bytes = [int64]0
    try {
        $l = Get-TmdLixeira
        $bytes = $l.Bytes
        $detalhe = if ($l.Itens -eq 0) { 'vazia' } else { "$(Format-TmdTamanho $l.Bytes) em $(Format-Quantidade ([int]$l.Itens))" }
    }
    catch { $detalhe = "não foi possível ler: $($_.Exception.Message)" }
    [pscustomobject]@{
        Id = $Categoria.Id; Nome = $Categoria.Nome; Categoria = $Categoria.Categoria; Caminho = ''; Tamanho = $bytes
        Estado = 'NaoSeAplica'; Detalhe = $detalhe; Nivel = 'Normal'; Valor = $null; Risco = 'Medio'
        Selecionado = $false; Selecionavel = $true; Destino = 'Permanente'; RequerAdmin = $false; Reversivel = $false
        Mudancas = @('Esvazia a Lixeira de todas as unidades.', $Categoria.Explicacao)
    }
}

# Não confia no Caminho dos alvos recebidos: as pastas são sempre as da categoria (ou as de -Pastas, nos testes).
function Invoke-Acao {
    param(
        [Parameter(Mandatory)][AllowEmptyCollection()][object[]]$Alvos,
        [switch]$Simular,
        [hashtable]$Pastas = @{}
    )

    $bases = Get-Bases
    foreach ($a in $Alvos) {
        $categoria = @($script:Categorias | Where-Object { $_.Id -eq $a.Id })
        if ($categoria.Count -eq 0) {
            [pscustomobject]@{ Id = $a.Id; Status = 'Erro'; Liberado = [int64]0; Itens = 0; Motivo = 'categoria desconhecida' }
            continue
        }
        $c = $categoria[0]
        if ($c.Especial -eq 'Lixeira') {
            $r = Clear-TmdLixeira -Simular:$Simular -Modulo 'limpar' -Id $c.Id
            [pscustomobject]@{ Id = $c.Id; Status = $r.Status; Liberado = $r.Liberado; Itens = 1; Motivo = $r.Motivo }
            continue
        }
        # Programa aberto segura os arquivos e pode estragar o próprio cache: só limpa com ele fechado.
        $abertos = @(Get-ProcessoAberto -Nomes $c.Processos)
        if ($abertos.Count -gt 0 -and -not $Simular) {
            [pscustomobject]@{ Id = $c.Id; Status = 'Ignorado'; Liberado = [int64]0; Itens = 0; Motivo = "feche $($c.Programa) e tente de novo" }
            continue
        }
        $resultados = @(foreach ($pasta in Resolve-PastaCategoria -Categoria $c -Pastas $Pastas -Bases $bases) {
                if (-not [IO.Directory]::Exists($pasta)) { continue }
                $itens = Get-ItemElegivel -Pasta $pasta -IdadeMinimaHoras $c.IdadeMinimaHoras -Filtro $c.Filtro
                foreach ($i in $itens.Elegiveis) {
                    Remove-TmdItem -Caminho $i.FullName -Raizes $pasta -Modulo 'limpar' -Id $c.Id -Simular:$Simular
                }
            })
        Join-Resultado -Id $c.Id -Resultados $resultados -Simular $Simular
    }
}

# Itens que podem ser apagados: sem links e mais velhos que a idade mínima. Sem -Filtro, os do primeiro nível da
# pasta (subpastas inteiras); com -Filtro, só os arquivos com esses nomes, em qualquer subpasta.
function Get-ItemElegivel {
    param([Parameter(Mandatory)][string]$Pasta, [int]$IdadeMinimaHoras, [string[]]$Filtro = @())

    $saida = [pscustomobject]@{ Existe = $false; SemAcesso = $false; Elegiveis = @(); Recentes = 0; Links = 0 }
    $dir = New-Object IO.DirectoryInfo($Pasta)
    if (-not $dir.Exists) { return $saida }
    $saida.Existe = $true
    $limite = (Get-Date).AddHours(-$IdadeMinimaHoras)
    $elegiveis = [System.Collections.Generic.List[object]]::new()
    $pendentes = [System.Collections.Generic.Stack[IO.DirectoryInfo]]::new()
    $pendentes.Push($dir)
    while ($pendentes.Count -gt 0) {
        $atual = $pendentes.Pop()
        try { $filhos = $atual.GetFileSystemInfos() }
        catch {
            if ($atual -eq $dir) { $saida.SemAcesso = $true }
            Write-Verbose "não foi possível listar $($atual.FullName): $($_.Exception.Message)"
            continue
        }
        foreach ($i in $filhos) {
            if ($i.Attributes -band [IO.FileAttributes]::ReparsePoint) { $saida.Links++; continue }
            if ($Filtro.Count -gt 0) {
                if ($i -is [IO.DirectoryInfo]) { $pendentes.Push($i); continue }
                $bate = $false
                foreach ($f in $Filtro) { if ($i.Name -like $f) { $bate = $true; break } }
                if (-not $bate) { continue }
            }
            if ($IdadeMinimaHoras -gt 0 -and $i.LastWriteTime -gt $limite) { $saida.Recentes++; continue }
            $elegiveis.Add($i)
        }
    }
    $saida.Elegiveis = $elegiveis.ToArray()
    $saida
}

# Um resultado por categoria, somando os resultados de cada item.
function Join-Resultado {
    param([string]$Id, [object[]]$Resultados, [bool]$Simular)

    $liberado = [int64]0
    foreach ($r in $Resultados) { $liberado += $r.Liberado }
    $feitos = @($Resultados | Where-Object { $_.Status -in 'Feito', 'Simulado' -or $_.Motivo -eq 'não existe mais' })
    $parciais = @($Resultados | Where-Object { $_.Status -eq 'Parcial' })
    $erros = @($Resultados | Where-Object { $_.Status -eq 'Erro' })
    $pulados = $Resultados.Count - $feitos.Count

    $status = if ($Simular) { 'Simulado' }
    elseif ($pulados -eq 0) { 'Feito' }
    elseif ($feitos.Count + $parciais.Count -gt 0) { 'Parcial' }
    elseif ($erros.Count -gt 0) { 'Erro' }
    else { 'Ignorado' }

    $motivo = ''
    if ($pulados -gt 0) {
        $exemplo = @($Resultados | Where-Object { $_.Status -notin 'Feito', 'Simulado' -and $_.Motivo -ne 'não existe mais' })[0].Motivo
        $motivo = "$pulados pulado(s) (ex.: $exemplo)"
    }
    [pscustomobject]@{ Id = $Id; Status = $status; Liberado = $liberado; Itens = $Resultados.Count; Motivo = $motivo }
}

function Format-Quantidade {
    param([int]$Quantidade)
    if ($Quantidade -eq 1) { return '1 item' }
    '{0:N0} itens' -f $Quantidade
}

Export-ModuleMember -Function Test-Requisitos, Find-Alvos, Invoke-Acao
