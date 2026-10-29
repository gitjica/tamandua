# Tamanduá

Limpeza, ajustes e manutenção profunda para Windows. Todos os 12 módulos prontos: status, analisar, limpar, purgar, instaladores, desinstalar, programas, ajustes, recursos, atualizações, otimizar e reparos.

## Uso

```powershell
.\tamandua.ps1            # abre a interface (ou o menu de texto, se a pasta interface faltar)
.\tamandua.ps1 status     # painel do sistema: saúde, CPU, memória, discos, rede, bateria, processos
.\tamandua.ps1 analisar          # unidades e atalhos; na janela, duplo clique abre a pasta
.\tamandua.ps1 analisar C:\Users\voce   # o que ocupa espaço nessa pasta, do maior para o menor
.\tamandua.ps1 instaladores -Simular   # instaladores, ISOs e compactados esquecidos em Downloads (vão para a Lixeira)
.\tamandua.ps1 purgar D:\dev -Simular   # node_modules, target, bin/obj... dos seus projetos, agrupados por projeto
.\tamandua.ps1 programas -Itens vlc,7zip   # instala (ou atualiza) pelo winget, perguntando antes
.\tamandua.ps1 programas -Itens atualizar-tudo   # winget upgrade --all
.\tamandua.ps1 desinstalar      # programas instalados; na janela, marque e confirme (o desinstalador de cada um abre)
.\tamandua.ps1 reparos -Itens sfc,dism   # pede admin uma vez e roda os reparos escolhidos
.\tamandua.ps1 otimizar -Itens dns,icones   # cache de DNS e de ícones (sem admin)
.\tamandua.ps1 recursos -Itens wsl,plataforma-vm   # liga (ou desliga) recursos do Windows; pede admin e reinício
.\tamandua.ps1 atualizacoes -Preset Equilibrado -Simular   # política do Windows Update (nunca desliga as atualizações)
.\tamandua.ps1 limpar -Simular   # quanto liberaria (temporários com mais de 24 h, despejos de falha)
.\tamandua.ps1 limpar            # mostra, pergunta e limpa
.\tamandua.ps1 ajustes -Preset Essencial -Simular   # o que o preset mudaria, e o que já está aplicado
.\tamandua.ps1 ajustes -Itens expl-extensoes        # aplica um ajuste específico (pergunta antes)
.\tamandua.ps1 modulos    # estado de cada módulo
.\tamandua.ps1 historico  # o que já foi removido, ajustado, simulado ou pulado
.\tamandua.ps1 desfazer <id>   # volta um ajuste ao valor de antes (-Simular para ver primeiro)
.\tamandua.ps1 protegidos # sua lista de caminhos que nunca são apagados
.\tamandua.ps1 ajuda
```

Tarefas demoradas (SFC, DISM, instalações...) mostram em qual item estão, quantos faltam e há quanto tempo rodam, na barra da janela e no console. Isso inclui o que roda como administrador.

Se a pasta de um módulo faltar ou quebrar, o resto continua funcionando e `tamandua modulos` diz o que falta.

## Desenvolvimento

Leia [GUIA-DESENVOLVIMENTO.md](GUIA-DESENVOLVIMENTO.md) antes de mexer no código.

```powershell
.\testes\executar.ps1     # lint + todos os testes; precisa estar verde antes de cada commit
```
