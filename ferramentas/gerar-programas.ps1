<#
.SYNOPSIS
    Gera modulos\programas\programas.json a partir do WinUtil (config/applications.json: IDs do winget, sites) e do
    FMHY (github.com/fmhy/edit, docs/*.md: o que entra e o que tem estrela). Nome, descrição e categoria em português.
    Ferramenta de desenvolvimento: o programa nunca roda isto.
.DESCRIPTION
    Regras (pedido do usuário):
      - Só fica o que está no FMHY; ⭐ no FMHY vira "estrela": true aqui.
      - Exceção: $Populares (muito usados que o FMHY não lista, e componentes que jogos e programas precisam), numa
        categoria à parte e sem estrela.
      - Só programas grátis (a versão gratuita tem que bastar): $Pagos ficam de fora mesmo estando no FMHY.
      - Programas com ⭐ do FMHY que não estão no WinUtil entram por $DoFmhy (escolhidos à mão: com pacote no winget,
        com janela, para usuário comum; nada de pirataria, linha de comando ou mod de jogo).
      - Desenvolvimento só com o básico.
    O que justificou cada programa (a entrada do FMHY) vai para testes\modulos\programas\fmhy-referencia.json.
.EXAMPLE
    .\ferramentas\gerar-programas.ps1 -WinUtil C:\temp\applications.json -Fmhy C:\temp\fmhy-docs
#>
[CmdletBinding()]
param([Parameter(Mandatory)][string]$WinUtil, [Parameter(Mandatory)][string]$Fmhy)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$raiz = Split-Path -Parent $PSScriptRoot
. (Join-Path $PSScriptRoot 'Fmhy.ps1')

# Muito usados que o FMHY não lista: ficam, à parte. (Decisão do usuário em 30/10/2026.)
$script:CategoriaPopulares = 'Populares (fora do FMHY)'
$script:Populares = 'discord', 'steam', 'telegram', 'whatsapp', 'chrome', 'epic', 'dotnet6', 'dotnet8', 'dotnet9', 'dotnet10', 'vc2015-32', 'vc2015-64'

# Pagos ou teste com prazo: fora, mesmo estando no FMHY. (Mullvad VPN: o app é grátis, mas só funciona com conta paga.)
$script:Pagos = '1password', 'winrar', 'startallback', 'totalcommander', 'sublimetext', 'internetdownloadmanager', 'mullvadvpn'

# Nome do programa no FMHY, quando é outro (id -> nomes).
$script:NomesFmhy = @{
    'cloudflarewarp' = @('Cloudflare One'); 'pdf24creator' = @('PDF24'); 'kodi' = @('Kodi'); 'jellyfinmediaplayer' = @('Jellyfin')
    'jellyfinserver' = @('Jellyfin'); 'treesize' = @('TreeSize'); 'sdio' = @('SDIO'); 'nextclouddesktop' = @('NextCloud')
    'lively' = @('Lively'); 'testdisk' = @('TestDisk'); 'koodoreader' = @('Koodo'); 'sysinternals' = @('Sysinternals')
}

# Alternativas (programas que fazem a mesma coisa): viram uma pasta na grade, como as pastas do menu Iniciar do
# Windows 11. Só dentro da mesma categoria; pasta com um programa só não aparece.
$script:Grupos = [ordered]@{
    'Baseados no Firefox'      = 'firefox', 'librewolf', 'zenbrowser', 'mullvadbrowser', 'tor'
    'Baseados no Chromium'     = 'brave', 'helium'
    'E-mail'                   = 'thunderbird', 'betterbird', 'mailspring', 'protonmail'
    'Mensagens'                = 'signal', 'matrix', 'qtox', 'discord', 'telegram', 'whatsapp'
    'Discord com extras'       = 'vesktop', 'dorion'
    'Players de vídeo'         = 'vlc', 'mpchc', 'mpc-qt', 'mpv'
    'Players de música'        = 'aimp', 'foobar'
    'Edição de imagem'         = 'gimp', 'krita', 'pinta', 'paintdotnet', 'inkscape'
    'Visualizadores de imagem' = 'imageglass', 'irfanview', 'nomacs', 'jpegview'
    'Edição de vídeo'          = 'kdenlive', 'shotcut', 'losslesscut'
    'Conversores'              = 'handbrake', 'shutterencoder', 'fileconverter'
    'Escritório'               = 'libreoffice', 'onlyoffice'
    'Notas'                    = 'obsidian', 'logseq', 'notesnook', 'joplin', 'qownnotes', 'simplenote'
    'Leitores (PDF e e-book)'  = 'sumatrapdf', 'okular', 'koodoreader'
    'Compactadores'            = '7zip', 'nanazip', 'peazip'
    'Senhas e 2FA'             = 'bitwarden', 'keepassxc', 'protonpass', 'enteauth', 'protonauth'
    'Desinstaladores'          = 'bulkcrapuninstaller', 'revo'
    'Espaço em disco'          = 'wiztree', 'treesize', 'czkawka'
    'Saúde do disco'           = 'crystaldiskinfo', 'crystaldiskmark'
    'Nuvem'                    = 'googledrive', 'dropbox', 'protondrive'
    'Criptografia'             = 'veracrypt', 'cryptomator'
    'Antimalware'              = 'malwarebytes', 'adwcleaner'
    'Personalizar o Windows'   = 'windhawk', 'rainmeter', 'lively', 'ttaskbar'
    'Organizar janelas'        = 'glazewm', 'altsnap'
    'Busca de arquivos'        = 'everything', 'everythingtoolbar'
    'Launchers de jogos'       = 'heroic', 'playnite', 'gog', 'itch', 'steam', 'epic'
    'Minecraft'                = 'prismlauncher', 'modrinth', 'overwolf'
    'Editores de código'       = 'vscode', 'vscodium', 'zed', 'notepadpp'
    'Assistentes de IA'        = 'chatgpt', 'claude'
    'Informações do hardware'  = 'cpuz', 'gpuz', 'hwinfo', 'hwmonitor'
    'VPN'                      = 'protonvpn', 'windscribe', 'wireguard', 'tailscale'
    'Análise de rede'          = 'nmap', 'wireshark'
    'Jellyfin'                 = 'jellyfinserver', 'jellyfinmediaplayer'
    'Plex'                     = 'plex', 'plexdesktop'
    'Jogos por streaming'      = 'sunshine', 'moonlight'
    'Componentes do Windows'   = 'dotnet6', 'dotnet8', 'dotnet9', 'dotnet10', 'vc2015-32', 'vc2015-64'
}

# Estrela do FMHY que é de outra coisa com o mesmo nome e site (o "Plex" com ⭐ é o site de filmes, não o app).
$script:SemEstrela = 'plex', 'plexdesktop'

# Programas com ⭐ no FMHY que não estão no WinUtil. Os seis do Sysinternals (Autoruns etc.) viram a suíte, que é o
# que o FMHY recomenda.
$script:Substituidos = 'autoruns', 'processexplorer', 'processmonitor', 'pstools', 'rdcman', 'tcpview'
$script:DoFmhy = @(
    , @('windhawk', 'Windhawk', 'Utilitários', 'RamenSoftware.Windhawk', 'https://windhawk.net/', 'windhawk', 'Mods para personalizar o Windows (barra de tarefas, menu Iniciar, janelas) sem mexer em arquivo do sistema.')
    , @('superf4', 'SuperF4', 'Utilitários', 'StefanSundin.Superf4', 'https://stefansundin.github.io/superf4/', 'superf4', 'Ctrl+Alt+F4 fecha na hora o programa travado em primeiro plano.')
    , @('altsnap', 'AltSnap', 'Utilitários', 'AltSnap.AltSnap', 'https://github.com/RamonUnch/AltSnap', 'altsnap', 'Arrasta e redimensiona janelas segurando Alt, de qualquer ponto delas.')
    , @('ditto', 'Ditto', 'Utilitários', 'Ditto.Ditto', 'https://ditto-cp.sourceforge.io/', 'ditto', 'Guarda tudo o que você copia para colar de novo depois.')
    , @('everythingtoolbar', 'EverythingToolbar', 'Utilitários', 'srwi.EverythingToolbar.Launcher', 'https://github.com/srwi/EverythingToolbar', 'everythingtoolbar', 'Busca do Everything direto da barra de tarefas (precisa do Everything).')
    , @('compactgui', 'CompactGUI', 'Utilitários', 'IridiumIO.CompactGUI', 'https://github.com/IridiumIO/CompactGUI', 'compactgui', 'Compacta pastas e jogos pelo próprio Windows, sem perder nada e sem precisar descompactar.')
    , @('czkawka', 'Czkawka', 'Utilitários', 'qarmin.czkawka.gui', 'https://github.com/qarmin/czkawka', 'czkawka', 'Acha arquivos duplicados, imagens parecidas e pastas vazias para liberar espaço.')
    , @('monitorian', 'Monitorian', 'Utilitários', 'emoacht.Monitorian', 'https://github.com/emoacht/Monitorian', 'monitorian', 'Ajusta o brilho dos monitores pela bandeja.')
    , @('rainmeter', 'Rainmeter', 'Utilitários', 'Rainmeter.Rainmeter', 'https://www.rainmeter.net/', 'rainmeter', 'Widgets e temas na área de trabalho (relógio, uso do PC, clima).')
    , @('textgrab', 'Text Grab', 'Utilitários', 'JosephFinney.Text-Grab', 'https://github.com/TheJoeFin/Text-Grab', 'text-grab', 'Copia o texto de qualquer coisa na tela (imagem, vídeo, programa).')
    , @('advancedrenamer', 'Advanced Renamer', 'Utilitários', 'HulubuluSoftware.AdvancedRenamer', 'https://www.advancedrenamer.com/', 'advanced-renamer', 'Renomeia muitos arquivos de uma vez, com regras (grátis para uso pessoal).')
    , @('deepl', 'DeepL', 'Utilitários', 'DeepL.DeepL', 'https://www.deepl.com/', 'deepl', 'Tradutor de texto e documentos (plano gratuito).')
    , @('flameshot', 'Flameshot', 'Utilitários', 'Flameshot.Flameshot', 'https://flameshot.org/', 'flameshot', 'Captura de tela com setas, texto e destaque na hora.')
    , @('kopia', 'Kopia', 'Utilitários', 'Kopia.KopiaUI', 'https://kopia.io/', 'kopiaui', 'Backup das suas pastas, criptografado, para outro disco ou para a nuvem.')
    , @('lively', 'Lively Wallpaper', 'Utilitários', 'rocksdanister.LivelyWallpaper', 'https://www.rocksdanister.com/lively/', 'lively', 'Papel de parede animado (vídeo, página, GIF).')
    , @('testdisk', 'TestDisk e PhotoRec', 'Utilitários', 'CGSecurity.TestDisk', 'https://www.cgsecurity.org/', 'testdisk-photorec', 'Recupera arquivos apagados e partições perdidas.')
    , @('veracrypt', 'VeraCrypt', 'Utilitários', 'IDRIX.VeraCrypt', 'https://www.veracrypt.fr/', 'veracrypt', 'Cofre criptografado para arquivos, pendrives e discos inteiros.')
    , @('cryptomator', 'Cryptomator', 'Utilitários', 'Cryptomator.Cryptomator', 'https://cryptomator.org/', 'cryptomator', 'Criptografa seus arquivos antes de irem para a nuvem (Drive, Dropbox, OneDrive).')
    , @('adwcleaner', 'AdwCleaner', 'Utilitários', 'Malwarebytes.AdwCleaner', 'https://www.malwarebytes.com/adwcleaner', 'adwcleaner', 'Remove adware, barras de ferramentas e programas indesejados.')
    , @('malwarebytes', 'Malwarebytes', 'Utilitários', 'Malwarebytes.Malwarebytes', 'https://www.malwarebytes.com/', 'malwarebytes', 'Procura e remove malware (a verificação manual é grátis).')
    , @('windscribe', 'Windscribe', 'Ferramentas avançadas', 'Windscribe.Windscribe', 'https://windscribe.com/', 'windscribe', 'VPN com plano gratuito.')
    , @('inkscape', 'Inkscape', 'Multimídia', 'Inkscape.Inkscape', 'https://inkscape.org/', 'inkscape', 'Desenho vetorial: logos, ilustrações, SVG.')
    , @('krita', 'Krita', 'Multimídia', 'KDE.Krita', 'https://krita.org/', 'krita', 'Pintura digital e ilustração.')
    , @('pinta', 'Pinta', 'Multimídia', 'Pinta.Pinta', 'https://www.pinta-project.com/', 'pinta', 'Editor de imagens simples, tipo um Paint mais completo.')
    , @('kdenlive', 'Kdenlive', 'Multimídia', 'KDE.Kdenlive', 'https://kdenlive.org/', 'kdenlive', 'Editor de vídeo completo.')
    , @('shotcut', 'Shotcut', 'Multimídia', 'Meltytech.Shotcut', 'https://shotcut.org/', 'shotcut', 'Editor de vídeo.')
    , @('losslesscut', 'LosslessCut', 'Multimídia', 'ch.LosslessCut', 'https://github.com/mifi/lossless-cut', 'lossless-cut', 'Corta vídeos e áudios na hora, sem perder qualidade.')
    , @('shutterencoder', 'Shutter Encoder', 'Multimídia', 'PaulPacifico.ShutterEncoder', 'https://www.shutterencoder.com/', 'shutter-encoder', 'Converte vídeo, áudio e imagem para qualquer formato.')
    , @('upscayl', 'Upscayl', 'Multimídia', 'Upscayl.Upscayl', 'https://upscayl.org/', 'upscayl', 'Aumenta imagens com IA sem ficar borrado.')
    , @('mp3tag', 'Mp3tag', 'Multimídia', 'FlorianHeidenreich.Mp3tag', 'https://www.mp3tag.de/', 'mp3tag', 'Edita nome, artista, álbum e capa das músicas.')
    , @('musescore', 'MuseScore', 'Multimídia', 'Musescore.Musescore', 'https://musescore.org/', 'musescore', 'Escreve e toca partituras.')
    , @('voicemeeter', 'Voicemeeter', 'Multimídia', 'VB-Audio.Voicemeeter', 'https://vb-audio.com/Voicemeeter/', 'voicemeeter', 'Mesa de som virtual: mistura microfone e sons do PC.')
    , @('freetube', 'FreeTube', 'Multimídia', 'FreeTube.FreeTube', 'https://freetubeapp.io/', 'freetube', 'YouTube sem anúncios e sem rastreamento.')
    , @('logseq', 'Logseq', 'Documentos', 'Logseq.Logseq', 'https://logseq.com/', 'logseq', 'Notas ligadas umas às outras, em tópicos.')
    , @('notesnook', 'Notesnook', 'Documentos', 'Streetwriters.Notesnook', 'https://notesnook.com/', 'notesnook', 'Notas criptografadas, sincronizadas.')
    , @('drawio', 'draw.io', 'Documentos', 'JGraph.Draw', 'https://www.drawio.com/', 'drawio', 'Fluxogramas, diagramas e organogramas.')
    , @('koodoreader', 'Koodo Reader', 'Documentos', 'AppByTroye.KoodoReader', 'https://koodoreader.com/', 'koodo-reader', 'Leitor de e-books (EPUB, PDF, MOBI).')
    , @('mailspring', 'Mailspring', 'Comunicação', 'Foundry376.Mailspring', 'https://getmailspring.com/', 'mailspring', 'Cliente de e-mail moderno para várias contas.')
    , @('ludusavi', 'Ludusavi', 'Jogos', 'mtkennerly.ludusavi', 'https://github.com/mtkennerly/ludusavi', 'ludusavi', 'Faz backup dos saves dos seus jogos.')
    , @('sysinternals', 'Sysinternals Suite', 'Ferramentas da Microsoft', 'Microsoft.Sysinternals.Suite', 'https://learn.microsoft.com/sysinternals/', 'sysinternals', 'As ferramentas avançadas da Microsoft: Autoruns, Process Explorer, Process Monitor, TCPView e outras.')
)

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
foreach ($d in $script:DoFmhy) {
    $programas.Add([ordered]@{ id = $d[0]; nome = $d[1]; descricao = $d[6]; categoria = $d[2]; wingetId = $d[3]; livre = $false; site = $d[4]; choco = $d[5]; winutil = '' })
}

# FMHY: o que fica, o que tem estrela e de onde veio.
$entradas = @(Read-FmhyEntradas -Pasta $Fmhy)
$indice = New-FmhyIndice -Entradas $entradas
$inseguros = @($entradas | Where-Object Inseguro | ForEach-Object Simples | Select-Object -Unique)
$fmhyRef = [ordered]@{}
$fora = [System.Collections.Generic.List[string]]::new()
$finais = foreach ($p in $programas) {
    if ($script:Pagos -contains $p.id -or $script:Substituidos -contains $p.id) { continue }
    $nomes = @($p.nome) + @(if ($script:NomesFmhy.ContainsKey($p.id)) { $script:NomesFmhy[$p.id] })
    $r = Find-FmhyPrograma -Indice $indice -Nomes $nomes -Site $p.site
    if (@(Get-FmhyFormasNome $p.nome | Where-Object { $inseguros -contains $_ }).Count -gt 0) { throw "$($p.id) está no unsafe.md do FMHY" }
    if ($script:Populares -contains $p.id) {
        $p.categoria = $script:CategoriaPopulares
        $p.estrela = $false
    }
    elseif ($r.Achou) {
        $p.estrela = $r.Estrela -and $script:SemEstrela -notcontains $p.id
        $p.fmhy = $r.Onde
        $fmhyRef[$p.id] = [ordered]@{ nomes = $nomes; estrela = $p.estrela; onde = $r.Onde }
    }
    else { $fora.Add("$($p.nome)"); continue }
    foreach ($g in $script:Grupos.Keys) { if (@($script:Grupos[$g]) -contains $p.id) { $p.grupo = $g } }
    $p
}
# Pasta só faz sentido com 2 ou mais na mesma categoria.
foreach ($g in @($finais | Where-Object { $_.Contains('grupo') } | Group-Object { "$($_.categoria)|$($_['grupo'])" } | Where-Object Count -lt 2)) {
    foreach ($p in $g.Group) { $p.Remove('grupo') }
}

# Ordem da página: categorias na ordem de $Categorias (populares no fim), com estrela primeiro, depois alfabética.
$ordem = @($script:Categorias.Values) + $script:CategoriaPopulares
$final = @($finais | Sort-Object @{ Expression = { $ordem.IndexOf($_.categoria) } }, @{ Expression = { -not $_.estrela } }, @{ Expression = { $_.nome } })
$json = ConvertTo-Json -InputObject $final -Depth 4
[IO.File]::WriteAllText((Join-Path $raiz 'modulos\programas\programas.json'), $json, (New-Object Text.UTF8Encoding $false))
$ref = [ordered]@{ ForaDeProposito = 'desenvolvimento além do básico'; DevBasico = $script:DevBasico; Programas = $referencia }
[IO.File]::WriteAllText((Join-Path $raiz 'testes\modulos\programas\winutil-apps.json'), (ConvertTo-Json -InputObject $ref -Depth 5), (New-Object Text.UTF8Encoding $false))
$refFmhy = [ordered]@{ Populares = $script:Populares; Pagos = $script:Pagos; Inseguros = $inseguros; Programas = $fmhyRef }
[IO.File]::WriteAllText((Join-Path $raiz 'testes\modulos\programas\fmhy-referencia.json'), (ConvertTo-Json -InputObject $refFmhy -Depth 5), (New-Object Text.UTF8Encoding $false))
"$($final.Count) programas em $(@($final | ForEach-Object categoria | Select-Object -Unique).Count) categorias; $(@($final | Where-Object estrela).Count) com estrela"
"Fora (não estão no FMHY): $($fora -join ', ')"
