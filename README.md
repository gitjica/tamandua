# Tamanduá

Limpeza, ajustes e manutenção profunda para Windows. MVP completo (etapas 1 a 7) + módulo analisar. Próximos módulos: programas, purgar, instaladores, desinstalar, recursos, otimizar, reparos, atualizações.

## Uso

```powershell
.\tamandua.ps1            # abre a interface (ou o menu de texto, se a pasta interface faltar)
.\tamandua.ps1 status     # painel do sistema: saúde, CPU, memória, discos, rede, bateria, processos
.\tamandua.ps1 analisar          # unidades e atalhos; na janela, duplo clique abre a pasta
.\tamandua.ps1 analisar C:\Users\voce   # o que ocupa espaço nessa pasta, do maior para o menor
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

Por enquanto existem o núcleo e os módulos `status`, `analisar`, `limpar` e `ajustes`. Os outros aparecem como `faltando`, e o programa funciona assim mesmo.

## Desenvolvimento

Leia [GUIA-DESENVOLVIMENTO.md](GUIA-DESENVOLVIMENTO.md) antes de mexer no código.

```powershell
.\testes\executar.ps1     # lint + todos os testes; precisa estar verde antes de cada commit
```
