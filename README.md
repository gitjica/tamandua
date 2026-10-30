# Tamanduá

Limpeza, ajustes e manutenção profunda para Windows. 12 módulos: status, limpar, instaladores, desinstalar, programas, ajustes, menu de contexto, fonte, recursos, atualizações, otimizar e reparos.

## Como abrir

**Jeito mais rápido**: abra o PowerShell (botão direito no Iniciar > Terminal) e cole:

```powershell
irm gitjica.github.io/tamandua | iex
```

Ele baixa a versão mais nova do GitHub, guarda em `%LOCALAPPDATA%\Tamandua\app` e abre. Rodar de novo atualiza
(o histórico e as configurações ficam). O endereço curto é a página do GitHub Pages (`docs/index.html`, que também é
um script: para o PowerShell o HTML é comentário e sobra só a linha abaixo). O endereço completo continua valendo:

```powershell
irm https://raw.githubusercontent.com/gitjica/tamandua/main/instalar.ps1 | iex
```

**Ou baixando**: baixe a pasta inteira (no GitHub: **Code > Download ZIP**, e extraia) e dê dois cliques em **`Tamandua.cmd`**.
Ele pede permissão de administrador uma vez (dá para recusar: abre assim mesmo, e o que precisar pede na hora).

- Por que o `.cmd` e não o `.ps1`: o Windows vem com scripts do PowerShell bloqueados (política "Restricted") e
  bloqueia também scripts baixados da internet. O `Tamandua.cmd` abre com `-ExecutionPolicy Bypass`, que vale só
  para aquela execução: não muda nenhuma configuração do Windows.
- Se o Windows mostrar "O Windows protegeu o computador" ou "Deseja executar este arquivo?", é porque ele veio da
  internet: clique em **Mais informações > Executar assim mesmo** (ou **Executar**).
- Pelo terminal: `powershell -ExecutionPolicy Bypass -File .\tamandua.ps1` (o PowerShell 7 também serve: o programa
  se abre de novo no Windows PowerShell 5.1, que é para o qual foi feito).
- Não abriu? O motivo fica em `%LOCALAPPDATA%\Tamandua\logs\erro-ao-abrir.txt` (versão do Windows, do PowerShell,
  política de scripts e o erro completo). Mande esse arquivo para quem for ajudar.

## Uso

```powershell
.\tamandua.ps1            # abre a interface (pede admin uma vez, como o WinUtil; recusar abre assim mesmo)
.\tamandua.ps1 status     # painel do sistema: saúde, CPU, memória, discos, rede, bateria, processos
.\tamandua.ps1 instaladores -Simular   # instaladores, ISOs e compactados esquecidos em Downloads (vão para a Lixeira)
.\tamandua.ps1 programas -Itens vlc,7zip   # instala (ou atualiza) pelo winget, perguntando antes
.\tamandua.ps1 programas -Itens atualizar-tudo   # winget upgrade --all
.\tamandua.ps1 desinstalar      # programas instalados; na janela, marque e confirme (o desinstalador de cada um abre)
.\tamandua.ps1 reparos -Itens sfc,dism   # pede admin uma vez e roda os reparos escolhidos
.\tamandua.ps1 otimizar -Itens dns,icones   # cache de DNS e de ícones (sem admin)
.\tamandua.ps1 recursos -Itens wsl,plataforma-vm   # liga (ou desliga) recursos do Windows; pede admin e reinício
.\tamandua.ps1 fonte -Itens fam-arial,tam-95   # Arial no lugar da Segoe UI, a 95%; vale depois de reiniciar (volta: -Itens segoe-original)
.\tamandua.ps1 atualizacoes -Preset Equilibrado -Simular   # política do Windows Update (nunca desliga as atualizações)
.\tamandua.ps1 limpar -Simular   # quanto liberaria: temporários, relatórios de erro, logs, caches do Windows, navegadores, Discord, Spotify, Steam...
.\tamandua.ps1 limpar            # mostra, pergunta e limpa (o que pede admin vai num único UAC)
.\tamandua.ps1 limpar -Itens spotify,discord   # só essas categorias (o programa precisa estar fechado)
.\tamandua.ps1 ajustes -Preset Essencial -Simular   # o que o preset mudaria, e o que já está aplicado
                         # todos os tweaks do WinUtil; presets: Mínimo, Essencial, Avançado, Notebook, Desempenho, Privacidade, Explorador
.\tamandua.ps1 ajustes -Itens expl-extensoes        # aplica um ajuste específico (pergunta antes)
.\tamandua.ps1 modulos    # estado de cada módulo
.\tamandua.ps1 historico  # o que já foi removido, ajustado, simulado ou pulado
.\tamandua.ps1 desfazer <id>   # volta um ajuste ao valor de antes (-Simular para ver primeiro)
.\tamandua.ps1 protegidos # sua lista de caminhos que nunca são apagados
.\tamandua.ps1 ajuda
```

A janela abre em ~3,5 s e já mostra o Status; as outras páginas são lidas em segundo plano e abrem na hora (F5 lê de novo).

Tarefas demoradas (SFC, DISM, instalações...) mostram em qual item estão, quantos faltam e há quanto tempo rodam, na barra da janela e no console. Isso inclui o que roda como administrador.

Se a pasta de um módulo faltar ou quebrar, o resto continua funcionando e `tamandua modulos` diz o que falta.

## Desenvolvimento

Leia [GUIA-DESENVOLVIMENTO.md](GUIA-DESENVOLVIMENTO.md) antes de mexer no código.

```powershell
.\testes\executar.ps1     # lint + todos os testes; precisa estar verde antes de cada commit
.\ferramentas\medir-tempos.ps1 -Vezes 3   # tempo de abrir o programa e cada módulo, na janela de verdade
```
