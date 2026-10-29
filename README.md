# Tamanduá

Limpeza, ajustes e manutenção profunda para Windows. Em desenvolvimento (etapa 6 de 7 do MVP).

## Uso

```powershell
.\tamandua.ps1            # abre a interface (ou o menu de texto, se a pasta interface faltar)
.\tamandua.ps1 status     # painel do sistema: saúde, CPU, memória, discos, rede, bateria, processos
.\tamandua.ps1 limpar -Simular   # quanto liberaria (temporários com mais de 24 h, despejos de falha)
.\tamandua.ps1 limpar            # mostra, pergunta e limpa
.\tamandua.ps1 modulos    # estado de cada módulo
.\tamandua.ps1 historico  # o que já foi removido, ajustado, simulado ou pulado
.\tamandua.ps1 desfazer <id>   # volta um ajuste ao valor de antes (-Simular para ver primeiro)
.\tamandua.ps1 protegidos # sua lista de caminhos que nunca são apagados
.\tamandua.ps1 ajuda
```

Por enquanto existem o núcleo e os módulos `status` e `limpar`. Os outros aparecem como `faltando`, e o programa funciona assim mesmo.

## Desenvolvimento

Leia [GUIA-DESENVOLVIMENTO.md](GUIA-DESENVOLVIMENTO.md) antes de mexer no código.

```powershell
.\testes\executar.ps1     # lint + todos os testes; precisa estar verde antes de cada commit
```
