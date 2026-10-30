<#
.SYNOPSIS
    Gera modulos\programas\programas.json a partir da lista de programas do WinUtil (config/applications.json),
    com nome, descrição e categoria em português. Ferramenta de desenvolvimento: o programa nunca roda isto.
.DESCRIPTION
    Entra tudo do WinUtil, menos a parte de desenvolvimento, que fica só com o básico (editores, Python, Node, Git):
    o Tamanduá não é para quem programa por profissão. A lista do WinUtil vai para a pasta de testes
    (winutil-apps.json), e um teste confere que nada dela ficou de fora sem estar em $ForaDeProposito.
.EXAMPLE
    .\ferramentas\gerar-programas.ps1 -WinUtil C:\temp\applications.json
#>
[CmdletBinding()]
param([Parameter(Mandatory)][string]$WinUtil)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$raiz = Split-Path -Parent $PSScriptRoot

# Desenvolvimento: só o que alguém que está começando usaria.
$script:DevBasico = 'vscode', 'vscodium', 'Zed', 'sublimetext', 'notepadplus', 'python3', 'nodejslts', 'git', 'githubdesktop',
'cursor', 'claude', 'chatgpt', 'visualstudio2026'

# Ids que já existiam (mantidos: o histórico e a linha de comando usam).
$script:IdsAntigos = @{
    'Mozilla.Firefox' = 'firefox'; 'Brave.Brave' = 'brave'; 'LibreWolf.LibreWolf' = 'librewolf'; 'Google.Chrome' = 'chrome'
    '7zip.7zip' = '7zip'; 'voidtools.Everything' = 'everything'; 'Microsoft.PowerToys' = 'powertoys'; 'AntibodySoftware.WizTree' = 'wiztree'
    'ShareX.ShareX' = 'sharex'; 'LocalSend.LocalSend' = 'localsend'; 'qBittorrent.qBittorrent' = 'qbittorrent'; 'Bitwarden.Bitwarden' = 'bitwarden'
    'KeePassXCTeam.KeePassXC' = 'keepassxc'; 'Git.Git' = 'git'; 'Microsoft.VisualStudioCode' = 'vscode'; 'Notepad++.Notepad++' = 'notepadpp'
    'Python.Python.3.14' = 'python'; 'OpenJS.NodeJS.LTS' = 'nodejs'; 'Microsoft.WindowsTerminal' = 'terminal'; 'VideoLAN.VLC' = 'vlc'
    'OBSProject.OBSStudio' = 'obs'; 'GIMP.GIMP.3' = 'gimp'; 'HandBrake.HandBrake' = 'handbrake'; 'Audacity.Audacity' = 'audacity'
    'Discord.Discord' = 'discord'; 'Telegram.TelegramDesktop' = 'telegram'; 'Zoom.Zoom' = 'zoom'; 'TheDocumentFoundation.LibreOffice' = 'libreoffice'
    'ONLYOFFICE.DesktopEditors' = 'onlyoffice'; 'SumatraPDF.SumatraPDF' = 'sumatrapdf'; 'Obsidian.Obsidian' = 'obsidian'; 'Valve.Steam' = 'steam'
    'HeroicGamesLauncher.HeroicGamesLauncher' = 'heroic'; 'EpicGames.EpicGamesLauncher' = 'epic'
}

$script:Categorias = [ordered]@{
    'Browsers' = 'Navegadores'; 'Communications' = 'Comunicação'; 'Multimedia Tools' = 'Multimídia'; 'Document' = 'Documentos'
    'Utilities' = 'Utilitários'; 'Games' = 'Jogos'; 'Development' = 'Desenvolvimento'; 'Microsoft Tools' = 'Ferramentas da Microsoft'
    'Pro Tools' = 'Ferramentas avançadas'; 'Selfhosted Tools' = 'Servidor em casa'
}

# Nome como aparece na tela (sem o "(Music Player)" e afins do WinUtil), quando muda.
$script:Nomes = @{
    aimp = 'AIMP'; blender = 'Blender'; eartrumpet = 'EarTrumpet'; foobar = 'foobar2000'; gimp = 'GIMP'; imageglass = 'ImageGlass'
    sharex = 'ShareX'; vlc = 'VLC'; naps2 = 'NAPS2'; posh = 'Oh My Posh'; starship = 'Starship'; python3 = 'Python'
    nodejslts = 'Node.js (LTS)'; vscode = 'Visual Studio Code'; vscodium = 'VSCodium'; visualstudio2026 = 'Visual Studio Community'
    claude = 'Claude'; chatgpt = 'ChatGPT'; moonlight = 'Moonlight'; sunshine = 'Sunshine'; syncthing = 'Syncthing'
    WiseProgramUninstaller = 'Wise Program Uninstaller'; OFGB = 'OFGB'; rufus = 'Rufus'; matrix = 'Element'; whatsapp = 'WhatsApp'
    teams = 'Microsoft Teams'; edge = 'Microsoft Edge'; chrome = 'Google Chrome'; OVirtualBox = 'VirtualBox'; terminal = 'Windows Terminal'
    Overwolf = 'CurseForge'; xeheditor = 'HxD'; klite = 'K-Lite Codec Pack'; mpchc = 'MPC-HC'; ddu = 'Display Driver Uninstaller'
    vc2015_32 = 'Visual C++ 2015-2022 (32 bits)'; vc2015_64 = 'Visual C++ 2015-2022 (64 bits)'; githubdesktop = 'GitHub Desktop'
    epicgames = 'Epic Games'; heroiclauncher = 'Heroic Games Launcher'; googledrive = 'Google Drive'; telegram = 'Telegram'
}

$script:Descricoes = @{
    '1password' = 'Gerenciador de senhas pago, com app e extensão para o navegador.'
    '7zip' = 'Abre e cria .zip, .7z, .rar e outros.'
    abdownloadmanager = 'Gerenciador de downloads que acelera e retoma downloads.'
    adobe = 'O leitor de PDF da Adobe.'
    advancedip = 'Mostra todos os aparelhos ligados na sua rede.'
    aimp = 'Player de música leve, com equalizador.'
    angryipscanner = 'Procura aparelhos e portas abertas na rede.'
    anydesk = 'Acesso remoto: controla outro computador pela internet.'
    audacity = 'Edição de áudio.'
    autoruns = 'Mostra tudo que inicia com o Windows (Sysinternals).'
    rdcman = 'Organiza várias conexões de Área de Trabalho Remota (Sysinternals).'
    autohotkey = 'Atalhos de teclado e automações com scripts.'
    battlenet = 'Loja e launcher da Blizzard (Diablo, Overwatch, WoW).'
    bitwarden = 'Gerenciador de senhas na nuvem, gratuito.'
    blender = 'Modelagem 3D, animação e edição de vídeo.'
    brave = 'Navegador com bloqueio de anúncios embutido.'
    bruno = 'Testa APIs (alternativa leve ao Postman).'
    bulkcrapuninstaller = 'Desinstala vários programas de uma vez e limpa os restos.'
    blurautoclicker = 'Clica sozinho no intervalo que você escolher.'
    calibre = 'Organiza e converte e-books.'
    cemu = 'Emulador de Wii U.'
    chatgpt = 'O app do ChatGPT para Windows (Microsoft Store).'
    chatterino = 'Chat da Twitch em janela própria.'
    chrome = 'Navegador do Google.'
    chromium = 'O Chrome de código aberto, sem os serviços do Google.'
    cinebenchr23 = 'Mede o desempenho do processador.'
    claude = 'O app do Claude, assistente de IA da Anthropic.'
    'claude-code' = 'O Claude no terminal, para programar.'
    cmake = 'Gera projetos de compilação para C e C++.'
    codex = 'Agente de programação da OpenAI no terminal.'
    cpuz = 'Mostra detalhes do processador, memória e placa-mãe.'
    crystaldiskinfo = 'Mostra a saúde e a temperatura dos discos.'
    crystaldiskmark = 'Mede a velocidade dos discos.'
    cursor = 'Editor de código com IA, baseado no VS Code.'
    ddu = 'Remove por completo o driver de vídeo (para reinstalar do zero).'
    discord = 'Chat de voz e texto.'
    dismtools = 'Interface para o DISM: imagens e reparo do Windows.'
    ntlite = 'Personaliza a instalação do Windows antes de instalar.'
    dorion = 'Discord mais leve, com temas e plugins.'
    dockerdesktop = 'Roda contêineres no Windows.'
    dotnet6 = 'O que programas feitos em .NET 6 precisam para abrir.'
    dotnet8 = 'O que programas feitos em .NET 8 precisam para abrir.'
    dotnet9 = 'O que programas feitos em .NET 9 precisam para abrir.'
    dotnet10 = 'O que programas feitos em .NET 10 precisam para abrir.'
    dropbox = 'Arquivos sincronizados na nuvem.'
    eaapp = 'Loja e launcher da EA (FIFA/FC, Battlefield, The Sims).'
    eartrumpet = 'Volume de cada programa direto na barra de tarefas.'
    edge = 'Navegador da Microsoft.'
    'es-de' = 'Biblioteca de jogos para emuladores, com cara de console.'
    enteauth = 'Códigos de verificação em duas etapas, com backup criptografado.'
    epicgames = 'Loja da Epic (jogos grátis toda semana).'
    files = 'Explorador de arquivos moderno, com abas.'
    fileconverter = 'Converte arquivos pelo botão direito do mouse.'
    firefox = 'Navegador da Mozilla.'
    firefoxesr = 'Firefox com atualizações mais espaçadas (versão estendida).'
    floorp = 'Firefox com mais personalização.'
    flux = 'Deixa a tela mais quente à noite.'
    foobar = 'Player de música leve e muito configurável.'
    fnm = 'Troca entre versões do Node.js.'
    foxpdfreader = 'Leitor de PDF com anotações.'
    geforcenow = 'Jogos na nuvem da NVIDIA.'
    gimp = 'Edição de imagens.'
    git = 'Controle de versão.'
    gitextensions = 'Interface gráfica para o Git.'
    githubcli = 'GitHub pela linha de comando (gh).'
    githubdesktop = 'O GitHub sem linha de comando: salvar e enviar versões com cliques.'
    gog = 'Loja e biblioteca de jogos da GOG, sem DRM.'
    golang = 'Linguagem Go.'
    googledrive = 'Arquivos do Google Drive como uma pasta no computador.'
    gpuz = 'Mostra detalhes da placa de vídeo.'
    gsudo = 'Roda um comando como administrador no terminal.'
    helium = 'Navegador leve baseado no Chromium, sem rastreamento.'
    hugo = 'Gera sites estáticos.'
    handbrake = 'Converte e comprime vídeos.'
    heroiclauncher = 'Jogos da Epic, GOG e Amazon num lugar só.'
    hwinfo = 'Sensores e informações detalhadas do hardware.'
    hwmonitor = 'Temperaturas, voltagens e ventoinhas.'
    imhex = 'Editor hexadecimal para engenharia reversa.'
    imageglass = 'Visualizador de imagens rápido.'
    internetdownloadmanager = 'Gerenciador de downloads pago, que acelera downloads.'
    irfanview = 'Visualizador e conversor de imagens, bem leve.'
    itch = 'Loja de jogos independentes.'
    itunes = 'Música da Apple e backup do iPhone.'
    java8 = 'Java 8 (Amazon Corretto), para programas antigos.'
    java21 = 'Java 21 (Amazon Corretto).'
    java25 = 'Java 25 (Amazon Corretto).'
    jellyfinmediaplayer = 'Assiste aos filmes do seu servidor Jellyfin.'
    jellyfinserver = 'Seu próprio "Netflix" com os seus filmes e séries.'
    jetbrains = 'Instala as IDEs da JetBrains.'
    jpegview = 'Visualizador de imagens leve.'
    joplin = 'Notas e listas, com sincronização.'
    keepassxc = 'Gerenciador de senhas local.'
    klite = 'Codecs para abrir qualquer formato de vídeo.'
    kodi = 'Central de mídia para filmes, séries e música.'
    lazygit = 'Git no terminal, com interface.'
    libreoffice = 'Pacote de escritório (texto, planilha, apresentação).'
    librewolf = 'Firefox com foco em privacidade.'
    localsend = 'Manda arquivos para outros aparelhos na mesma rede.'
    'mpc-qt' = 'Player de vídeo no estilo do MPC-HC.'
    mpv = 'Player de vídeo minimalista.'
    matrix = 'Mensagens pelo Matrix, descentralizado e criptografado.'
    minitoolpartitionwizard = 'Cria, redimensiona e move partições.'
    modrinth = 'Instala Minecraft com mods.'
    moonlight = 'Joga no celular ou notebook o que roda no seu PC (cliente).'
    mpchc = 'Player de vídeo clássico e leve.'
    msedgeredirect = 'Abre os links do Windows no seu navegador, não no Edge.'
    msiafterburner = 'Overclock e monitor de desempenho da placa de vídeo.'
    mullvadvpn = 'VPN paga, sem conta e sem registro.'
    mullvadbrowser = 'Navegador de privacidade do Mullvad com o Tor Project.'
    nomacs = 'Visualizador de imagens.'
    nanazip = '7-Zip moderno, integrado ao menu do Windows 11.'
    netbird = 'Rede privada entre seus aparelhos.'
    tailscale = 'Rede privada entre seus aparelhos, fácil de configurar.'
    naps2 = 'Digitaliza documentos para PDF.'
    neovim = 'Editor de texto no terminal.'
    nextclouddesktop = 'Sincroniza com o seu servidor Nextcloud.'
    nmap = 'Mapeia redes e portas.'
    nodejs = 'JavaScript fora do navegador (versão mais nova).'
    nodejslts = 'JavaScript fora do navegador (versão de longo suporte).'
    pnpm = 'Gerenciador de pacotes do Node.js.'
    notepadplus = 'Editor de texto leve.'
    nuget = 'Gerenciador de pacotes do .NET.'
    nvclean = 'Instala o driver da NVIDIA sem os extras.'
    obs = 'Gravação e transmissão de tela.'
    obsidian = 'Notas em Markdown.'
    okular = 'Leitor de PDF e documentos do KDE.'
    onedrive = 'Arquivos da Microsoft na nuvem.'
    onlyoffice = 'Pacote de escritório compatível com o Office.'
    OPAutoClicker = 'Clica sozinho no intervalo que você escolher.'
    opencode = 'Agente de programação com IA no terminal.'
    openrgb = 'Controla as luzes RGB de várias marcas num programa só.'
    OpenVPN = 'Conecta em VPNs OpenVPN.'
    OVirtualBox = 'Roda outros sistemas operacionais em máquinas virtuais.'
    policyplus = 'Editor de Política de Grupo, inclusive no Windows Home.'
    processexplorer = 'Gerenciador de Tarefas detalhado (Sysinternals).'
    Paintdotnet = 'Edição de imagens simples e rápida.'
    parsec = 'Acesso remoto com baixa latência, bom para jogos.'
    peazip = 'Abre e cria arquivos compactados.'
    'pdf-xchange' = 'Edita, anota e assina PDFs.'
    pdf24creator = 'Junta, divide, comprime e converte PDFs.'
    pdfgear = 'Edita e converte PDFs, grátis.'
    pdfsam = 'Junta e divide PDFs.'
    playnite = 'Junta os jogos de todas as lojas numa biblioteca só.'
    plex = 'Servidor de filmes e séries para a casa toda.'
    plexdesktop = 'Assiste ao que está no seu servidor Plex.'
    posh = 'Deixa o prompt do terminal bonito e informativo.'
    postman = 'Testa APIs.'
    powershell = 'PowerShell 7, a versão mais nova.'
    powertoys = 'Utilitários da Microsoft: FancyZones, PowerRename, Seletor de Cor...'
    prismlauncher = 'Minecraft com várias instâncias e mods.'
    processlasso = 'Ajusta a prioridade dos programas automaticamente.'
    protonauth = 'Códigos de verificação em duas etapas, da Proton.'
    protonmail = 'E-mail criptografado da Proton.'
    protondrive = 'Nuvem criptografada da Proton.'
    protonpass = 'Gerenciador de senhas da Proton.'
    protonvpn = 'VPN da Proton, com plano gratuito.'
    processmonitor = 'Mostra o que cada programa faz no disco e no registro (Sysinternals).'
    pstools = 'Comandos de administração remota (Sysinternals).'
    putty = 'Conexões SSH e Telnet.'
    python3 = 'Linguagem Python.'
    qbittorrent = 'Cliente de torrent sem anúncios.'
    qownnotes = 'Notas em Markdown, com sincronização pelo Nextcloud.'
    qtox = 'Mensagens e chamadas criptografadas, sem servidor.'
    revo = 'Desinstala programas e limpa os restos.'
    WiseProgramUninstaller = 'Desinstala programas e limpa os restos.'
    rufus = 'Cria pendrive de instalação do Windows ou Linux.'
    rustlang = 'Linguagem Rust.'
    sdio = 'Instala e atualiza drivers sem internet.'
    sharex = 'Captura e gravação de tela.'
    nilesoftShell = 'Substitui o menu do botão direito por um personalizável.'
    systeminformer = 'Gerenciador de Tarefas avançado.'
    signal = 'Mensagens criptografadas.'
    signalrgb = 'Controla as luzes RGB de várias marcas.'
    simplenote = 'Notas simples, sincronizadas.'
    simplewall = 'Firewall simples: escolhe quais programas usam a internet.'
    slack = 'Chat para equipes.'
    startallback = 'Menu Iniciar e barra de tarefas no estilo do Windows 7/10 (pago).'
    starship = 'Prompt do terminal rápido e bonito.'
    steam = 'Loja e biblioteca de jogos.'
    roblox = 'Plataforma de jogos Roblox.'
    sublimetext = 'Editor de código rápido.'
    sumatra = 'Leitor de PDF leve.'
    sunshine = 'Transmite os jogos do seu PC para outros aparelhos (servidor).'
    synctrayzor = 'Syncthing com ícone na bandeja.'
    syncthing = 'Sincroniza pastas entre seus aparelhos, sem nuvem.'
    tcpview = 'Mostra as conexões de rede de cada programa (Sysinternals).'
    teams = 'Reuniões e chat da Microsoft.'
    teamviewer = 'Acesso remoto.'
    teamspeak3 = 'Chat de voz para jogos.'
    teamspeak6 = 'Chat de voz para jogos (versão nova, em teste).'
    telegram = 'Mensagens.'
    terminal = 'Terminal moderno com abas.'
    thunderbird = 'E-mail e agenda da Mozilla.'
    betterbird = 'Thunderbird com correções e melhorias.'
    tor = 'Navega pela rede Tor, anônimo.'
    totalcommander = 'Gerenciador de arquivos com dois painéis.'
    treesize = 'Mostra o que ocupa espaço no disco.'
    ttaskbar = 'Barra de tarefas transparente.'
    ubisoft = 'Loja e launcher da Ubisoft.'
    ungoogled = 'Chromium sem nada do Google.'
    unity = 'Motor de jogos Unity.'
    vagrant = 'Cria máquinas virtuais por configuração.'
    everything = 'Acha qualquer arquivo do disco na hora.'
    vc2015_32 = 'O que muitos programas e jogos precisam para abrir (32 bits).'
    vc2015_64 = 'O que muitos programas e jogos precisam para abrir (64 bits).'
    ventoy = 'Pendrive que dá boot em vários ISOs.'
    vesktop = 'Discord com Vencord (temas e plugins).'
    viber = 'Mensagens e chamadas.'
    visualstudio2022 = 'IDE da Microsoft para C#, C++ e .NET (2022).'
    visualstudio2026 = 'IDE da Microsoft para C#, C++ e .NET, grátis.'
    vivaldi = 'Navegador muito personalizável.'
    vlc = 'Toca qualquer vídeo ou música.'
    vrdesktopstreamer = 'Usa o PC em óculos de realidade virtual.'
    vscode = 'Editor de código.'
    vscodium = 'O VS Code sem a telemetria da Microsoft.'
    waterfox = 'Navegador baseado no Firefox, com foco em privacidade.'
    whatsapp = 'O WhatsApp para Windows (Microsoft Store).'
    wingetui = 'Interface para instalar e atualizar programas (winget, Chocolatey e outros).'
    winrar = 'Abre e cria .rar e .zip.'
    winscp = 'Transfere arquivos por SFTP e FTP.'
    wireguard = 'VPN WireGuard.'
    wireshark = 'Captura e analisa o tráfego de rede.'
    wiztree = 'Mapa de uso do disco, muito rápido.'
    xeheditor = 'Editor hexadecimal.'
    xournal = 'Anotações à mão e em PDFs (bom com caneta).'
    yarn = 'Gerenciador de pacotes do Node.js.'
    zoom = 'Videochamadas.'
    uv = 'Gerenciador de pacotes do Python, muito rápido.'
    tightvnc = 'Acesso remoto por VNC.'
    glazewm = 'Organiza as janelas lado a lado automaticamente.'
    Overwolf = 'Instala mods de jogos (Minecraft, WoW e outros).'
    OFGB = 'Desliga as propagandas do Windows 11.'
    ZenBrowser = 'Navegador baseado no Firefox, com abas na lateral.'
    Zed = 'Editor de código rápido.'
    zotero = 'Organiza referências e artigos.'
    deskflow = 'Um teclado e mouse para vários computadores.'
    Ruby = 'Linguagem Ruby.'
    Lua = 'Linguagem Lua.'
    CloudflareWARP = 'Conexão mais segura e DNS rápido da Cloudflare.'
}

# Fora do WinUtil, mantidos do catálogo antigo.
$script:Extras = @(
    [ordered]@{ id = 'spotify'; nome = 'Spotify'; descricao = 'Música por streaming.'; categoria = 'Multimídia'; wingetId = 'Spotify.Spotify'; livre = $false; site = 'https://www.spotify.com/'; choco = 'spotify'; winutil = '' }
)

$dados = [IO.File]::ReadAllText($WinUtil, [Text.Encoding]::UTF8) | ConvertFrom-Json
$programas = [System.Collections.Generic.List[object]]::new()
$referencia = [ordered]@{}
foreach ($p in $dados.PSObject.Properties) {
    $chave = $p.Name; $a = $p.Value
    $referencia[$chave] = [ordered]@{ nome = [string]$a.content; winget = [string]$a.winget; categoria = [string]$a.category }
    if ($a.category -eq 'Development' -and $script:DevBasico -notcontains $chave) { continue }
    if (-not $script:Descricoes.ContainsKey($chave)) { throw "sem descrição em português para '$chave' ($($a.content))" }
    $winget = [string]$a.winget
    $loja = $winget -like 'msstore:*'
    $wingetId = if ($loja) { $winget.Substring(8) } else { $winget }
    $id = if ($script:IdsAntigos.ContainsKey($wingetId)) { $script:IdsAntigos[$wingetId] } else { ($chave.ToLowerInvariant() -replace '[^a-z0-9]+', '-').Trim('-') }
    $p2 = [ordered]@{
        id = $id
        nome = if ($script:Nomes.ContainsKey($chave)) { $script:Nomes[$chave] } else { [string]$a.content }
        descricao = $script:Descricoes[$chave]
        categoria = $script:Categorias[[string]$a.category]
        wingetId = $wingetId
    }
    if ($loja) { $p2.fonte = 'msstore' }
    # Nem todo programa do WinUtil tem todos os campos.
    $campo = { param($n) $x = $a.PSObject.Properties[$n]; if ($x) { $x.Value } else { $null } }
    $p2.livre = (& $campo 'foss') -eq $true
    $p2.site = [string](& $campo 'link')
    $choco = [string](& $campo 'choco')
    $p2.choco = if ($choco -and $choco -ne 'na') { ($choco -split ';')[-1] } else { '' }
    $p2.winutil = $chave
    $programas.Add($p2)
}
foreach ($e in $script:Extras) { $programas.Add($e) }

# Ordem da página: categorias na ordem de $Categorias, nomes em ordem alfabética.
$ordem = @($script:Categorias.Values)
$final = @($programas | Sort-Object @{ Expression = { $ordem.IndexOf($_.categoria) } }, @{ Expression = { $_.nome } })
$json = ConvertTo-Json -InputObject $final -Depth 4
[IO.File]::WriteAllText((Join-Path $raiz 'modulos\programas\programas.json'), $json, (New-Object Text.UTF8Encoding $false))
$ref = [ordered]@{ ForaDeProposito = 'desenvolvimento além do básico'; DevBasico = $script:DevBasico; Programas = $referencia }
[IO.File]::WriteAllText((Join-Path $raiz 'testes\modulos\programas\winutil-apps.json'), (ConvertTo-Json -InputObject $ref -Depth 5), (New-Object Text.UTF8Encoding $false))
"$($final.Count) programas em $(@($final | ForEach-Object categoria | Select-Object -Unique).Count) categorias"
