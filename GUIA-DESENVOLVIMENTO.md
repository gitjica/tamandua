# Tamanduá — Guia de Desenvolvimento

> Limpeza, ajustes e manutenção profunda para Windows.
> Inspirado no [Mole](https://github.com/tw93/Mole) (limpeza, macOS) e no [WinUtil](https://github.com/ChrisTitusTech/winutil) (ajustes, programas e interface, Windows).
> O tamanduá vai lá no fundo com a língua pra catar formiga; o Tamanduá vai lá no fundo do sistema pra catar lixo.

Este documento é o contrato do projeto. Toda decisão de código deve seguir o que está aqui.
Se algo aqui estiver errado ou faltando, **atualize o guia antes** de escrever o código.

---

## 1. Princípios

1. **Modular de verdade.** Cada funcionalidade é um módulo independente. Se um módulo não existir,
   estiver quebrado ou não puder rodar nesta máquina, o programa continua funcionando e mostra
   o estado dele (`faltando`, `quebrado`, `indisponível`) com o motivo. A interface gráfica também
   é opcional: sem ela, a linha de comando funciona igual.
2. **Seguro por padrão.** Nada é apagado ou alterado sem antes ser listado. Na dúvida, não mexe.
   É melhor deixar 1 GB de lixo do que apagar 1 arquivo do usuário.
3. **Descobrir ≠ executar.** Todo módulo separa *encontrar o que fazer* (somente leitura)
   de *fazer* (escrita). Isso deixa a simulação (`-Simular`) e os testes triviais.
4. **Tudo que muda o sistema pode ser desfeito.** Antes de alterar registro, serviço ou tarefa,
   o Tamanduá grava o valor **que estava lá de verdade**, não um valor padrão suposto.
5. **Mostrar o estado real.** A interface diz o que *já está* aplicado nesta máquina, lido do sistema,
   em vez de só oferecer checkboxes no escuro.
6. **Testado sempre.** Toda mudança roda a suíte de testes. Testes nunca tocam o sistema real —
   usam pastas e chaves de registro falsas (sandbox).
7. **Sem dependências para o usuário.** Roda no PowerShell 5.1 que já vem no Windows 10/11.
   Funciona também no PowerShell 7, mas não exige.
8. **Sem admin para abrir.** O programa abre como usuário comum e pede elevação só para a ação que precisa.
9. **Eficiente e responsivo.** Varre disco com .NET (`EnumerateFiles`), não com `Get-ChildItem -Recurse`.
   Na interface, nenhum trabalho roda na thread da janela: ela nunca congela.

---

## 2. Referências: o que pegar e o que melhorar

### Do Mole

Pegamos: limpeza por categorias, purgar artefatos de projeto, instaladores esquecidos, desinstalar com restos,
`--dry-run`, lista de proteção, log de operações (`history`), guardas de segurança (nunca seguir link,
desmarcar o que é recente, reconfirmar antes de apagar).

### Do WinUtil

Pegamos:

- **Ajustes declarativos.** Cada ajuste é um dado (registro, serviço, script de aplicar/desfazer), não código solto. O motor executa.
- **Catálogo de programas** com IDs do winget, por categoria, com marcação de software livre.
- **Presets** (ex.: "Essencial", "Mínimo") que marcam um conjunto de ajustes de uma vez.
- **Recursos do Windows, reparos e atualizações** como abas próprias.
- **Interface WPF** com abas, busca e seleção em lote — o usuário gosta, é a base.
- XAML separado, Pester + PSScriptAnalyzer.

Melhoramos (problemas conhecidos do WinUtil que o Tamanduá **não** repete):

| WinUtil | Tamanduá |
|---|---|
| Desfazer usa um `OriginalValue` fixo no JSON (o que *se supõe* ser o padrão) | Desfazer restaura o valor **lido da máquina** antes da alteração (snapshot) |
| Não mostra se o ajuste já está aplicado | Cada item mostra estado real: aplicado / não aplicado / parcial / desconhecido |
| Não mostra o que um ajuste vai mexer | Painel de detalhes: lista exata de chaves, valores, serviços e comandos |
| Exige rodar tudo como admin | Abre sem admin; eleva só a ação que precisa |
| Interface trava em tarefas longas | Todo trabalho em runspace, com progresso e botão de cancelar |
| Paredes de checkboxes sem hierarquia de risco | Selo de risco (baixo/médio/alto), itens de risco alto nunca vêm marcados |
| Tudo compilado num script gigante com um objeto global `$sync` | Pastas de módulos independentes; a interface só conversa com o núcleo |
| Execução via `irm | iex` | Distribuição como pasta/zip versionado (e assinado, quando possível) |
| Sem histórico do que foi alterado | Aba **Histórico** com tudo que foi feito e botão de desfazer por item |

### Licenças

- Mole é **GPL-3.0**: pegamos só ideias, **nenhum código**.
- WinUtil é **MIT**: se adaptarmos dados do catálogo (lista de ajustes, IDs de programas), manter crédito em `CREDITOS.md`.
  Mesmo assim, todo ajuste adaptado é revisado e testado aqui — não confiamos cegamente no valor de lá.

---

## 3. Stack

| Item | Escolha | Por quê |
|---|---|---|
| Linguagem | PowerShell 5.1 (compatível com 7.x) | Já instalado em todo Windows; acesso nativo a registro, CIM, serviços |
| Interface | WPF (`PresentationFramework`) com XAML em arquivo separado | Já vem no Windows, é o que o WinUtil usa, dá pra fazer bonito |
| Trabalho em segundo plano | Runspaces | Mantém a janela responsiva |
| Programas | winget (obrigatório para o módulo `programas`; se não houver, módulo fica `indisponível`) | Oficial da Microsoft |
| Testes | Pester 5 ou mais novo, testado com 6.2 (`Install-Module Pester -Scope CurrentUser -Force -SkipPublisherCheck`) | Padrão do ecossistema |
| Lint | PSScriptAnalyzer (`Install-Module PSScriptAnalyzer -Scope CurrentUser`) | Pega erros comuns antes de rodar |
| Manifestos e catálogos | `.psd1` (lido com `Import-PowerShellDataFile`) para manifestos; `.json` para catálogos grandes (ajustes, programas) | Nativo, sem parser externo |
| Logs | JSON Lines em `%LOCALAPPDATA%\Tamandua\logs\operacoes.jsonl` | Fácil de ler, filtrar e mostrar no Histórico |

### Regras de compatibilidade com PowerShell 5.1

- **Arquivos `.ps1`/`.psm1`/`.psd1` em UTF-8 *com BOM*.** Sem BOM, o 5.1 lê acentos errado (`Tamanduá` vira `TamanduÃ¡`).
  `.json` e `.xaml` em UTF-8 (lidos com `-Encoding UTF8` explícito).
- Proibido: `&&`, `||`, `??`, `?.`, operador ternário, `ForEach-Object -Parallel`, `ConvertFrom-Json -AsHashtable`.
- `Set-Content`/`Add-Content` sempre com `-Encoding UTF8`.
- `ConvertFrom-Json` de uma lista JSON devolve a lista inteira como **um** objeto no 5.1: desmonte com `foreach ($x in (... | ConvertFrom-Json)) { $x }`.
- `$x = if (...) { @(...) } else { ... }` desmonta o array (um item vira escalar, nenhum vira `$null`): use `$x = @(if ...)`.
- `@($param).Count` com um `[string[]]` nulo lança em StrictMode no 5.1: `$lista = @(); if ($param) { $lista = @($param) }`.
- Loops pesados de arquivo vão para C# (`Add-Type`), como `Tamandua.Medidor` em `nucleo/Remocao.ps1`: mede ~95 mil arquivos em ~3 s.
- Testes: nada de `<...>` no nome de `It`/`Describe` fora de `-ForEach` — o Pester tenta expandir como variável.
- Testes: `-Skip:(...)` é avaliado na descoberta; o que ele usa vem de `BeforeDiscovery`, não de `BeforeAll`.
- `$lista.Propriedade` numa lista vazia lança em StrictMode: use `$lista | ForEach-Object { $_.Propriedade }`.
- Variáveis não diferenciam maiúsculas: um `$catalogo` local sobrescreve o parâmetro `$Catalogo`.
- `-and` e `-or` têm a mesma precedência (avaliados da esquerda para a direita): use parênteses.
- Função que devolve array tipado (`[byte[]]`, `[string[]]`) usa `return , $array`; sem a vírgula vira `Object[]`.
- `StrictMode Latest` lança em índice fora do array (`$a[-1]` em array vazio) e em propriedade que não existe:
  objetos vindos de JSON são lidos com `Get-Propriedade`.
- Nada de `2>&1` em executáveis nativos.
- `Import-PowerShellDataFile` (e outros cmdlets que no 5.1 são funções) ignoram o `$ErrorActionPreference` do chamador:
  sempre passar `-ErrorAction Stop` quando o erro precisa ser capturado.
- `-Include`/`-Exclude` são ignorados junto com `-LiteralPath`: filtrar com `Where-Object { $_.Extension -in ... }`.

---

## 4. Estrutura de pastas

```
Tamandua/
├─ tamandua.ps1                 # ponto de entrada: sem argumentos abre a interface; com argumentos, CLI
├─ GUIA-DESENVOLVIMENTO.md      # este arquivo
├─ README.md                    # uso, para o usuário final
├─ CREDITOS.md                  # atribuições (WinUtil etc.)
├─ nucleo/
│  ├─ Tamandua.Nucleo.psm1      # carrega as partes abaixo
│  ├─ Carregador.ps1            # descobre e valida módulos
│  ├─ Seguranca.ps1             # validação de caminhos, caminhos protegidos
│  ├─ Remocao.ps1               # ÚNICO lugar que apaga arquivos
│  ├─ MotorAjustes.ps1          # ÚNICO lugar que escreve registro/serviço/tarefa (aplicar, verificar, desfazer)
│  ├─ Estado.ps1                # snapshots para desfazer
│  ├─ Elevacao.ps1              # detectar admin, reexecutar uma ação elevada
│  ├─ Saida.ps1                 # cores, tabelas, tamanhos legíveis (CLI)
│  ├─ Registro.ps1              # log de operações
│  ├─ Config.ps1                # config do usuário e lista de proteção
│  └─ catalogo.psd1             # lista dos módulos que o Tamanduá conhece
├─ interface/                   # OPCIONAL: sem esta pasta, só a CLI funciona
│  ├─ Interface.psm1            # Start-TmdInterface: monta a janela e mostra
│  ├─ janela.xaml               # layout principal (sem eventos; tudo por x:Name)
│  ├─ tema-claro.xaml           # cores do tema claro (único lugar com cor fixa, junto com o escuro)
│  ├─ tema-escuro.xaml          # mesmas chaves, tema escuro
│  ├─ estilos.xaml              # estilos; cores só por DynamicResource
│  ├─ Janela.ps1                # carrega XAML, troca tema, barra de título escura
│  ├─ Paginas.ps1               # barra lateral, página, detalhes, busca, barra de ação
│  ├─ Conversao.ps1             # funções puras: dados do núcleo -> linhas da tela
│  └─ SegundoPlano.ps1          # tarefas em runspace + relógio que entrega na thread da janela
├─ ferramentas/
│  └─ capturar-interface.ps1    # salva PNG da janela (revisão visual)
├─ modulos/
│  ├─ status/                   # cada módulo é uma pasta
│  │  ├─ modulo.psd1            # manifesto
│  │  ├─ status.psm1            # implementação
│  │  └─ pagina.xaml            # OPCIONAL: página na interface; sem ela, usa página genérica
│  ├─ analisar/
│  ├─ limpar/
│  ├─ purgar/
│  ├─ instaladores/
│  ├─ desinstalar/
│  ├─ otimizar/
│  ├─ ajustes/                  # + ajustes.json (catálogo declarativo) + presets.json
│  ├─ programas/                # + programas.json (IDs winget)
│  ├─ recursos/                 # recursos opcionais do Windows
│  ├─ reparos/                  # sfc, DISM, rede, Windows Update
│  └─ atualizacoes/             # política de atualizações
├─ config/
│  └─ protegidos.padrao.txt     # padrões que nunca são tocados (o usuário estende em %APPDATA%)
└─ testes/
   ├─ executar.ps1              # roda tudo: lint + testes
   ├─ Ajudantes.ps1             # sandbox de arquivos e de registro
   ├─ nucleo/
   ├─ contrato/                 # testa TODO módulo e TODO item de catálogo automaticamente
   ├─ resiliencia/              # módulo/interface faltando ou quebrado não derruba o programa
   ├─ interface/                # XAML carrega, controles existem, estados aparecem
   └─ modulos/<nome>/
```

Pastas de dados do usuário (criadas sob demanda, nunca dentro da pasta do programa):

- `%APPDATA%\Tamandua\config.psd1`, `protegidos.txt`, `perfis\*.json` — configuração e seleções salvas
- `%LOCALAPPDATA%\Tamandua\logs\` — logs de operação
- `%LOCALAPPDATA%\Tamandua\estado\` — snapshots para desfazer
- `%LOCALAPPDATA%\Tamandua\backup\` — `reg export` das chaves antes de alterar

---

## 5. Contrato de módulo

### 5.1 Catálogo de módulos

`nucleo/catalogo.psd1` lista todos os módulos que o Tamanduá **conhece**. É assim que o
programa sabe dizer que algo está *faltando* (não dá pra avisar que falta algo que ninguém declarou).

```powershell
@{
    Modulos = @(
        @{ Nome = 'status';       Grupo = 'Sistema';    Descricao = 'Painel do sistema (CPU, memória, disco, rede)' }
        @{ Nome = 'analisar';     Grupo = 'Limpeza';    Descricao = 'Mostra o que ocupa espaço no disco' }
        @{ Nome = 'limpar';       Grupo = 'Limpeza';    Descricao = 'Remove caches, temporários e logs' }
        @{ Nome = 'purgar';       Grupo = 'Limpeza';    Descricao = 'Remove artefatos de projeto (node_modules, target...)' }
        @{ Nome = 'instaladores'; Grupo = 'Limpeza';    Descricao = 'Encontra instaladores esquecidos (.exe, .msi, .iso)' }
        @{ Nome = 'desinstalar';  Grupo = 'Programas';  Descricao = 'Desinstala programas e restos' }
        @{ Nome = 'programas';    Grupo = 'Programas';  Descricao = 'Instala e atualiza programas via winget' }
        @{ Nome = 'ajustes';      Grupo = 'Ajustes';    Descricao = 'Privacidade, desempenho e preferências (reversível)' }
        @{ Nome = 'recursos';     Grupo = 'Ajustes';    Descricao = 'Recursos opcionais do Windows (WSL, Hyper-V, .NET 3.5...)' }
        @{ Nome = 'atualizacoes'; Grupo = 'Ajustes';    Descricao = 'Política do Windows Update' }
        @{ Nome = 'otimizar';     Grupo = 'Manutenção'; Descricao = 'Tarefas de manutenção do Windows' }
        @{ Nome = 'reparos';      Grupo = 'Manutenção'; Descricao = 'SFC, DISM, reset de rede e do Windows Update' }
    )
}
```

Uma pasta em `modulos/` que **não** está no catálogo também é carregada (módulo extra), desde que cumpra o contrato.

### 5.2 Manifesto (`modulo.psd1`)

```powershell
@{
    Nome           = 'limpar'
    Versao         = '0.1.0'
    Descricao      = 'Remove caches, temporários e logs'
    Arquivo        = 'limpar.psm1'
    Escreve        = $true      # $false = módulo só leitura (status, analisar)
    RequerAdmin    = $false     # $true = o módulo inteiro precisa de admin
    ContratoMinimo = 1          # versão do contrato que ele implementa
    Icone          = 'vassoura' # nome de ícone do tema da interface
}
```

### 5.3 Funções obrigatórias

Todo `.psm1` exporta estas funções (nomes fixos; o núcleo chama cada uma pela referência do próprio módulo,
`$modulo.ExportedFunctions['Find-Alvos']`, então nomes iguais em módulos diferentes não colidem):

| Função | Obrigatória | Faz | Pode escrever? |
|---|---|---|---|
| `Test-Requisitos` | sim | Diz se pode rodar aqui. Retorna `@{ Ok = $bool; Motivo = 'texto' }` | **não** |
| `Find-Alvos` | sim | Descobre o que seria feito e o **estado atual** de cada item. Retorna lista de `Alvo` | **não** |
| `Invoke-Acao` | se `Escreve = $true` | `-Alvos <objetos de Find-Alvos> [-Simular]`. Executa **somente** nos alvos recebidos e devolve um `Resultado` por alvo | sim, via núcleo |
| `Undo-Acao` | se o módulo altera configuração (ajustes, recursos, atualizações, otimizar) | Desfaz a partir do snapshot | sim, via núcleo |

Regras:

- `Find-Alvos` recebe `-Raizes` (pastas) ou `-RaizRegistro` com valor padrão real. Os testes passam a sandbox. **Nenhum caminho do sistema fica fixo dentro de função que não aceite override.**
- Módulos **nunca** apagam arquivo, escrevem registro, mudam serviço ou tarefa agendada diretamente. Chamam `Remove-TmdItem` ou o motor de ajustes do núcleo, que validam, fazem snapshot, registram em log e respeitam `-Simular`.
- Nenhum módulo chama outro módulo. Se dois precisam da mesma coisa, ela vai para o núcleo.
  Módulos podem usar as funções **exportadas** do núcleo (ex.: `Format-TmdTamanho`); o `tamandua.ps1` importa o núcleo com `-Global` para isso.
- Leitura do sistema (CIM, registro, processos) fica numa função pequena do módulo (ex.: `Get-LeituraSistema`),
  e cada parte dela é lida isolada: se uma falhar, só aquela parte vira `Desconhecido`.
- `Invoke-Acao` **não confia** em caminhos vindos nos alvos (podem ter sido alterados no caminho): recalcula a partir do `Id`
  com as regras do próprio módulo. Ex.: o `limpar` usa só o `Id` da categoria para achar a pasta.
- Para testes, `Find-Alvos` e `Invoke-Acao` podem aceitar trocas de pasta (ex.: `-Pastas @{ 'temp-usuario' = '...' }`).
  O módulo lê as pastas padrão de variáveis de ambiente (`TEMP`, `LOCALAPPDATA`) quando possível, para os testes da CLI
  trocarem essas variáveis no processo filho e nunca tocarem nas pastas reais.
- Manifesto pode ter `RotuloAcao` (ex.: `'Limpar'`): vira o texto do botão principal e da pergunta de confirmação,
  `Resultado = 'Mudancas'` quando o resultado fala de mudanças (ajustes, programas) em vez de espaço liberado, e
  `AvisoConfirmacao` (texto que vai junto da pergunta de confirmação, na CLI e na interface).
- Alvo pode ter `Selo` (texto do selo, ex.: "instalado"); a cor continua vindo do `Estado`.
- Módulo que registra operação sem apagar nada (ex.: programas) usa `Write-TmdOperacao`; arquivo temporário próprio usa
  `New-TmdArquivoTemporario` / `Remove-TmdArquivoTemporario` (só `tamandua-*` direto no TEMP).
- **Módulos que navegam** (ex.: `analisar`): `Find-Alvos -Caminho <pasta>`; sem `-Caminho`, mostram um ponto de partida.
  Alvos com `Navegavel = $true` e `Caminho` abrem com duplo clique/Enter na interface (o subtítulo mostra a pasta,
  Atualizar/F5 continuam nela) e com `tamandua <módulo> <pasta>` na CLI. O núcleo só passa `-Caminho` se a função tiver esse parâmetro.
- Nenhum módulo usa `Write-Host` nem toca em WPF. Retorna objetos; quem desenha é a CLI (`Saida.ps1`) ou a interface.
- Progresso é reportado via `Write-Progress`-equivalente do núcleo (`Write-TmdProgresso`), que a CLI e a interface traduzem cada uma do seu jeito.
- Erro em um alvo não para o módulo: o alvo vira `Status = 'Erro'` com `Motivo`, e segue para o próximo.
- Cancelamento: funções longas checam `Test-TmdCancelado` entre itens.

### 5.4 Objetos padrão

**Alvo** (retornado por `Find-Alvos`):

```powershell
[pscustomobject]@{
    Id          = 'temp-usuario'          # estável, usado em presets, perfis, lista de proteção e testes
    Nome        = 'Temporários do usuário'
    Categoria   = 'Temporários'
    Caminho     = 'C:\Users\x\AppData\Local\Temp'   # quando for arquivo/pasta
    Tamanho     = 123456789               # bytes; -1 = desconhecido; $null = não se aplica
    Estado      = 'NaoAplicado'           # Aplicado | NaoAplicado | Parcial | Desconhecido | NaoSeAplica
    Risco       = 'Baixo'                 # Baixo | Medio | Alto
    Selecionado = $true                   # pré-seleção; Risco Alto nunca vem selecionado
    Destino     = 'Permanente'            # Permanente | Lixeira | NaoSeAplica
    RequerAdmin = $false
    Reversivel  = $false
    Detalhe     = '1.234 arquivos'
    Mudancas    = @()                     # lista legível do que será alterado (painel de detalhes)
}
```

Propriedades **obrigatórias em todo alvo** (verificadas pelo teste de contrato): `Id` (único no módulo), `Nome`,
`Categoria`, `Estado`, `Detalhe`. As demais são obrigatórias só para módulos que escrevem.
Módulos de leitura (`status`, `analisar`) usam também:

- `Nivel` — `Normal` | `Atencao` | `Critico`: cor na CLI e na interface.
- `Valor` — número de 0 a 100 quando faz sentido (uso de CPU, % de disco), para barras na interface.

**Resultado** (retornado por `Invoke-Acao` / `Undo-Acao`, um por alvo):

```powershell
[pscustomobject]@{
    Id       = 'temp-usuario'
    Status   = 'Feito'       # Feito | Simulado | Ignorado | Parcial | Erro
    Liberado = 120000000     # bytes liberados (limpeza); 0 quando não se aplica
    Motivo   = '12 arquivos em uso foram pulados'
}
```

---

## 6. Carregador de módulos

Para cada módulo do catálogo + pastas extras em `modulos/`, o carregador define um estado:

| Estado | Quando | CLI | Interface |
|---|---|---|---|
| `ok` | manifesto válido, import ok, `Test-Requisitos` ok | Disponível | Item normal na barra lateral |
| `faltando` | está no catálogo mas a pasta/arquivo não existe | `✗ limpar — faltando (pasta modulos\limpar não encontrada)` | Item cinza; ao clicar, página explicando o que falta |
| `quebrado` | manifesto inválido, import falhou, função obrigatória ausente, catálogo JSON inválido | `✗ limpar — quebrado (falta a função Find-Alvos)` | Item com aviso vermelho + motivo |
| `indisponivel` | `Test-Requisitos` retornou `Ok = $false` | `○ programas — indisponível (winget não encontrado)` | Item com aviso amarelo + motivo + ação sugerida |

Regras:

- Cada módulo é carregado dentro de `try/catch` próprio. **Uma exceção em um módulo nunca impede o carregamento dos outros.**
- `Test-Requisitos` roda com timeout curto; se travar ou lançar exceção, vira `indisponivel`.
- `tamandua modulos` lista todos os módulos com estado e motivo.
- Chamar um comando de módulo que não está `ok` imprime o estado e o motivo e sai com código `2`, sem stack trace.
- O núcleo é a única parte obrigatória. Se faltar, `tamandua.ps1` diz isso claramente e sai.
- Se `interface/` faltar ou falhar ao carregar, `tamandua.ps1` sem argumentos cai para o **menu de texto** e avisa o porquê.
- Módulo sem `pagina.xaml` aparece na interface com a **página genérica** (lista de alvos + detalhes + botões), montada a partir dos objetos `Alvo`. Assim todo módulo funciona na interface sem código de UI próprio.

---

## 7. Segurança (o núcleo garante, os módulos não reimplementam)

### 7.1 Validação de caminho (`Test-TmdCaminhoSeguro`)

Antes de qualquer remoção, o caminho precisa passar por **todas** as checagens:

1. Caminho absoluto, normalizado (`[IO.Path]::GetFullPath`), sem curingas.
2. **Não é reparse point** (junction, symlink, placeholder do OneDrive). Nunca seguir links — é o jeito clássico de um limpador apagar a pasta errada no Windows.
3. Está **dentro** de uma das raízes permitidas declaradas pelo alvo. Comparação com caminho completo + `\`, para `C:\Temp2` não passar como filho de `C:\Temp`.
4. **Não é** um caminho protegido nem pai de um. Dois tipos (`nucleo/Seguranca.ps1`):
   - **Pontos protegidos** — a pasta e seus pais são intocáveis, o conteúdo pode ser limpo: raiz de unidade, `C:\Users`,
     perfil, `AppData\Roaming`, `AppData\Local`, `ProgramData`, `Documentos`, `Área de Trabalho`, `Downloads`, `Temp`, menu Iniciar.
   - **Árvores protegidas** — nada dentro pode ser removido: `Windows` (exceto `Windows\Temp` e `SoftwareDistribution\Download`),
     `Arquivos de Programas` (os dois), `Imagens`, `Músicas`, `Vídeos`, `OneDrive` e a própria pasta do Tamanduá.
5. Não bate com nenhum padrão da lista de proteção: `config/protegidos.padrao.txt` (dados de navegador que não são cache,
   chaves, carteiras, `.git`) + `%APPDATA%\Tamandua\protegidos.txt` (`tamandua protegidos` abre). Se a lista do usuário
   existe mas não pode ser lida, nada é removido.

Falhou em qualquer item → `Ignorado` com motivo. Nunca lança exceção para o usuário.

### 7.2 Remoção (`Remove-TmdItem`)

- Único ponto do código que apaga arquivos. Teste de contrato verifica
  (`Remove-Item`, `[IO.File]::Delete`, `rd`, `del` fora de `nucleo/Remocao.ps1` → teste falha).
- Apaga com .NET, item por item. **Nunca** `Remove-Item -Recurse`: no 5.1 ele segue junctions e apaga o destino.
  Links encontrados dentro de uma pasta são pulados (nem seguidos, nem apagados) e contados no `Motivo`.
- `Destino = 'Lixeira'` usa `SHFileOperation` (shell32) com `FOF_ALLOWUNDO`, sem janela nem pergunta, e confere que o item saiu do lugar.
- Arquivo somente leitura: tira o atributo e apaga.
- Arquivo em uso / acesso negado → pula, conta, informa no `Motivo` (`Parcial` se algo foi apagado, `Ignorado` se nada).
- `-Simular` não toca no disco.
- Todo item removido (ou simulado) vai para o log de operações.

### 7.3 Motor de ajustes (`MotorAjustes.ps1`)

Único ponto que escreve **registro, serviços, tarefas agendadas, pacotes Appx e scripts de sistema**.
Teste de contrato verifica (`Set-ItemProperty`, `New-ItemProperty`, `Remove-ItemProperty`, `Set-Service`,
`Disable-ScheduledTask`, `Remove-AppxPackage`, `reg add`, `sc config` fora do motor → teste falha).

Para cada mudança, na ordem:

1. **Ler** o valor atual (ou "não existe").
2. **Gravar snapshot** em `%LOCALAPPDATA%\Tamandua\estado\` (id do ajuste, item, valor anterior, tipo, data). Snapshot falhou → mudança não acontece.
3. **`reg export`** da chave em `backup\` (rede de segurança extra, restaurável manualmente).
4. **Aplicar.**
5. **Verificar** relendo o valor. Não bateu → `Erro`, e restaura o snapshot daquela mudança.
6. **Registrar** no log.

Desfazer usa o snapshot. Sem snapshot (ex.: ajuste aplicado por outra ferramenta), usa o `PadraoWindows`
declarado no catálogo e avisa na tela que está restaurando o *padrão do Windows*, não o valor anterior.

Implementação (`nucleo/MotorAjustes.ps1`, `nucleo/Estado.ps1`):

- `Set-TmdAjuste -Ajuste <definição> [-Simular]`, `Undo-TmdAjuste -Id <id> [-Ajuste <definição>] [-Simular]`,
  `Get-TmdEstadoAjuste -Ajuste <definição>` → `Aplicado | NaoAplicado | Parcial | Desconhecido`.
- Mudança que já está como o ajuste quer é pulada e **não entra no snapshot** (não foi o Tamanduá que mudou).
- Snapshot em `%LOCALAPPDATA%\Tamandua\estado\ajustes\<id>.json`, gravado de forma atômica; corrompido = não desfaz.
- Registro por .NET (`RegistryKey`, visão de 64 bits, caminho literal), nunca por `Set-ItemProperty`.
  `.reg` de cada chave em `%LOCALAPPDATA%\Tamandua\backup\` antes de mexer.
- Serviços por `sc.exe config` (o `Set-Service` do 5.1 não sabe "automático atrasado"); tarefas por `Enable/Disable-ScheduledTask`.
- `-RaizRegistro 'HKCU:\Software\TamanduaTestes\...'` redireciona HKCU e HKLM para uma chave de teste. Só aceita caminhos
  dentro de `HKCU:\Software\TamanduaTestes\`, e o snapshot guarda onde a mudança foi feita: desfazer volta no mesmo lugar
  mesmo quando quem desfaz não sabe do redirecionamento. No módulo `ajustes`, `TAMANDUA_REGISTRO_TESTE` faz o mesmo para
  processos filhos (CLI) e para a janela.
- Histórico: cada `ajustar`/`desfazer` vai para o log; `Get-TmdHistorico` marca `Reversivel` no ajuste mais recente de cada Id
  que ainda tem snapshot. CLI: `tamandua desfazer <id> [-Simular] [-Sim]`. Interface: página **Histórico** (do núcleo,
  sempre no fim da barra lateral) com caixa só nos ajustes reversíveis e botão **Desfazer**.

### 7.4 Ponto de restauração

Antes do **primeiro lote** de mudanças de sistema numa sessão (ajustes, recursos, atualizações, otimizar),
oferece criar ponto de restauração (`Checkpoint-Computer`, precisa de admin e da Proteção do Sistema ligada).
O Windows limita a 1 ponto a cada 24h por padrão — se não der, avisa o motivo em vez de fingir que criou.

### 7.5 Confirmação e modos

| Flag | Efeito |
|---|---|
| (nenhuma) | Mostra a lista, pede confirmação |
| `-Simular` | Mostra o que faria, não faz nada |
| `-Sim` | Pula confirmação (para scripts). Sem `-Sim`, rodar sem console interativo **não altera nada** |
| `-Detalhado` | Log detalhado na tela |

Na interface: o botão de executar sempre abre um resumo ("Vai alterar 7 itens, 3 precisam de admin, 1 é de risco alto") antes de rodar.

### 7.6 Admin

- O programa roda sem admin. Alvos com `RequerAdmin = $true` aparecem marcados com um escudo.
- Ao executar, os alvos que precisam de admin vão num **único** processo elevado (um só prompt do UAC por lote),
  que roda o mesmo núcleo e devolve os `Resultado` por arquivo JSON temporário.
  Implementado (`nucleo/Elevacao.ps1`): CLI e interface chamam `Invoke-TmdAcaoModulo`; se o manifesto tem `RequerAdmin = $true`
  e o processo não é admin, ele grava o pedido num `tamandua-*.json` do TEMP e roda `tamandua.ps1 __elevado <pedido>` com
  `-Verb RunAs` (`Start-TmdProcessoElevado`, o único ponto que pede o UAC). O lado elevado só aceita pedido e resposta que
  sejam temporários do Tamanduá. UAC negado = tudo `Ignorado` com o motivo. `-Simular` nunca eleva.
- Programas do sistema (`sfc`, `DISM`, `netsh`, `net`...) rodam por `Invoke-TmdPrograma`, que devolve código e saída e registra no log.
- Serviços do Windows: parar só se necessário, e sempre religar no `finally`.

---

## 8. Ajustes declarativos (módulo `ajustes`)

O módulo `ajustes` quase não tem código: ele lê `ajustes.json` e entrega ao motor.

```json
{
  "id": "privacidade-historico-atividades",
  "nome": "Desativar histórico de atividades",
  "descricao": "Impede o Windows de registrar e enviar o histórico de atividades.",
  "categoria": "Privacidade",
  "risco": "Baixo",
  "requerAdmin": true,
  "link": "https://learn.microsoft.com/...",
  "mudancas": [
    { "tipo": "Registro", "caminho": "HKLM:\\SOFTWARE\\Policies\\Microsoft\\Windows\\System",
      "nome": "EnableActivityFeed", "valor": 0, "tipoValor": "DWord", "padraoWindows": null }
  ]
}
```

Tipos de mudança suportados pelo motor:

| `tipo` | Campos | Verificação de estado |
|---|---|---|
| `Registro` | `caminho`, `nome`, `valor`, `tipoValor`, `padraoWindows` (`null` = não existe) | lê o valor |
| `Servico` | `nome`, `inicializacao` (`Automatic`, `Manual`, `Disabled`, `AutomaticDelayedStart`), `padraoWindows` | lê `StartType` |
| `Tarefa` | `caminho`, `nome`, `habilitada`, `padraoWindows` | lê estado da tarefa |
| `Appx` | `pacote` | pacote instalado ou não. Remoção de Appx é **risco Alto** e não reversível pelo motor (reinstalação via Store) |
| `Script` | `aplicar`, `desfazer`, `verificar` | roda `verificar`; sem `verificar`, estado = `Desconhecido` |

Regras do catálogo (verificadas por teste automático em **todo** item):

- `id` único, minúsculo, com prefixo da categoria.
- Toda mudança `Registro`/`Servico`/`Tarefa` tem `padraoWindows`.
- Todo `Script` tem `desfazer`; sem `verificar` só é aceito com `risco` ≥ `Medio`.
- Caminho de registro começa com `HKCU:` ou `HKLM:`; `HKLM:` exige `requerAdmin: true`.
- Ajustes que mexem em segurança (Defender, UAC, SmartScreen, firewall, BitLocker) **não entram** no catálogo.

Categorias iniciais (seleção revisada do que o WinUtil oferece):

- **Privacidade** (baixo): telemetria, histórico de atividades, rastreamento de localização, ID de anúncios, recursos de consumidor (apps sugeridos), sugestões e Bing na busca do Iniciar.
- **Explorer e interface** (baixo): mostrar extensões, arquivos ocultos, menu de contexto clássico, barra de tarefas à esquerda, tema escuro, desativar descoberta automática de pastas, Início/Galeria no Explorer, "Finalizar tarefa" no botão direito.
- **Desempenho** (médio): efeitos visuais para desempenho, apps em segundo plano, Game Mode, aceleração do mouse, plano de energia "Desempenho máximo" (com aviso para notebooks), otimização de entrega.
- **Sistema** (médio/alto): hibernação, Armazenamento Reservado, Storage Sense, caminhos longos, BSoD/logon detalhados, IPv4 preferido, remover widgets, Copilot/recursos de IA.
- **Remoções** (alto, desmarcado, não reversível pelo motor): OneDrive, Edge, apps pré-instalados (Appx).

**Presets**: cada ajuste lista os presets de que faz parte (`"presets": ["Essencial", "Privacidade"]`), sem arquivo separado.
Iniciais: `Essencial` (só risco baixo), `Privacidade`, `Explorador`. Aplicar preset **só marca** os itens; o usuário ainda
revisa e confirma. O mecanismo é genérico: qualquer módulo cujos alvos tenham `Presets` ganha os botões "Marcar:" na interface
e `-Preset <nome>` na CLI; `-Itens a,b` marca por id.

Primeira versão do catálogo (`modulos/ajustes/ajustes.json`): 14 ajustes, todos em `HKCU`, sem admin. Cada ajuste tem teste
de ida e volta (aplica → `Aplicado` → desfaz → nenhum valor sobra) gerado automaticamente a partir do catálogo.

Ainda não suportado pelo motor (fica para quando houver necessidade): criar/apagar **chaves** inteiras (ex.: menu de contexto
clássico do Windows 11, que depende da existência de uma chave) e remoção de Appx.

**Perfis**: o usuário pode exportar/importar sua seleção (ajustes + programas) como JSON em `%APPDATA%\Tamandua\perfis\` —
útil para configurar uma máquina nova igual à antiga.

---

## 9. Módulos

| Módulo | O que faz no Windows | Escreve | Admin | Origem |
|---|---|---|---|---|
| `status` | CPU, memória, disco, rede, bateria, top processos, nota de saúde (CIM) | não | não | Mole |
| `analisar` | Maiores pastas/arquivos a partir de um caminho, navegável | não* | não | Mole |
| `limpar` | `%TEMP%`, cache de navegadores (só cache, nunca perfil), `CrashDumps`, WER, cache de miniaturas, caches de dev (npm, pip, NuGet), Lixeira, Limpeza de Disco (`cleanmgr /sagerun`) | sim | parcial | Mole + WinUtil |
| `purgar` | `node_modules`, `target`, `bin`/`obj`, `dist`, `build`, `__pycache__`, `.venv` | sim | não | Mole |
| `instaladores` | `.exe .msi .msix .iso .zip` em Downloads → Lixeira | sim | não | Mole |
| `desinstalar` | Lista programas (Uninstall HKLM/HKCU/WOW6432 + Appx), roda o desinstalador, oferece restos → Lixeira | sim | depende | Mole |
| `programas` | Catálogo por categoria (winget), instalar em lote, ver o que já está instalado, atualizar todos (`winget upgrade`) | sim | depende | WinUtil |
| `ajustes` | Seção 8 | sim | parcial | WinUtil (melhorado) |
| `recursos` | Liga/desliga recursos opcionais (WSL, Hyper-V, Sandbox, .NET 3.5, NFS) com estado atual | sim | sim | WinUtil |
| `atualizacoes` | Política do Windows Update: padrão / só segurança (adiar recursos) / pausar. **Desativar totalmente não é oferecido** | sim | sim | WinUtil (restrito) |
| `otimizar` | Flush DNS, reconstruir cache de ícones, retrim SSD (`defrag /O`), limpeza de componentes DISM | sim | sim | Mole + WinUtil |
| `reparos` | `sfc /scannow`, `DISM /RestoreHealth`, reset de rede (winsock/IP), reset do Windows Update, chkdsk agendado | sim | sim | WinUtil |
| `historico` (núcleo) | Log de operações, com desfazer por item | — | — | Mole |

\* `analisar` pode enviar para a Lixeira no futuro, sempre via núcleo.

### Proteções específicas

- **purgar:** só com marcador de projeto ao lado (`package.json`, `Cargo.toml`, `*.csproj`, `pyproject.toml`...). Pula se houver arquivos versionados no Git. Modificado nos últimos 7 dias → **desmarcado**. `bin`/`obj` só com `*.csproj`/`*.fsproj` irmão.
  Implementado: regras por nome de pasta em `modulos/purgar/purgar.psm1` (com o comando para recriar), `.venv`/`venv` exigem
  `pyvenv.cfg` dentro, artefato com outro repositório `.git` dentro (até 2 níveis) fica de fora, versionado vira um aviso
  ("N pastas deixadas de fora"). Sem git instalado: risco médio e desmarcado. Busca em Documentos, Área de Trabalho e
  `~\source|Projects|Projetos|dev|code|repos|git|GitHub|workspace|src` (ou na pasta de `tamandua purgar <pasta>`), até 6 níveis,
  sem entrar em links, `.git`, `AppData` nem pastas do Windows. `Invoke-Acao` reconfere tudo pelo caminho do `Id`.
- **Lista de proteção vale dentro das pastas:** ao apagar uma pasta, o que estiver dentro e bater com a lista (ex.: uma `chave.pem`
  num `target\deploy`) fica, e o resultado vira `Parcial` com "N protegido(s) pela lista de proteção".
- **limpar (navegadores):** navegador aberto → pula com motivo. Nunca toca em `Cookies`, `Login Data`, `History`, `Bookmarks`, `Local Storage`.
- **instaladores:** reconfirma tamanho + data imediatamente antes de remover; se mudou, pula. O caminho sai do `Id` e a
  extensão é conferida de novo (alvo forjado com `.pdf` ou `..\` é ignorado). Só vem marcado `.exe/.msi/.msix/.appx/.iso`
  baixado há 7 dias ou mais; `.zip/.7z/.rar/.img` são risco médio. `.exe` numa subpasta com outros arquivos (ex.: `.dll`)
  é tratado como **programa portátil já extraído**: risco médio, nunca marcado. Busca com mais de 20 mil arquivos não marca nada.
  Lê a pasta Downloads real do registro (pode ter sido movida). Tudo vai para a Lixeira.
  Testes: `TAMANDUA_DOWNLOADS_TESTE` e `TAMANDUA_LIXEIRA_TESTE` (ambas só aceitas dentro do TEMP) trocam Downloads e Lixeira.
- **desinstalar:** restos com `Risco = Medio`, desmarcados se o nome for ambíguo.
  Implementado: lista das chaves Uninstall (HKLM 64 e 32 bits, HKCU), sem componentes de sistema nem atualizações; runtimes,
  redistribuíveis, drivers e afins são risco alto. Nada vem marcado. O comando sai do registro na hora de executar (não do alvo);
  `MsiExec /I{GUID}` vira `/x {GUID}`. Roda o desinstalador do próprio programa (a janela dele abre) e espera até 90 s o
  programa sumir da lista; se não sumiu, é erro. Restos: só pastas com o **nome exato** do programa (sem versão/arquitetura)
  ou `Editor\Programa` em `%APPDATA%`, `%LOCALAPPDATA%` e `%ProgramData%`, **só de programas que o Tamanduá desinstalou**
  (guardados em `estado\restos.json`); aparecem desmarcados e vão para a Lixeira. Restos em Arquivos de Programas não são
  oferecidos (árvore protegida). Desinstalador e lista do registro passam por `Start-Desinstalador` e `Get-RegistroPrograma` (Mock nos testes).
- **programas:** só IDs exatos do winget (`--exact --id`), com `--accept-source-agreements` apenas depois de o usuário aceitar na primeira execução.
  Implementado: catálogo `modulos/programas/programas.json` (37 programas, IDs conferidos no winget). Instalados pelo
  `winget export --source winget` (JSON), atualizações pelo `winget upgrade` lendo as colunas pela **posição das palavras do
  cabeçalho** (um Id longo encosta na versão com um espaço só). Nada vem marcado; o selo diz "instalado",
  "atualizar para X" ou "não instalado". "Atualizar tudo" roda `winget upgrade --all`. Os termos são aceitos (`--accept-*`)
  só na confirmação, que avisa disso pelo `AvisoConfirmacao` do manifesto. Todo acesso ao winget passa por `Invoke-Winget`
  (Mock nos testes); códigos "nenhuma atualização" e "já instalado" contam como sucesso.
- **otimizar / reparos:** cada tarefa é um alvo próprio; tarefa longa (SFC, DISM) mostra progresso e pode ser cancelada antes de começar, nunca no meio.
  Implementado (reparos): `chkdsk C: /scan` (só verifica; problema que precisa de reinício vira Parcial com a instrução),
  `sfc /scannow`, `DISM /Online /Cleanup-Image /RestoreHealth`, `netsh winsock reset` + `int ip reset` (pede reinício) e
  "destravar o Windows Update" (para `wuauserv` e `bits`, apaga `SoftwareDistribution\Download` pelo núcleo e religa os
  serviços num `finally`). Nada vem marcado. Ainda sem barra de progresso: a interface mostra "Executando…".

---

## 10. Interface

### 10.1 Layout

Base do WinUtil (abas, busca, seleção em lote), reorganizada:

```
┌──────────────────────────────────────────────────────────────────────┐
│ 🐜 Tamanduá                         [ Buscar em tudo...    ]  ◐  ⚙   │
├──────────────┬───────────────────────────────────────┬───────────────┤
│ SISTEMA      │ Ajustes › Privacidade      Preset [▼] │ DETALHES      │
│  Status      │ ───────────────────────────────────── │               │
│ LIMPEZA      │ ☑ Desativar telemetria      ● Aplicado│ Desativar     │
│  Analisar    │ ☐ Histórico de atividades   ○ Não     │ telemetria    │
│  Limpar      │ ☐ ID de anúncios            ◐ Parcial │ Risco: Baixo  │
│  Purgar      │ ☐ Bing no Iniciar        🛡 ○ Não      │ 🛡 Requer admin│
│  Instaladores│                                       │               │
│ PROGRAMAS    │                                       │ Vai alterar:  │
│  Programas   │                                       │ HKLM\...\Data │
│  Desinstalar │                                       │ Collection    │
│ AJUSTES      │                                       │ AllowTelemetry│
│  Ajustes   ◀ │                                       │ 3 → 0         │
│  Recursos    │                                       │               │
│ MANUTENÇÃO   │                                       │ Desfazer: sim │
│  Otimizar    │                                       │ (valor atual  │
│  Reparos     │                                       │ será salvo)   │
│ ──────────── │                                       │               │
│  Histórico   │                                       │               │
│  ✗ otimizar  │                                       │               │
│    faltando  │                                       │               │
├──────────────┴───────────────────────────────────────┴───────────────┤
│ 3 selecionados · 1 requer admin   [Simular]  [Desfazer]  [Aplicar ▶] │
│ ▓▓▓▓▓▓▓▓░░░░░░░ Aplicando 2/3...                        [Cancelar]   │
└──────────────────────────────────────────────────────────────────────┘
```

### 10.2 Melhorias em relação ao WinUtil

- **Barra lateral agrupada** no lugar de abas soltas; módulos faltando/quebrados/indisponíveis aparecem no fim com o motivo.
- **Estado real** em cada linha (aplicado / não aplicado / parcial / desconhecido), atualizado após cada ação.
- **Painel de detalhes**: o que vai mudar, valor atual → novo, risco, se precisa de admin, se é reversível, link de referência.
- **Busca global** (Ctrl+F) que procura em todos os módulos.
- **Barra de ação fixa** com contagem, Simular, Desfazer e Aplicar; resumo de confirmação antes de executar.
- **Progresso e cancelamento** sempre visíveis; janela nunca congela.
- **Histórico** com desfazer por item.
- **Tema** segue o Windows (claro/escuro), com opção manual; acentos e textos em português.
- **Acessibilidade**: navegação total por teclado, `AutomationProperties.Name` em todo controle, contraste mínimo AA.
- **Escala**: layout funciona a partir de 1024×700 e respeita DPI.

### 10.3 Regras de código da interface

- A interface **só** chama funções públicas do núcleo (`Get-TmdModulo`, `Find-TmdAlvos`, `Invoke-TmdAcao`...). Nunca chama módulo direto, nunca contém lógica de sistema.
- Estado da janela num objeto pequeno e explícito (`$Estado.Selecao`, `$Estado.Pagina`), não um `$sync` global com tudo.
- Toda chamada ao núcleo passa por `Segundo-Plano.ps1` (runspace); atualizações de tela voltam via `Dispatcher.Invoke`.
- Lógica de tela testável fora da janela: funções que transformam `Alvo` em linhas da lista, montam o resumo de confirmação etc. são puras e têm teste.
- Tarefas em segundo plano recebem o **texto** do script e importam o núcleo do zero no próprio runspace;
  devolvem só dados. Um `DispatcherTimer` (100 ms) entrega o resultado na thread da janela — nada de WPF é tocado de outra thread.
- Todo evento passa por `Invoke-TmdProtegido`: erro vira texto na barra de status, a janela nunca cai.
- `Start-TmdInterface -AoCarregar {...} -FecharAposSeg N` existe para testes e capturas: os testes abrem a janela de verdade
  e ela fecha sozinha mesmo se algo travar.
- Estilo implícito de `TextBlock` não atravessa `DataTemplate`: a cor do texto em listas vem do `Foreground` do item.
- Em handlers de evento, leia `$args` **antes** de entrar no `Invoke-TmdProtegido { ... }`: dentro do bloco, `$args` é o do bloco (vazio).
- Callbacks de tarefa **não** usam `GetNewClosure()` (perderiam o acesso às funções e ao `$script:` do módulo);
  o que precisam vai em `Start-TmdTarefa -Contexto`, entregue como 4º argumento.
- Módulo que escreve: caixa de seleção por linha (a marca fica no próprio alvo e sobrevive à busca), **Simular** roda direto,
  o botão principal pede confirmação na barra de status ("…Isso não pode ser desfeito. Confirmar?") e só o segundo clique executa.
  Depois de executar, a página é relida e o resultado fica na barra de status.
- Revisão visual: `.\ferramentas\capturar-interface.ps1 -Saida tela.png -Tema escuro -Modulo limpar`.

### 10.4 Paleta "Tamanduá"

Extraída das cores dominantes de uma foto de tamanduá-bandeira
([Myresluger2.jpg, Wikimedia Commons](https://commons.wikimedia.org/wiki/File:Myresluger2.jpg)):
pelagem preta, pelo acinzentado, faixa creme, terra do chão e capim seco.
Os tons foram ajustados a partir dos da foto para atingir contraste AA.

| Origem | Cor base |
|---|---|
| Pelagem (faixa preta) | `#232020` |
| Pelo acinzentado | `#5A4640` |
| Focinho | `#857565` |
| Faixa creme | `#FADFC0` |
| Terra | `#9C5A3C` |
| Capim seco | `#BF9D65` |
| Musgo | `#56632F` |
| Ferrugem | `#963A2E` |

Tokens (definidos só em `interface/tema-claro.xaml` e `tema-escuro.xaml`; nenhuma cor fixa fora deles):

| Token | Claro | Escuro | Uso |
|---|---|---|---|
| `Fundo` | `#F3EADD` | `#1A1716` | Painel de detalhes, áreas de fundo |
| `Superficie` | `#FBF6EF` | `#232020` | Janela, lista, barras |
| `SuperficieLateral` | `#EADDCB` | `#2B2624` | Barra lateral |
| `Borda` | `#D9C6AE` | `#443E39` | Divisórias |
| `Texto` | `#232020` | `#F3E9DC` | Texto principal |
| `TextoSecundario` | `#5A4640` | `#C4B09C` | Texto de apoio |
| `TextoSutil` | `#857565` | `#8F8072` | Dicas, rótulos de grupo |
| `Acento` / `AcentoFundo` | `#9C5A3C` / `#F0DACB` | `#D99A72` / `#4A3125` | Botão principal, item ativo, progresso |
| `NoAcento` | `#FBF6EF` | `#232020` | Texto sobre `Acento` |
| `Sucesso` / `SucessoFundo` | `#56632F` / `#E3E4C9` | `#A9B57A` / `#33361F` | Estado "aplicado" |
| `Aviso` / `AvisoFundo` | `#85601C` / `#F2E2BF` | `#D9B46F` / `#41331A` | "Parcial", risco médio, indisponível |
| `Perigo` / `PerigoFundo` | `#963A2E` / `#F2D8D1` | `#E38B7B` / `#4A231E` | Risco alto, faltando, erros |

Logo: círculo com a faixa diagonal preta e creme do tamanduá.
Teste em `testes/interface/` verifica que toda cor usada no XAML vem de um token de `tema.xaml`.

---

## 11. Ordem do MVP

Cada etapa só começa com a anterior com testes verdes.

1. **Núcleo + carregador + `tamandua modulos`** — catálogo com os 12 módulos, todos `faltando`. Prova a modularidade.
2. **`status`** — só leitura, valida o contrato sem risco.
3. **Casca da interface** — janela, barra lateral com estados reais dos módulos, página genérica, `status` aparecendo. Fallback para menu de texto se a interface faltar.
4. **Segurança + Remoção** — bateria pesada de testes (seção 12.3) antes de qualquer módulo que apague.
5. **`limpar`** — primeiro módulo que escreve. Começa só com `%TEMP%` do usuário e `CrashDumps`; cada categoria nova = alvo novo + testes novos.
6. **Motor de ajustes + Estado (snapshots) + Histórico** — com testes na sandbox de registro.
7. **`ajustes`** — começando com ~10 itens de risco baixo em `HKCU` (sem admin), depois os de `HKLM`.
8. **`analisar`**, 9. **`programas`**, 10. **`purgar`**, 11. **`instaladores`**, 12. **`desinstalar`**, 13. **`recursos`**, 14. **`otimizar`**, 15. **`reparos`**, 16. **`atualizacoes`**.

Definição de pronto do MVP: etapas 1–7 entregues, interface e CLI funcionando, `-Simular` em tudo, log de operações, histórico com desfazer.

---

## 12. Testes

### 12.1 Regra de ouro

**Nenhum teste toca o sistema real.**

- Arquivos: `$TestDrive` (sandbox do Pester), passado via `-Raizes`.
- Configuração e log: `testes/Ajudantes.ps1` aponta `TAMANDUA_CONFIG` e `TAMANDUA_DADOS` para a sandbox
  (vale para os processos filhos também). Os testes nunca criam nada em `%APPDATA%` ou `%LOCALAPPDATA%`.
- Lixeira: simulada por `Mock` no processo, ou por `TAMANDUA_LIXEIRA_TESTE` (pasta dentro do TEMP que recebe os itens) quando
  o teste roda a CLI ou a janela. O teste com a Lixeira real é opcional (`$env:TAMANDUA_TESTE_LIXEIRA = '1'`), porque deixa um arquivinho nela.
- Registro: o motor aceita `-RaizRegistro`; nos testes, todo caminho `HKLM:\...`/`HKCU:\...` do catálogo é reescrito para
  `HKCU:\Software\TamanduaTestes\<guid>\HKLM\...`, e a chave (inclusive a mãe `TamanduaTestes`, se vazia) é apagada no `AfterAll`.
  Testes que rodam o processo filho usam um caminho que **já é** uma chave de teste, sem redirecionamento.
- Mocks com estado (serviço/tarefa falsos) usam variáveis globais `$global:TmdTeste*`, removidas no `AfterAll`.
  No Pester 6 um `Mock` com `-ParameterFilter` não cai no comando real: declare também um mock padrão.
- Serviços, tarefas, Appx, winget, CIM, `Checkpoint-Computer`: isolados atrás de funções pequenas e substituídos por `Mock`.

### 12.2 Camadas

| Camada | Pasta | O que garante |
|---|---|---|
| Núcleo | `testes/nucleo/` | Validação de caminho, remoção, motor de ajustes, snapshots, simulação, log, elevação (lógica) |
| Contrato | `testes/contrato/` | Roda para **cada pasta em `modulos/`**: manifesto válido, funções obrigatórias, `Find-Alvos` não escreve (sandbox não muda), objetos com as propriedades certas, nenhuma escrita de sistema fora do núcleo. E para **cada item** de `ajustes.json` e `programas.json`: regras da seção 8 |
| Resiliência | `testes/resiliencia/` | Copia o projeto para a sandbox e: remove a pasta de um módulo → abre e mostra `faltando`; corrompe manifesto ou JSON → `quebrado`; exceção no import → os outros carregam; `Test-Requisitos` lança → `indisponivel`; remove `interface/` → cai no menu de texto |
| Interface | `testes/interface/` | XAML carrega sem erro (`XamlReader`, sem mostrar janela), todo controle nomeado existe, funções puras de tela, página genérica monta a partir de alvos falsos |
| Módulo | `testes/modulos/<nome>/` | Comportamento específico, sempre com sandbox |

### 12.3 Casos de segurança obrigatórios

**Remoção** (o `limpar` não começa sem todos passando):

- junction dentro da raiz apontando para fora → **não segue**, destino intacto
- `..\` que escapa da raiz permitida → recusado
- `C:\Temp2` com raiz permitida `C:\Temp` → recusado
- cada caminho protegido da seção 7.1 → recusado
- caminho na lista de proteção do usuário → recusado
- arquivo travado (aberto por outro handle) → `Parcial`, não exceção
- `-Simular` → sandbox idêntica antes e depois (hash de todos os arquivos)
- sem `-Sim` e sem console interativo → nada removido

**Ajustes** (o módulo `ajustes` não começa sem todos passando):

- aplicar → valor novo gravado, snapshot com o valor **anterior real**
- desfazer → valor anterior restaurado exatamente (inclusive "não existia" → chave/valor removido)
- aplicar duas vezes → snapshot não é sobrescrito pelo valor já alterado
- falha ao gravar snapshot → nada é alterado
- verificação pós-escrita falha → mudança revertida, `Erro`
- ajuste com 3 mudanças onde a 2ª falha → 1ª revertida, 3ª não aplicada
- `-Simular` → registro da sandbox idêntico antes e depois

### 12.4 Como rodar

```powershell
.\testes\executar.ps1            # lint + todos os testes
.\testes\executar.ps1 -Rapido    # só testes, sem lint
.\testes\executar.ps1 -Modulo limpar
```

`executar.ps1` sai com código ≠ 0 se qualquer coisa falhar.

### 12.5 Fluxo de cada mudança

1. Escreve/ajusta o teste que descreve a mudança (vê ele falhar).
2. Implementa.
3. `.\testes\executar.ps1` — tudo verde.
4. Smoke test manual no sistema real **em `-Simular`** e confere a lista.
5. Para ajustes: aplica num item, confere o estado, **desfaz**, confere que voltou.
6. Só então usa de verdade, e confere o Histórico.
7. Commit pequeno, mensagem dizendo o que mudou e qual teste cobre.

Mudança que não tem como ser testada automaticamente (ex.: algo que depende de admin real) precisa
de um roteiro de teste manual escrito no commit e de um `Mock` que cubra pelo menos a lógica de decisão.
Ajustes novos de `HKLM` são testados manualmente numa VM ou no Windows Sandbox antes de entrar no catálogo.

---

## 13. Estilo de código

- Funções públicas do núcleo: `Verbo-TmdSubstantivo` (verbos aprovados do PowerShell, substantivo em português): `Get-TmdModulo`, `Remove-TmdItem`, `Set-TmdAjuste`.
- Funções de módulo: nomes fixos do contrato; auxiliares internas não exportadas.
- `Set-StrictMode -Version Latest` e `$ErrorActionPreference = 'Stop'` em todo `.psm1`, com tratamento explícito onde erro é esperado.
- Funções curtas, uma responsabilidade. Arquivo passou de ~300 linhas → dividir.
- Comentários só onde o *porquê* não é óbvio (ex.: por que pular reparse points).
- Mensagens ao usuário em português; nomes de propriedade sem acento (`Descricao`, não `Descrição`).
- Nada de caminho fixo tipo `C:\Users\fulano`: sempre `$env:LOCALAPPDATA`, `$env:TEMP`, `[Environment]::GetFolderPath(...)`.

---

## 14. CLI

```
tamandua                       # abre a interface (ou menu de texto, se a interface faltar)
tamandua menu                  # força o menu de texto
tamandua modulos               # estado de cada módulo
tamandua status
tamandua analisar [caminho]
tamandua limpar [-Simular] [-Sim]
tamandua purgar [caminho] [-Simular] [-Sim]
tamandua instaladores [-Simular] [-Sim]
tamandua desinstalar [-Lista]
tamandua programas [-Lista] [-Instalar id,id] [-Atualizar]
tamandua ajustes [-Lista] [-Preset Essencial] [-Aplicar id,id] [-Desfazer id,id] [-Simular]
tamandua recursos [-Lista] [-Ligar id] [-Desligar id]
tamandua atualizacoes [-Politica Padrao|Seguranca|Pausar]
tamandua otimizar [-Simular]
tamandua reparos [-Lista] [-Executar id]
tamandua perfil -Exportar arquivo.json | -Importar arquivo.json
tamandua historico [-Desfazer idOperacao]
tamandua protegidos            # abre a lista de proteção do usuário
```

Códigos de saída: `0` ok · `1` erro · `2` módulo não disponível · `3` cancelado pelo usuário.

---

## 15. Fora do escopo do MVP

MicroWin/criação de ISO, atualização automática, instalador, agendamento, TUI navegável no `analisar`,
integração com menu de contexto do Explorer, Chocolatey. Tudo isso pode virar módulo depois.
