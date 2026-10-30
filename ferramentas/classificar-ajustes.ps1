<#
.SYNOPSIS
    Grava em modulos\ajustes\ajustes.json a classificação de cada ajuste: "classificacao" (Recomendado, Opcional,
    Atencao, Arriscado) e, quando pode dar algum contratempo, "contratempo" (o que pode acontecer) e "seAcontecer"
    (como resolver). Ferramenta de desenvolvimento: os textos ficam aqui e o catálogo é regravado. Rodar de novo é seguro.
.DESCRIPTION
    Recomendado  bom para quase todo mundo, sem efeito colateral que se note.
    Opcional     questão de gosto; não atrapalha nada.
    Atencao      funciona, mas pode dar um contratempo em certos casos.
    Arriscado    mexe em segurança ou em algo que o Windows usa por baixo. Tudo de "Avançado (por sua conta e risco)".
#>
[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$raiz = Split-Path -Parent $PSScriptRoot
$arquivo = Join-Path $raiz 'modulos\ajustes\ajustes.json'

$desfazer = 'Desfaça na página Ajustes: o ajuste aparece como "aplicado · marcar desfaz"; marque e clique em Aplicar.'
$reiniciar = "$desfazer Depois, reinicie o computador."

# id = classificação, contratempo, se acontecer. Recomendado/Opcional sem contratempo não precisam de texto.
$c = @{
    'seg-ponto-restauracao'            = 'Recomendado'
    'acao-limpar-temporarios'          = 'Recomendado'
    'acao-limpeza-disco'               = 'Atencao', 'Demora (pode passar de meia hora) e, depois, não dá mais para desinstalar as atualizações do Windows que foram limpas.', 'Nada a desfazer: só deixe terminar. Se uma atualização nova der problema, a saída passa a ser o ponto de restauração.'
    'priv-telemetria'                  = 'Recomendado'
    'priv-historico-atividades'        = 'Recomendado'
    'priv-recursos-consumidor'         = 'Recomendado'
    'priv-sem-otimizacao-entrega'      = 'Recomendado'
    'priv-localizacao'                 = 'Atencao', 'Apps de mapa e clima não acham onde você está, o fuso horário automático para de funcionar e o "Localizar meu dispositivo" fica desligado.', $desfazer
    'priv-id-anuncios'                 = 'Recomendado'
    'priv-experiencias-personalizadas' = 'Recomendado'
    'priv-sugestoes-iniciar'           = 'Recomendado'
    'priv-dicas-windows'               = 'Recomendado'
    'priv-apps-sugeridos'              = 'Recomendado'
    'priv-bing-iniciar'                = 'Atencao', 'Em algumas versões do Windows a busca do menu Iniciar fica em branco ou demora para mostrar resultados.', $reiniciar
    'priv-apps-dispositivos'           = 'Recomendado'
    'priv-busca-loja'                  = 'Opcional'
    'priv-sem-content-delivery'        = 'Recomendado'
    'priv-sem-propaganda-onedrive'     = 'Recomendado'
    'priv-sem-telemetria-office'       = 'Recomendado'
    'priv-sem-telemetria-nvidia'       = 'Recomendado'
    'priv-sem-terminar-configuracao'   = 'Recomendado'
    'priv-sem-sincronizar-configuracoes' = 'Atencao', 'Em outro computador com a mesma conta Microsoft, tema, senhas do Wi-Fi e preferências não vêm junto.', $desfazer
    'priv-sem-sincronizar-mensagens'   = 'Opcional'
    'priv-permissoes-apps'             = 'Atencao', 'Algum app da Microsoft Store pode não mostrar seu nome ou foto da conta, ou pedir para entrar de novo.', $desfazer
    'priv-media-player'                = 'Recomendado'
    'priv-sem-experimentos'            = 'Recomendado'
    'priv-sem-camera-bloqueio'         = 'Opcional'
    'priv-sem-rastreio-desempenho'     = 'Recomendado'
    'priv-sem-tela-privacidade-contas' = 'Opcional'
    'priv-sem-atualizar-voz'           = 'Opcional'
    'priv-sem-apps-mais-usados'        = 'Opcional'
    'priv-sem-idiomas-sites'           = 'Recomendado'
    'priv-sem-relatorio-erros'         = 'Opcional', 'Quando um programa trava, o Windows não procura mais uma solução conhecida para o erro.', $desfazer
    'priv-sem-telemetria-ativacao'     = 'Opcional'
    'priv-sem-ceip'                    = 'Recomendado'
    'priv-sem-coleta-escrita'          = 'Recomendado'
    'priv-sem-spotlight'               = 'Opcional'
    'priv-sem-pedir-opiniao'           = 'Recomendado'
    'priv-sem-telemetria-mrt'          = 'Recomendado'
    'priv-sem-compartilhar-proximidade' = 'Opcional'
    'priv-sem-continuar-celular'       = 'Opcional'
    'priv-sem-escrita-ink'             = 'Recomendado'
    'priv-outlook-classico'            = 'Opcional'
    'sis-servicos-manual'              = 'Atencao', 'Os serviços continuam lá e ligam quando precisam, mas um recurso pouco usado pode demorar alguns segundos a mais na primeira vez.', $reiniciar
    'sis-wpbt'                         = 'Recomendado'
    'sis-storage-sense'                = 'Opcional'
    'sis-caminhos-longos'              = 'Recomendado'
    'sis-tela-azul-detalhada'          = 'Recomendado'
    'sis-login-detalhado'              = 'Opcional'
    'sis-sem-tela-bloqueio'            = 'Opcional'
    'sis-config-sem-inicio'            = 'Opcional'
    'sis-apps-segundo-plano'           = 'Atencao', 'Apps da Microsoft Store (WhatsApp, Teams, Spotify da Store) param de mostrar notificações e de atualizar enquanto estão fechados.', $desfazer
    'sis-sem-notificacoes'             = 'Atencao', 'Nenhuma notificação aparece: nem de mensagens, nem de lembretes, nem avisos do Windows.', $reiniciar
    'sis-sem-assistente-compatibilidade' = 'Atencao', 'Programas muito antigos deixam de receber os consertos automáticos que o Windows aplica e podem não abrir.', $desfazer
    'sis-sem-registro-rsop'            = 'Opcional'
    'sis-sem-dicas'                    = 'Recomendado'
    'sis-config-sem-dicas'             = 'Recomendado'
    'sis-sem-conteudo-nuvem'           = 'Recomendado'
    'sis-sem-autoplay'                 = 'Recomendado'
    'sis-abrir-com-sem-loja'           = 'Recomendado'
    'sis-sem-aviso-disco'              = 'Atencao', 'O disco pode encher sem nenhum aviso; com o disco cheio, o Windows fica lento e atualizações falham.', $desfazer
    'sis-sem-aviso-usb'                = 'Opcional'
    'sis-sem-insider'                  = 'Opcional'
    'sis-atualizacao-sem-insistir'     = 'Opcional'
    'sis-loja-sem-atualizar-sozinha'   = 'Atencao', 'Os apps da Microsoft Store ficam desatualizados até você abrir a Store e atualizar à mão (Biblioteca > Obter atualizações).', $desfazer
    'expl-extensoes'                   = 'Recomendado'
    'expl-ocultos'                     = 'Opcional', 'Aparecem arquivos e pastas de sistema que o Windows escondia; apagar um deles pode estragar algum programa.', $desfazer
    'expl-abrir-este-computador'       = 'Opcional'
    'expl-sem-inicio-galeria'          = 'Opcional'
    'expl-sem-autodescoberta'          = 'Recomendado'
    'expl-menu-classico'               = 'Opcional'
    'expl-sem-texto-atalho'            = 'Recomendado'
    'expl-detalhes-copia'              = 'Opcional'
    'expl-sem-caixas-selecao'          = 'Opcional'
    'expl-modo-compacto'               = 'Opcional'
    'expl-menu-completo-varios'        = 'Opcional'
    'expl-sem-arquivos-office'         = 'Opcional'
    'expl-sem-recentes'                = 'Atencao', 'Somem as listas de arquivos recentes do Explorador, do menu Iniciar e de "Abrir recente" em vários programas.', $desfazer
    'expl-sem-procurar-atalhos'        = 'Opcional'
    'expl-dica-rapida'                 = 'Opcional'
    'expl-este-computador-sem-pastas'  = 'Opcional'
    'expl-busca-classica'              = 'Atencao', 'A busca dentro das pastas volta a ser a antiga: sem sugestões e às vezes mais lenta.', $reiniciar
    'expl-finalizar-tarefa'            = 'Recomendado'
    'barra-icones-esquerda'            = 'Opcional'
    'barra-sem-busca'                  = 'Opcional'
    'barra-sem-visao-tarefas'          = 'Opcional'
    'barra-sem-recomendados'           = 'Opcional'
    'barra-porcentagem-bateria'        = 'Opcional'
    'barra-iniciar-antigo'             = 'Atencao', 'Usa uma opção escondida do Windows: uma atualização pode desligá-la ou deixar o menu Iniciar com cara estranha.', $reiniciar
    'barra-sem-widgets'                = 'Atencao', 'Remove o pacote dos Widgets: o painel de notícias e clima some (Win+W não abre nada).', 'Instale de novo pela Microsoft Store o "Windows Web Experience Pack" e reinicie.'
    'barra-sem-chat'                   = 'Recomendado'
    'barra-sem-reuniao'                = 'Recomendado'
    'barra-alt-tab-sem-abas'           = 'Recomendado'
    'barra-iniciar-sem-sugestoes'      = 'Recomendado'
    'barra-iniciar-mais-fixados'       = 'Opcional'
    'aparencia-tema-escuro'            = 'Opcional'
    'aparencia-efeitos-desempenho'     = 'Opcional', 'O Windows fica com cara mais simples: sem sombras, animações e fontes suavizadas em alguns lugares.', $desfazer
    'aparencia-barras-rolagem'         = 'Opcional'
    'aparencia-sem-desfoque-login'     = 'Opcional'
    'janela-sem-encaixe'               = 'Opcional'
    'aparencia-sem-iluminacao-dinamica' = 'Opcional'
    'aparencia-papel-parede-qualidade' = 'Opcional'
    'aparencia-sem-peek'               = 'Opcional'
    'aparencia-sem-sacudir'            = 'Opcional'
    'aparencia-sem-sons-acessibilidade' = 'Opcional'
    'aparencia-ocultar-sons-desligados' = 'Opcional'
    'mouse-sem-aceleracao'             = 'Opcional'
    'acess-teclas-aderentes'           = 'Recomendado'
    'teclado-numlock'                  = 'Opcional'
    'jogos-modo-jogo'                  = 'Recomendado'
    'sis-desligar-mais-rapido'         = 'Atencao', 'Ao desligar, programas abertos têm menos tempo para fechar: um documento não salvo pode se perder.', $desfazer
    'sis-iniciar-sem-atraso'           = 'Opcional'
    'jogos-mmcss'                      = 'Opcional'
    'jogos-prioridade-primeiro-plano'  = 'Opcional'
    'jogos-sem-game-bar'               = 'Atencao', 'Win+G não abre nada e não dá mais para gravar ou capturar jogos pela Xbox Game Bar.', $desfazer
    'jogos-sem-som-reduzido'           = 'Opcional'
    'jogos-cache-icones-maior'         = 'Opcional'
    'energia-sem-hibernacao'           = 'Atencao', 'Some a opção Hibernar e a Inicialização Rápida: o computador demora um pouco mais para ligar; no notebook, a bateria acaba se ficar muito tempo em suspensão.', $desfazer
    'energia-desempenho-maximo'        = 'Atencao', 'O computador gasta mais energia e esquenta mais; no notebook, a bateria dura bem menos.', 'Volte ao plano Equilibrado em Configurações > Sistema > Energia, ou desfaça na página Ajustes.'
    'energia-rede-espera'              = 'Opcional'
    'sis-manutencao-sem-acordar'       = 'Recomendado'
    'rede-sem-llmnr'                   = 'Atencao', 'Impressoras ou computadores antigos da rede podem não ser achados pelo nome.', $reiniciar
    'rede-smb-sem-limite'              = 'Opcional'
    'rede-sem-acesso-anonimo'          = 'Atencao', 'Pastas compartilhadas de aparelhos antigos (NAS, roteador, impressora) que não pedem senha podem parar de abrir.', $reiniciar
    'rede-dns-google'                  = 'Atencao', 'Algumas redes (empresa, escola, Wi-Fi de hotel com página de login) só funcionam com o DNS do próprio roteador.', 'Desfaça na página Ajustes (o DNS volta para o automático) ou, nessa rede, use outra conexão até sair dela.'
    'rede-dns-cloudflare'              = 'Atencao', 'Algumas redes (empresa, escola, Wi-Fi de hotel com página de login) só funcionam com o DNS do próprio roteador.', 'Desfaça na página Ajustes (o DNS volta para o automático).'
    'rede-dns-cloudflare-malware'      = 'Atencao', 'Bloqueia sites conhecidos por malware (às vezes algum site legítimo cai junto) e pode não funcionar em redes de empresa, escola ou hotel.', 'Desfaça na página Ajustes (o DNS volta para o automático).'
    'rede-dns-cloudflare-familia'      = 'Atencao', 'Bloqueia sites adultos e de malware para todo o computador; pode não funcionar em redes de empresa, escola ou hotel.', 'Desfaça na página Ajustes (o DNS volta para o automático).'
    'rede-dns-opendns'                 = 'Atencao', 'Algumas redes (empresa, escola, Wi-Fi de hotel com página de login) só funcionam com o DNS do próprio roteador.', 'Desfaça na página Ajustes (o DNS volta para o automático).'
    'rede-dns-quad9'                   = 'Atencao', 'Bloqueia sites conhecidos por malware e pode não funcionar em redes de empresa, escola ou hotel.', 'Desfaça na página Ajustes (o DNS volta para o automático).'
    'rede-dns-adguard'                 = 'Atencao', 'Bloqueia anúncios e rastreadores no computador todo: algum site ou app pode quebrar (botão que não carrega, vídeo que não toca).', 'Desfaça na página Ajustes (o DNS volta para o automático).'
    'rede-dns-adguard-familia'         = 'Atencao', 'Bloqueia anúncios, sites adultos e força a busca segura: algum site ou app pode quebrar.', 'Desfaça na página Ajustes (o DNS volta para o automático).'
    'rede-dns-mais-rapido'             = 'Atencao', 'Algumas redes (empresa, escola, Wi-Fi de hotel com página de login) só funcionam com o DNS do próprio roteador.', 'Desfaça na página Ajustes (o DNS volta para o automático).'
    'nav-edge-limpo'                   = 'Atencao', 'O Edge passa a mostrar "Seu navegador é gerenciado pela sua organização" (é assim que o Windows aplica essas regras).', $desfazer
    'nav-brave-limpo'                  = 'Atencao', 'O Brave passa a mostrar "Gerenciado pela sua organização" e alguns recursos (carteira, VPN, Leo) somem.', $desfazer
}

# Apps do Windows: Recomendado = propaganda ou quase ninguém usa; Atencao = tem uso de verdade.
$apps = @{
    'app-windowsfeedbackhub' = 'Recomendado'; 'app-gethelp' = 'Recomendado'; 'app-outlookforwindows' = 'Opcional'; 'app-msteams' = 'Opcional'
    'app-clipchamp-clipchamp' = 'Recomendado'; 'app-microsoftofficehub' = 'Recomendado'; 'app-bingsearch' = 'Recomendado'; 'app-quickassist' = 'Opcional'
    'app-windows-devhome' = 'Recomendado'; 'app-todos' = 'Opcional'; 'app-powerautomatedesktop' = 'Recomendado'; 'app-windowssoundrecorder' = 'Opcional'
    'app-copilot' = 'Opcional'; 'app-bingnews' = 'Recomendado'; 'app-bingweather' = 'Opcional'; 'app-startexperiencesapp' = 'Recomendado'
    'app-microsoftsolitairecollection' = 'Recomendado'; 'app-zunevideo' = 'Opcional'; 'app-xboxspeechtotextoverlay' = 'Opcional'
}
$appsAtencao = @{
    'app-zunemusic'             = 'Arquivos de música e vídeo deixam de ter um programa padrão para abrir.'
    'app-crossdevice'           = 'Recursos de celular no Windows (fotos e mensagens do celular no PC) param de funcionar.'
    'app-yourphone'             = 'Não dá mais para ver mensagens, chamadas e fotos do celular no computador.'
    'app-microsoftstickynotes'  = 'As notas autoadesivas somem do computador (se você entrou com a conta Microsoft, continuam salvas na nuvem).'
    'app-windowsalarms'         = 'Alarmes, temporizador e cronômetro do Windows param de funcionar.'
    'app-paint'                 = 'Imagens que abriam no Paint ficam sem programa para editar.'
    'app-windowsnotepad'        = 'Arquivos .txt e de configuração ficam sem programa padrão para abrir.'
    'app-screensketch'          = 'Win+Shift+S e a tecla Print Screen param de abrir a captura de tela.'
    'app-windowscalculator'     = 'A calculadora some (inclusive a tecla de calculadora do teclado).'
    'app-windowscamera'         = 'O app Câmera some (a webcam continua funcionando em chamadas de vídeo).'
    'app-windows-photos'        = 'Fotos e imagens ficam sem programa padrão para abrir.'
    'app-gamingapp'             = 'Jogos do Game Pass para PC e da loja Xbox não abrem nem instalam.'
    'app-xboxgamingoverlay'     = 'Win+G não abre nada e a gravação de jogos para de funcionar.'
    'app-xbox-tcui'             = 'Jogos que usam a conta Xbox (Minecraft, Forza, Sea of Thieves) podem não conseguir entrar na conta.'
}
$appsArriscado = @{
    'app-xboxidentityprovider'  = 'Jogos que usam a conta Xbox (Minecraft, Forza, Sea of Thieves, Game Pass) não conseguem entrar na conta e muitos nem abrem.'
}

# "Avançado (por sua conta e risco)": tudo Arriscado, cada um com o seu contratempo.
$avancados = @{
    'avanc-sem-ia'                 = 'O Copilot some e recursos de IA do Windows (Recall, IA no Bloco de Notas e no Paint) param de funcionar; atualizações grandes podem trazer parte de volta.', $reiniciar
    'avanc-remover-onedrive'       = 'Arquivos que estavam só na nuvem deixam de aparecer no PC, e a pasta Documentos/Área de Trabalho pode ficar apontando para a pasta do OneDrive.', 'Desfaça na página Ajustes (reinstala o OneDrive) e entre na conta: os arquivos da nuvem voltam a aparecer.'
    'avanc-remover-edge'           = 'Links de alguns lugares do Windows (ajuda, widgets, busca) não abrem, e alguns programas que abrem páginas pelo Edge reclamam.', 'Desfaça na página Ajustes (reinstala o Edge pelo winget) ou baixe em microsoft.com/edge.'
    'avanc-armazenamento-reservado' = 'Com o disco quase cheio, uma atualização grande do Windows pode falhar por falta de espaço.', $reiniciar
    'avanc-svchost-agrupado'       = 'Se um serviço travar, derruba junto os outros do mesmo processo (som, rede ou Wi-Fi podem cair juntos).', $reiniciar
    'avanc-hora-utc'               = 'Sem Linux no mesmo computador, o relógio do Windows fica com a hora errada (adiantado ou atrasado algumas horas).', "$desfazer Depois acerte a hora em Configurações > Hora e idioma > Sincronizar agora."
    'avanc-sem-mpo'                = 'Em PCs sem o problema de tela piscando, pode deixar vídeos e jogos em janela um pouco mais pesados.', $reiniciar
    'avanc-sem-recall'             = 'O Recall (linha do tempo de capturas da IA) deixa de existir nos PCs Copilot+.', $reiniciar
    'avanc-sem-mpo-total'          = 'Além do anterior, mexe no driver de vídeo: em alguns PCs piora o desempenho de vídeo ou a tela fica preta por um instante ao trocar de janela.', $reiniciar
    'avanc-bloquear-razer'         = 'O Windows Update também para de instalar sozinho apps e drivers de fabricante para aparelhos novos (impressoras, controles, webcams).', 'Instale o driver pelo site do fabricante, ou desfaça na página Ajustes.'
    'avanc-bloquear-logitech'      = 'O assistente da Logitech não reinstala sozinho; para usar o Logi Options+ ou G HUB, instale pelo site da Logitech.', $desfazer
    'acao-oo-shutup'               = 'O O&O ShutUp10++ tem opções que desligam proteções e atualizações do Windows; o que você mudar nele não aparece no Histórico do Tamanduá.', 'No próprio O&O ShutUp10++: menu Ações > "Desfazer todas as alterações", ou use o ponto de restauração.'
    'avanc-rdp-sem-aviso'          = 'Um arquivo .rdp malicioso (por e-mail, por exemplo) abre sem nenhum aviso.', $desfazer
    'avanc-ipv4-preferido'         = 'Serviços que funcionam melhor por IPv6 podem ficar um pouco mais lentos.', $reiniciar
    'avanc-sem-teredo'             = 'O app Xbox pode mostrar "NAT estrito / Teredo não qualifica" e o chat de grupo do Xbox pode falhar.', $reiniciar
    'avanc-sem-ipv6'               = 'Algumas redes e serviços (e partes do próprio Windows, como o Grupo Doméstico e o Xbox) param de funcionar ou ficam lentos.', $reiniciar
    'avanc-bloquear-adobe'         = 'Programas da Adobe instalados de verdade (pagos) param de validar a licença e de atualizar.', $desfazer
    'avanc-sono-s3'                = 'Em muitos notebooks novos o S3 não existe: a suspensão para de funcionar ou o notebook não acorda (precisa desligar no botão).', "$reiniciar Se ele não acordar da suspensão, segure o botão de ligar até desligar e então desfaça."
    'avanc-defender-sem-amostras'  = 'O Defender demora mais a reconhecer vírus novos, que ainda não estão na lista dele.', $desfazer
    'avanc-sem-bitlocker'          = 'O disco fica sem criptografia: quem pegar o computador (ou o SSD) consegue ler seus arquivos. A descriptografia leva tempo.', 'Para criptografar de novo com chave de recuperação: Configurações > Privacidade e segurança > Criptografia do dispositivo (ou BitLocker no Painel de Controle).'
    'sis-memoria-kernel'           = 'Com pouca memória (8 GB ou menos) o computador pode ficar mais lento ou fechar programas por falta de RAM.', $reiniciar
}

function ConvertTo-JsonTexto([string]$Texto) { '"' + ($Texto -replace '\\', '\\' -replace '"', '\"') + '"' }

$catalogo = @([IO.File]::ReadAllText($arquivo, [Text.Encoding]::UTF8) | ConvertFrom-Json | ForEach-Object { $_ })
$porId = @{}
foreach ($a in $catalogo) {
    $id = [string]$a.id
    $nomeApp = ([string]$a.nome) -replace '^Remover:\s*', ''
    $voltaApp = "Instale de novo pela Microsoft Store (procure por `"$nomeApp`")."
    $contra = $null; $seAc = $null
    if ([string]$a.categoria -like 'Avançado*') {
        if (-not $avancados.ContainsKey($id)) { throw "ajuste avançado sem contratempo: $id" }
        $classe = 'Arriscado'; $contra, $seAc = $avancados[$id]
    }
    elseif ($c.ContainsKey($id)) { $v = @($c[$id]); $classe = $v[0]; if ($v.Count -gt 2) { $contra = $v[1]; $seAc = $v[2] } }
    elseif ($apps.ContainsKey($id)) { $classe = $apps[$id] }
    elseif ($appsAtencao.ContainsKey($id)) { $classe = 'Atencao'; $contra = $appsAtencao[$id]; $seAc = $voltaApp }
    elseif ($appsArriscado.ContainsKey($id)) { $classe = 'Arriscado'; $contra = $appsArriscado[$id]; $seAc = $voltaApp }
    else { throw "sem classificação para $id" }
    $porId[$id] = @{ Classe = $classe; Contra = $contra; SeAc = $seAc }
}

# Edita o texto do arquivo (mantém o formato à mão): tira as linhas antigas e põe as novas logo depois de "risco".
$linhas = [IO.File]::ReadAllLines($arquivo, [Text.Encoding]::UTF8)
$saida = [System.Collections.Generic.List[string]]::new()
$atual = $null
foreach ($l in $linhas) {
    if ($l -match '^\s*"id":\s*"([^"]+)"') { $atual = $Matches[1] }
    if ($l -match '^\s*"(classificacao|contratempo|seAcontecer)":') { continue }
    $saida.Add($l)
    if ($atual -and $l -match '^(\s*)"risco":') {
        $recuo = $Matches[1]; $d = $porId[$atual]
        $saida.Add("$recuo`"classificacao`": $(ConvertTo-JsonTexto $d.Classe),")
        if ($d.Contra) { $saida.Add("$recuo`"contratempo`": $(ConvertTo-JsonTexto $d.Contra),") }
        if ($d.SeAc) { $saida.Add("$recuo`"seAcontecer`": $(ConvertTo-JsonTexto $d.SeAc),") }
    }
}
[IO.File]::WriteAllText($arquivo, (($saida -join "`n") + "`n"), (New-Object Text.UTF8Encoding $false))
# Confere que continua JSON válido.
$conferir = @([IO.File]::ReadAllText($arquivo, [Text.Encoding]::UTF8) | ConvertFrom-Json | ForEach-Object { $_ })
$conferir | Group-Object classificacao -NoElement | ForEach-Object { "$($_.Name): $($_.Count)" }
