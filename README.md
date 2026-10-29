# Tamanduá

Limpeza, ajustes e manutenção profunda para Windows. Em desenvolvimento (etapa 3 de 7 do MVP).

## Uso

```powershell
.\tamandua.ps1            # abre a interface (ou o menu de texto, se a pasta interface faltar)
.\tamandua.ps1 status     # painel do sistema: saúde, CPU, memória, discos, rede, bateria, processos
.\tamandua.ps1 modulos    # estado de cada módulo
.\tamandua.ps1 ajuda
```

Por enquanto existem o núcleo e o módulo `status`. Os outros aparecem como `faltando`, e o programa funciona assim mesmo.

## Desenvolvimento

Leia [GUIA-DESENVOLVIMENTO.md](GUIA-DESENVOLVIMENTO.md) antes de mexer no código.

```powershell
.\testes\executar.ps1     # lint + todos os testes; precisa estar verde antes de cada commit
```
