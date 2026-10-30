# Plano — próxima sessão

Pedido (30/10/2026): lista de programas pelo FMHY (com as estrelas), classificação de todos os ajustes
(recomendado / perigoso, com o que pode dar errado e como resolver) e ícones com quadrado branco.
Ordem sugerida: 1 → 2 → 3 (o 3 é rápido e pode ir junto do 1).

---

## 1. Programas pelo FMHY

**Regra do usuário:** só fica o que está no FMHY; o que tem ⭐ no FMHY tem estrela no Tamanduá.

### Como o FMHY marca
- Fonte: `github.com/fmhy/edit`, pasta `docs/*.md` (system-tools, file-tools, internet-tools, video-tools, audio,
  image-tools, text-tools, gaming, gaming-tools, privacy, storage, developer-tools, torrenting, downloading…).
- Linha: `* ⭐ **[Nome](link)**, [Outro](link) or [Mais um](link) - Descrição`.
  A estrela vale **só para o primeiro nome em negrito depois de ⭐**; os outros da mesma linha não têm estrela.
- `docs/unsafe.md` lista o que o FMHY condena: nunca pode entrar.

### Resultado do cruzamento de hoje (210 programas atuais)
Cruzamento automático **preliminar** (nome simplificado ou domínio do site):
**158 de 210 aparecem no FMHY, 87 com ⭐, 0 em unsafe.md.**

- **Com ⭐ (87):** Firefox, Google Chrome, LibreWolf, Mullvad Browser, Tor Browser, Betterbird, Chatterino, Proton Mail,
  Signal, Thunderbird, AIMP, Blender, Calibre, EarTrumpet, File Converter, foobar2000, GIMP, HandBrake, ImageGlass,
  IrfanView, MPC-HC, mpc-qt, mpv, OBS Studio, ShareX, VLC, LibreOffice, Obsidian, ONLYOFFICE, Sumatra PDF, Zotero,
  AB Download Manager, AutoHotkey, Bitwarden, Bulk Crap Uninstaller, Cloudflare WARP, CrystalDiskInfo, CrystalDiskMark,
  Ente Auth, Everything, F.lux, GlazeWM, Google Drive, JPEGView, KeePassXC, NanaZip, NVCleanstall, OpenRGB, Parsec,
  PeaZip, Proton Authenticator, Proton Drive, Proton Pass, qBittorrent, StartAllBack, UniGetUI, VirtualBox, WizTree,
  Heroic, Itch.io, Playnite, Prism Launcher, GitHub Desktop, Notepad++, VSCodium, Zed, PowerToys, CPU-Z, GPU-Z,
  HWiNFO, HWMonitor, ImHex, MSI Afterburner, Mullvad VPN, Proton VPN, PuTTY, Rufus, Tailscale, WireGuard,
  Jellyfin Media Player, Jellyfin Server, Kodi, LocalSend, Moonlight, Nextcloud, Sunshine, Syncthing.
- **Não achados (52):** Chromium, Firefox ESR, Floorp, Microsoft Edge, Ungoogled Chromium, Vivaldi, Waterfox, Zen
  Browser, Teams, Slack, Viber, WhatsApp, iTunes, PDF24 Creator, PDFgear, PDFsam, PDF-XChange, 1Password, AnyDesk,
  BlurAutoClicker, HxD, Internet Download Manager, OFGB, OPAutoClicker, SignalRGB, TeamViewer, Wise Program Uninstaller,
  Battle.net, EA App, ES-DE, Ubisoft Connect, Virtual Desktop Streamer, Node.js LTS, .NET 6/8/9/10, Autoruns, DISMTools,
  NTLite, NuGet, OneDrive, Process Explorer, Process Monitor, PsTools, RDCMan, TCPView, Advanced IP Scanner,
  Angry IP Scanner, gsudo, Ventoy, SyncTrayzor.

**Esse cruzamento ainda erra para os dois lados — revisar antes de tirar qualquer coisa:**
- Falso "não achado": **PDF24** está no FMHY com ⭐ (lá é "PDF24", aqui "PDF24 Creator"); as ferramentas Sysinternals
  (Autoruns, Process Explorer…) aparecem como "Sysinternals" ⭐ no system-tools; navegadores podem estar com outro nome.
- Falso "achado": casar pelo domínio pega domínios genéricos (Google Drive casou por `google.com`). Tirar do casamento
  por site: google.com, microsoft.com, apple.com, mozilla.org, github.com, e casar só pelo caminho nesses casos.
- Runtimes (.NET, Visual C++) e o que o próprio Windows precisa não são "programas" do FMHY. **Perguntar ao usuário**
  se eles ficam numa categoria à parte ("Componentes do Windows") mesmo fora do FMHY.
- Gerar uma tabela de revisão (programa → achado em qual linha do FMHY, com ⭐ ou não) e mostrar ao usuário antes de
  apagar.

Script do cruzamento (protótipo): `cruzar-fmhy.ps1` no scratchpad da sessão anterior; a lógica vai para o gerador.
Atenção: em PowerShell 5.1, arquivo .ps1 sem BOM lê o ⭐ errado — usar `[char]0x2B50`.

### Passos
1. `ferramentas/gerar-programas.ps1` passa a ler o FMHY (os `.md` baixados) além do WinUtil:
   - O WinUtil continua dando ID do winget, site e ícone; o FMHY decide **se entra** e **se tem estrela**.
   - Casamento por nome simplificado e, se não der, pelo domínio do site (fora github.com e microsoft.com).
   - Tabela `$Casamentos` no gerador para os casos que o automático erra (nomes diferentes, ex.:
     "Visual C++" ↔ "Visual C++ Redistributable", ".NET" etc.), conferida à mão.
   - Campo novo no catálogo: `"estrela": true` e `"fmhy": "system-tools"` (de onde veio).
2. **Decidido pelo usuário (30/10/2026): adicionar também os programas com ⭐ do FMHY** que têm pacote no winget e
   não estão na lista (ex.: Windhawk, EverythingToolbar, SuperF4). Só os com ⭐, só programas de Windows instaláveis
   (nada de site, extensão de navegador ou ferramenta só web), com o ID do winget conferido por
   `winget show --id X --exact` (só leitura), descrição em português, categoria nossa e ícone baixado pela ferramenta.
   Mostrar a lista dos novos ao usuário antes de gravar no catálogo.
3. Programas que o FMHY lista em `unsafe.md` nunca entram (teste).
4. Tela:
   - Estrela no canto do quadro da grade (ícone ⭐ / glifo E735 do Segoe Fluent, cor de destaque do tema) e na lista.
   - Detalhe: "Recomendado pelo FMHY".
   - Preset "Recomendados (⭐ FMHY)" na barra de presets da página Programas (marca só os não instalados com estrela).
   - Ordem dentro da categoria: com estrela primeiro, depois alfabética.
5. Testes: nada fora do FMHY (fixture `testes/modulos/programas/fmhy-referencia.json` gerada junto), toda estrela do
   FMHY que está no catálogo tem `estrela`, nada de `unsafe.md`, ícone para todo programa novo.
6. Ícones dos programas novos: `ferramentas/baixar-icones-programas.ps1` (já existe) + revisão na folha de contato.

---

## 2. Classificação de todos os ajustes

Vale para **ajustes** (190), **menu-contexto** (31 itens) e **atualizacoes** (políticas do Windows Update).

### Termos (selo colorido em cada linha)
| Selo | Cor | Quando |
|---|---|---|
| **Recomendado** | verde | Bom para quase todo mundo, sem efeito colateral que se note. |
| **Opcional** | neutro | Questão de gosto (tema escuro, segundos no relógio). Não atrapalha nada. |
| **Atenção** | amarelo | Funciona, mas pode dar um *contratempo* em certos casos (algum app reclamar, um recurso sumir). |
| **Arriscado** | vermelho | Mexe em segurança ou em algo que o Windows usa por baixo; só se souber o que está fazendo. |

"Perigoso" aqui não é sobre o que o ajuste faz, e sim **o que pode acontecer depois** e **como sair dessa**.

### Campos novos no catálogo (substituem `risco`)
- `"nivel"`: `Recomendado | Opcional | Atencao | Arriscado`
- `"contratempo"`: o que pode acontecer, em linguagem de gente. Ex.: *"Apps da Microsoft Store podem não abrir a
  página de login."*
- `"seAcontecer"`: o que fazer. Ex.: *"Desfaça este ajuste na página Ajustes (marque e aplique) e reinicie."*,
  ou, quando o desfazer não resolve sozinho: *"Reinstale o app pela Microsoft Store."*
- Teste: `Atencao` e `Arriscado` exigem os dois textos; `Recomendado` não pode ter risco Alto; presets **Mínimo** e
  **Essencial** só com `Recomendado`/`Opcional`; tudo do grupo "Avançado (por sua conta e risco)" é `Arriscado`.

### Tela
- Selo do nível na linha (antes do selo de estado), com a cor da tabela.
- Painel de detalhes: seções "Pode dar problema" e "Se acontecer" quando houver.
- Confirmação: se tiver `Arriscado` marcado, a pergunta lista quais são e pede confirmação explícita.
- CLI: nível na listagem (`[Atenção]`) e o mesmo aviso na confirmação.

### Trabalho
Escrever nível + contratempo + seAcontecer para ~230 itens. Fazer por categoria, com cuidado nos que mais dão
problema na prática: remover apps da Store, desligar serviços (Spooler, Bluetooth, Xbox), Defender/SmartScreen/UAC,
DNS, IPv6/Teredo, OneDrive, hibernação, Copilot/Recall, MPO, itens do menu de contexto de programas.

---

## 3. Ícones com quadrado branco

Detectados hoje (3 ou mais cantos brancos opacos): autoruns, chatgpt, ddu, dismtools, glazewm, kodi, librewolf,
netbird, nomacs, nvclean, protonauth, protonpass, protonvpn, qtox, sunshine, tightvnc, vesktop, waterfox, xournal,
zenbrowser. Ícones com fundo opaco **colorido** (cpu-z, .NET, sublimetext, audacity…) são o desenho do app: ficam.
Vários destes podem sair da lista pelo FMHY; fazer depois da parte 1.

- No `baixar-icones-programas.ps1`: depois de redesenhar, **tirar o fundo branco que encosta na borda**
  (preenchimento a partir dos 4 cantos, tolerância pequena, só pixel quase branco e opaco), sem mexer no branco de
  dentro do desenho.
- Para os que ainda ficarem ruins: fonte melhor em `$Manuais` (Wikimedia / ícone do repositório).
- Teste: nenhum ícone com 3 ou mais cantos brancos opacos.
- Revisão na folha de contato nos dois temas (fundo claro e escuro).

---

## Ao terminar cada parte
Suíte inteira (`.\testes\executar.ps1`), captura da janela (`ferramentas\capturar-interface.ps1 -Modulo …`),
guia atualizado, commit com `Co-Authored-By`, push.
