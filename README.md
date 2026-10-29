# Tamanduá

Limpeza, ajustes e manutenção profunda para Windows. Em desenvolvimento (etapa 1 de 7 do MVP).

## Uso

```powershell
.\tamandua.ps1 modulos    # estado de cada módulo
.\tamandua.ps1 ajuda
```

Por enquanto só o núcleo existe: todos os módulos aparecem como `faltando`, e o programa funciona assim mesmo.

## Desenvolvimento

Leia [GUIA-DESENVOLVIMENTO.md](GUIA-DESENVOLVIMENTO.md) antes de mexer no código.

```powershell
.\testes\executar.ps1     # lint + todos os testes; precisa estar verde antes de cada commit
```
