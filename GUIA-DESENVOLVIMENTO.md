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

Pegamos: limpeza por categorias, instaladores esquecidos, desinstalar com restos,
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

### Como o programa abre (e por que pode não abrir na máquina de outra pessoa)

- O Windows vem com a política de scripts "Restricted" e bloqueia `.ps1` baixado da internet (Mark of the Web, mesmo
  com "RemoteSigned"). Por isso o jeito de abrir é o **`Tamandua.cmd`**: `powershell.exe -ExecutionPolicy Bypass`, que
  vale só para aquela execução (não muda configuração nenhuma). Sem argumentos ele abre pelo `conhost.exe` (console
  clássico) minimizado e termina: com o Windows Terminal como console padrão, a janela dele não dá para esconder.
  Com argumentos (linha de comando) roda no console à vista e, se der erro, espera uma tecla.
- `tamandua.ps1`: no PowerShell 7 (pwsh) ou sem STA, abre de novo no Windows PowerShell 5.1 com `-STA`.
  `-EsconderConsole` (o `.cmd` e a cópia de admin passam) esconde o console só depois que a janela aparece
  (`Hide-TmdConsole` no `ContentRendered`); quem abre pelo próprio terminal não perde o terminal.
- Erro ao abrir: `erro-ao-abrir.txt` em `%LOCALAPPDATA%\Tamandua\logs` (Windows, PowerShell, idioma, pasta, admin,
  política de scripts, erro completo), caixa de mensagem quando era para abrir a janela, e o console volta à vista.
  Interface que não abre: o motivo vai para o mesmo arquivo e o menu de texto aparece com o console restaurado.
- A cópia de admin (`Start-TmdReaberturaElevada`) também vai pelo `conhost.exe`, minimizada.
- A janela tem identidade própria na barra de tarefas (`SetCurrentProcessExplicitAppUserModelID`) e o ícone é o logo do
  topo desenhado em 64 px: não agrupa com o PowerShell nem usa o ícone dele.
- Para testar como numa máquina nova: copie a pasta, marque os arquivos como baixados
  (`Set-Content -Stream Zone.Identifier -Value "[ZoneTransfer]`nZoneId=3"`) e rode
  `powershell -ExecutionPolicy Restricted -File tamandua.ps1 versao` (falha, como na máquina do amigo) e o `Tamandua.cmd`.

### Regras de compatibilidade com PowerShell 5.1

- **Arquivos `.ps1`/`.psm1`/`.psd1` em UTF-8 *com BOM*.** Sem BOM, o 5.1 lê acentos errado (`Tamanduá` vira `TamanduÃ¡`).
  `.json` e `.xaml` em UTF-8 (lidos com `-Encoding UTF8` explícito).
- Proibido: `&&`, `||`, `??`, `?.`, operador ternário, `ForEach-Object -Parallel`, `ConvertFrom-Json -AsHashtable`.
- `Set-Content`/`Add-Content` sempre com `-Encoding UTF8`.
- `ConvertFrom-Json` de uma lista JSON devolve a lista inteira como **um** objeto no 5.1: desmonte com `foreach ($x in (... | ConvertFrom-Json)) { $x }`.
- `$x = if (...) { @(...) } else { ... }` desmonta o array (um item vira escalar, nenhum vira `$null`): use `$x = @(if ...)`.
- `@($param).Count` com um `[string[]]` nulo lança em StrictMode no 5.1: `$lista = @(); if ($param) { $lista = @($param) }`.
- Loops pesados de arquivo vão para C# (`Add-Type`), como `Tamandua.Medidor` em `nucleo/Remocao.ps1`: mede ~95 mil arquivos em ~3 s.
  Os tipos C# do núcleo são compilados **só quando alguém precisa** (`Initialize-TmdTipos`, ~0,3 s, uma vez por processo,
  com trava para dois runspaces não compilarem juntos): importar o núcleo não compila nada.
- Nada de `Win32_Processor` para uso de CPU (leva ~1 s): `Start-TmdMedidaCpu` / `Get-TmdUsoCpu -Desde` mede pelo
  `GetSystemTimes` no intervalo em que o resto é lido. Em CIM, peça só os campos usados (`-Property`).
- Medir antes e depois de mexer em desempenho: `.\ferramentas\medir-tempos.ps1 -Vezes 3` (abre a janela de verdade,
  passa por todos os módulos e devolve a mediana em ms; `-Esperar` simula quem espera a leitura antecipada).
- Leituras lentas do Windows (cada cmdlet que carrega um módulo CIM leva 0,5 a 3 s) ficam em `$script:LeiturasLentas`
  (`nucleo/MotorAjustes.ps1`): os "verificar" do catálogo chamam `Get-TmdLeitura <chave>` e a página de ajustes faz
  `Update-TmdLeiturasLentas` no começo, que lê todas em paralelo (runspaces) e guarda até os erros. Ajustes: ~10 s → ~2 s.
  O DNS saiu do `Get-NetAdapter` (CIM, ~2 s) para registro + `NetworkInterface` do .NET (~0,1 s), com o mesmo resultado.
  Em `$hashtable.Chave` com chave que não existe, o StrictMode lança: use `.ContainsKey()`.
- A tela não remonta linhas à toa: `ConvertTo-LinhaAlvo -Cache` reusa a linha de cada Id enquanto os alvos da página
  são os mesmos (a busca refaz a lista a cada tecla), e as pastas são montadas numa passada só. Redesenhar Programas:
  ~1,3 s → ~0,6 s. No modelo da grade, toda linha tem todas as propriedades ligadas por Binding (vazias se não usar):
  Binding que não acha a propriedade custa caro em cada quadro.
- Abrir: a barra lateral sai do catálogo e dos manifestos (`Get-TmdModulosProvisorios`, ~0,15 s na própria janela) e a
  primeira página abre sem esperar os módulos carregarem de verdade (~0,8 s). A lista de verdade troca a provisória sem
  reabrir a página (`Update-TmdListaDeVerdade`); módulo que estava com problema é reaberto com a mensagem certa. O aviso
  "carregou" (`AoCarregar`) e a leitura antecipada esperam a lista de verdade.
- Grade grande: o WPF não tem painel em grade que desenhe só o que está à vista. `Update-TmdBusca` põe os 48 primeiros
  quadros e o resto com prioridade `Background`, depois do primeiro desenho (a página aparece 2,5 a 3,5x antes);
  `-Inteira` para quem precisa achar um item logo em seguida (fechar pasta). O `AoCarregar` vai com prioridade
  `ContextIdle`, então quem é avisado já acha a lista completa.
- Testes: nada de `<...>` no nome de `It`/`Describe` fora de `-ForEach` — o Pester tenta expandir como variável.
- Testes: `-Skip:(...)` é avaliado na descoberta; o que ele usa vem de `BeforeDiscovery`, não de `BeforeAll`.
- `$lista.Propriedade` numa lista vazia lança em StrictMode: use `$lista | ForEach-Object { $_.Propriedade }`.
- Variáveis não diferenciam maiúsculas: um `$catalogo` local sobrescreve o parâmetro `$Catalogo`.
- `-and` e `-or` têm a mesma precedência (avaliados da esquerda para a direita): use parênteses.
- Não use nomes de variáveis automáticas (`$home`, `$input`, `$args`, `$error`, `$host`, `$matches`) como variável própria.
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
│  ├─ capturar-interface.ps1    # salva PNG da janela (revisão visual)
│  └─ medir-tempos.ps1          # tempo de abrir o programa e cada módulo (mediana de N rodadas)
├─ modulos/
│  ├─ status/                   # cada módulo é uma pasta
│  │  ├─ modulo.psd1            # manifesto
│  │  ├─ status.psm1            # implementação
│  │  └─ pagina.xaml            # OPCIONAL: página na interface; sem ela, usa página genérica
│  ├─ limpar/
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
        @{ Nome = 'limpar';       Grupo = 'Limpeza';    Descricao = 'Temporários, caches de navegadores, apps e jogos, logs e Lixeira' }
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
    Escreve        = $true      # $false = módulo só leitura (status)
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
- Manifesto com `Visualizacao = 'Grade'` (desinstalar, programas) mostra a página em quadros com ícone; o botão no
  cabeçalho da página troca para lista e volta (a escolha vale por módulo enquanto a janela está aberta). Alvo com
  `Icone` (caminho no formato do `DisplayIcon`: `arquivo` ou `arquivo,índice`, com aspas e variáveis de ambiente)
  ganha o ícone; sem ícone, o quadro mostra a inicial do nome. `Icone` também pode ser uma lista de candidatos
  (`Get-TmdCandidatosIcone`: DisplayIcon, o .ico do MSI em `Windows\Installer\{código}`, o .exe da pasta de instalação,
  o atalho do menu Iniciar, o desinstalador); vale o primeiro que tiver ícone. Ícones dos programas para instalar vêm
  com o projeto; o `baixar-icones-programas.ps1` tira o quadrado branco que encosta na borda e põe uma placa branca
  arredondada atrás de logo escuro e vazado (que sumiria no tema escuro); `-SoLimparFundo` refaz isso sem baixar. O PNG é extraído em segundo plano por
  `Get-TmdAlvosParaTela` (núcleo, que as duas leituras da janela usam) e vira imagem na janela em `Set-TmdImagensLinha`.
  A imagem tem que ir para a linha como objeto .NET puro (`::new()` e `.PSObject.BaseObject`): embrulhada num
  PSObject, o Binding do WPF não mostra nada e não dá erro.
- Alvo pode ter `Selo` (texto do selo, ex.: "instalado"); a cor continua vindo do `Estado`.
- Módulo que registra operação sem apagar nada (ex.: programas) usa `Write-TmdOperacao`; arquivo temporário próprio usa
  `New-TmdArquivoTemporario` / `Remove-TmdArquivoTemporario` (só `tamandua-*` direto no TEMP).
  Alvos com `Navegavel = $true` e `Caminho` abrem com duplo clique/Enter na interface (o subtítulo mostra a pasta,
  Atualizar/F5 continuam nela) e com `tamandua <módulo> <pasta>` na CLI. O núcleo só passa `-Caminho` se a função tiver esse parâmetro.
- Nenhum módulo usa `Write-Host` nem toca em WPF. Retorna objetos; quem desenha é a CLI (`Saida.ps1`) ou a interface.
- Progresso: na execução de verdade o núcleo chama `Invoke-Acao` **um alvo por vez** e, antes de cada um, `Write-TmdProgresso`
  (Status = nome do alvo, CurrentOperation = "2 de 5"). Módulos não precisam fazer nada. A CLI mostra a barra do console; a
  interface lê `Streams.Progress` da tarefa (`Start-TmdTarefa -AoProgresso`) e mostra a fração na barra de baixo, com o item e o
  tempo decorrido no status (com um item só, a barra fica indeterminada). `-Simular` continua de uma vez, sem progresso.
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
Módulos de leitura (`status`) usam também:

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
   - **Árvores protegidas** — nada dentro pode ser removido: `Windows` (exceto `Temp`, `SoftwareDistribution\Download`, `Logs`,
     `Minidump` e o cache da Otimização de Entrega), `Arquivos de Programas` (os dois; exceto `Steam\logs`, `Steam\dumps` e
     `Steam\appcache\httpcache`), `Imagens`, `Músicas`, `Vídeos`, `OneDrive` e a própria pasta do Tamanduá.
   - **Nomes protegidos** — em qualquer lugar, inclusive dentro de uma pasta sendo apagada: `pagefile.sys`, `hiberfil.sys`,
     `swapfile.sys`, `ntuser.dat*`, `usrclass.dat*`, `bootmgr`, `BCD` e afins (ideia do swept).
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

**Classificação** (ajustes, menu-contexto, atualizacoes): `classificacao` = `Recomendado` (bom para quase todo
mundo), `Opcional` (gosto), `Atencao` (pode dar contratempo) ou `Arriscado` (segurança ou algo que o Windows usa por
baixo; tudo de "Avançado"). Atenção e Arriscado têm `contratempo` (o que pode acontecer, em linguagem de gente) e
`seAcontecer` (como resolver). Os textos dos ajustes ficam em `ferramentas/classificar-ajustes.ps1`, que grava no
`ajustes.json` sem mexer no resto do arquivo; no menu de contexto saem de `Get-ClassificacaoItem`. Na tela: selo
colorido na linha (com a explicação ao passar o mouse), "Pode dar problema" e "Se acontecer" num cartão amarelo ou
vermelho no painel de detalhes (que rola, com cartões Sobre / problema / O que acontece, montados por `Get-DetalheAlvo`;
os comandos ficam numa caixa que dá para selecionar e copiar), e a
confirmação lista os arriscados que vão ser aplicados. Na CLI: `[Atenção]` na listagem e aviso antes de confirmar.
Presets Mínimo, Essencial, Notebook e Explorador nunca têm Arriscado (teste).

Na tela (ajustes e menu-contexto): item com estado `Aplicado` vem com `Desfaz = $true` e o selo
"aplicado · marcar desfaz"; marcado, o `Invoke-Acao` chama `Undo-TmdAjuste -Ajuste` (snapshot ou padrão do Windows) em
vez de aplicar. A primeira linha das mudanças (`Get-TmdTextoDesfaz`) diz para onde volta, e a confirmação avisa quantos
serão desfeitos. **Preset nunca marca item com `Desfaz`** (nem na interface, nem no `-Preset` da CLI): só marcando à
mão ou com `-Itens`. O Histórico só desfaz o que tem snapshot; cada linha sem caixa diz o motivo no painel de detalhes
(simulação, "já estava aplicado", remoção de arquivos) e aponta a página Ajustes.

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

Implementado como o primeiro item da página Ajustes ("Criar ponto de restauração antes", presets Mínimo, Essencial, Avançado,
Notebook e Desempenho): `Invoke-Acao` sempre o roda antes dos ajustes marcados. `New-TmdPontoRestauracao` (núcleo) liga a
Proteção do Sistema no disco do Windows se estiver desligada e zera `SystemRestorePointCreationFrequency` **só durante** a
criação (o WinUtil deixa zerado), para não esbarrar no limite de 1 ponto a cada 24 h. Falhou = `Erro` com o motivo.

### 7.5 Confirmação e modos

| Flag | Efeito |
|---|---|
| (nenhuma) | Mostra a lista, pede confirmação |
| `-Simular` | Mostra o que faria, não faz nada |
| `-Sim` | Pula confirmação (para scripts). Sem `-Sim`, rodar sem console interativo **não altera nada** |
| `-Detalhado` | Log detalhado na tela |

Na interface: o botão de executar sempre abre um resumo ("Vai alterar 7 itens, 3 precisam de admin, 1 é de risco alto") antes de rodar.

### 7.6 Admin

- Ao abrir a janela (`tamandua` sem comando), pede admin uma vez, como o WinUtil (`Request-TmdAdminAoAbrir`): aceitou, abre
  outra cópia como administrador e esta termina; recusou, abre assim mesmo e a barra de status avisa que o que tem escudo pede
  permissão na hora. Comandos da CLI não pedem nada ao abrir. Testes: `TAMANDUA_NAO_ELEVAR=1` (o `Ajudantes.ps1` liga).
- Sem admin, alvos com `RequerAdmin = $true` aparecem marcados com um escudo.
- Ao executar, os alvos que precisam de admin vão num **único** processo elevado (um só prompt do UAC por lote),
  que roda o mesmo núcleo e devolve os `Resultado` por arquivo JSON temporário.
  Implementado (`nucleo/Elevacao.ps1`): CLI e interface chamam `Invoke-TmdAcaoModulo`; se o manifesto tem `RequerAdmin = $true`
  e o processo não é admin, ele grava o pedido num `tamandua-*.json` do TEMP e roda `tamandua.ps1 __elevado <pedido>` com
  `-Verb RunAs` (`Start-TmdProcessoElevado`, o único ponto que pede o UAC). O lado elevado só aceita pedido e resposta que
  sejam temporários do Tamanduá. UAC negado = tudo `Ignorado` com o motivo. `-Simular` nunca eleva.
  Só os alvos com `RequerAdmin = $true` vão para o processo elevado; os outros rodam como o usuário (ex.: reiniciar o
  Explorador elevado deixaria a área de trabalho rodando como admin). Os resultados voltam na ordem dos alvos.
  Na interface, esses alvos mostram um escudo ao lado do nome.
  O processo elevado também grava o progresso num terceiro temporário (`Progresso` no pedido, validado igual à resposta);
  `Start-TmdProcessoElevado` devolve o processo sem esperar, e `Invoke-TmdAcaoElevada` lê esse arquivo a cada 300 ms
  e repassa por `Write-TmdProgresso` até o processo sair. Mocks de teste devem devolver `Start-Process ... -PassThru` (sem `-Wait`).
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
| `Servico` | `nome`, `inicializacao` (`Automatic`, `Manual`, `Disabled`, `AutomaticDelayedStart`), `padraoWindows` | lê `Services\<nome>\Start` no registro (CIM levava ~100 ms por serviço) |
| `Tarefa` | `caminho`, `nome`, `habilitada`, `padraoWindows` | lê estado da tarefa |
| `Script` | `aplicar`, `desfazer`, `verificar` | roda `verificar`; sem `verificar`, estado = `Desconhecido` |

Scripts rodam dentro do núcleo e podem usar `Read-TmdRegistro`/`Write-TmdRegistro`. Comando externo que falhar precisa lançar
(`if ($LASTEXITCODE) { throw ... }`), senão o motor acha que deu certo. `verificar` roda toda vez que a página abre: precisa ser
rápido e não exigir admin (sem admin, lançar = `Desconhecido`). Remoção de Appx, OneDrive, Edge e afins é `Script` com
`desfazer` que reinstala pelo winget/Store, e chave inteira (menu clássico) é `Script` que cria/apaga a chave.
Funções do núcleo feitas para os scripts: `Remove-TmdAppx`/`Install-TmdAppxDaLoja`/`Test-TmdAppxInstalado` (uma leitura do
`Get-AppxPackage` guardada por 20 s serve aos 34 apps), `Set-TmdDns`/`Get-TmdDnsAtual`, `Set-TmdPastaBloqueada`/
`Test-TmdPastaBloqueada` (nega escrita a "Todos"), `Clear-TmdConteudoPasta` (apaga pelo `Remove-TmdItem`, pulando `tamandua-*`).

**Ações únicas** (`"acao": true`, `"executar": "<script>"`, sem `mudancas`): o que se faz uma vez e não tem estado nem desfazer
— ponto de restauração, Limpeza de Disco, apagar temporários, abrir o O&O ShutUp10++. `Invoke-TmdAcaoAjuste` (núcleo) roda o
script, soma o `Liberado` dos `Remove-TmdItem` que ele devolver (pulado = `Parcial`) e registra `executar` no histórico.
`"primeiro": true` (só o ponto de restauração) vai antes de tudo; e, sem admin, o lote elevado roda antes do resto.

Regras do catálogo (verificadas por teste automático em **todo** item):

- `id` único, minúsculo, com prefixo (`priv-`, `sis-`, `expl-`, `barra-`, `aparencia-`, `energia-`, `nav-`, `avanc-`...).
- Toda mudança `Registro`/`Servico`/`Tarefa` tem `padraoWindows`.
- Todo `Script` tem `desfazer` e compila; sem `verificar` só é aceito com `risco` ≥ `Medio`.
- Caminho de registro começa com `HKCU:`, `HKLM:` ou `HKU:`; `HKLM:`, `HKU:`, serviço e tarefa exigem `requerAdmin: true`.
- O que mexe em segurança (Defender, UAC, SmartScreen, firewall, BitLocker) só existe na categoria
  **Avançado (por sua conta e risco)**, com risco Alto e fora de qualquer preset. Nada de `priv-`/`sis-` toca nisso.

Catálogo atual: **tudo** da aba Tweaks do WinUtil — os 68 de `config/tweaks.json` e os 34 apps de `config/appx.json` —
em 118 entradas, cada uma com `"winutil": ["<chave original>"]` e "(WinUtil: nome original)" na descrição.
`testes/modulos/ajustes/winutil-referencia.json` é a cópia das chaves e presets do WinUtil (com a data da conferência); um
teste falha se faltar qualquer chave ou se um preset do WinUtil não estiver inteiro no nosso. Para atualizar: baixar de novo
`tweaks.json`, `appx.json` e `preset.json`, regenerar a referência e ver o que o teste aponta.
Mais 72 ajustes do **Atlas OS** (`src/playbook/Configuration/tweaks`, GPL-3.0; usamos só os valores), com `"atlas": ["<arquivo>.yml"]`
e "(Atlas: título original)" na descrição: os que são só registro e que um administrador consegue escrever. Ficaram de fora os que
o WinUtil já tinha, os internos do Atlas (scripts, tema, foto de perfil, atalhos), os que enfraquecem a segurança (mitigações,
Core Isolation, UAC sem área de trabalho segura, páginas do Segurança do Windows), os que exigem TrustedInstaller (o Atlas roda
como TI: `Diagnostics\Performance`, `Component Based Servicing`, `ActivatableClassId`, índice de busca) e os de menu de contexto
(viraram o módulo Menu de contexto).
Um tweak do WinUtil pode virar mais de um ajuste: DNS (combobox) virou um por provedor + "o mais rápido"; Multiplane Overlay,
dois (compatibilidade e total); Windows AI, dois (IA + Recall); Ultimate Performance (ligar/desligar), um com desfazer.
Diferenças de propósito:
- Telemetria não mexe no Defender: o envio de amostras virou o ajuste avançado `avanc-defender-sem-amostras` (mesma chave).
- Otimização de Entrega existe aqui e no módulo Atualizações (mesmo valor e mesmo alvo: aplicar num aparece aplicado no outro).
- Serviços em manual deixa o Compartilhamento de Internet em manual, não desligado (o Hotspot móvel continua).
- Remover Edge não usa `--delete-profile` (favoritos e senhas ficam). A lista da Adobe para o hosts é filtrada linha a linha.
- Copilot/Recall por política reversível + remoção do app (o WinUtil mexe no `EndOfLife` do Appx, sem volta).
- Remover app também tira da imagem (contas novas não ganham) e desfazer reinstala pela Store.
- O&O ShutUp10++ só abre se a assinatura digital for da O&O; DNS desfaz para o automático (DHCP).
- Escolhas exclusivas (IPv6, MPO, DNS) ficam fora dos presets e a descrição avisa para escolher uma.

**Presets**: cada ajuste lista os presets de que faz parte, sem arquivo separado. Clicar num preset **troca** a seleção inteira,
então cada preset é completo sozinho. Os do WinUtil (`config/preset.json`) estão inteiros nos nossos (teste), mas os nossos vão
além — os do WinUtil marcam pouco:
- `Mínimo` (5): o Minimal do WinUtil + ponto de restauração. Só risco baixo.
- `Essencial` (34): para qualquer usuário. O Standard do WinUtil + toda a privacidade básica, extensões visíveis, tela azul com
  detalhes, caminhos longos, Configurações sem propaganda, Shift×5 sem Teclas de Aderência e remoção só dos apps-propaganda
  (Notícias, Bing, Clipchamp, Paciência, Microsoft 365, Hub de Comentários...). Risco baixo, fora o que o Standard exige.
- `Avançado` (60): Essencial + o Advanced do WinUtil (Widgets, OneDrive, IA, Recall, menu clássico, busca da Loja, Iniciar
  antigo) + Edge/Brave limpos, apps em segundo plano, armazenamento reservado, DNS mais rápido, Iniciar sem Recomendados,
  Explorador em Este Computador, ocultos visíveis e mais apps (Copilot, Clima, Teams, Outlook novo, Assistência Rápida...).
- `Notebook` (38): Essencial sem a localização (fuso automático em viagem) + bateria na barra, sem rede no modo de espera,
  apps em segundo plano, sem Widgets. Nada que gaste bateria nem desligue a hibernação.
- `Desempenho` (45): Essencial + efeitos visuais, plano Desempenho Máximo, Modo de Jogo, sem hibernação, mouse sem aceleração,
  MPO em compatibilidade, DNS mais rápido. Mantém os apps do Xbox.
- `Privacidade` (26): toda a privacidade + IA/Recall + Edge/Brave + DNS do AdGuard + apps do Bing/Copilot.
- `Explorador` (13): Explorador e barra de tarefas com jeito de Windows 10. `Remover apps` (18): o AppxDefault do WinUtil.
Regras com teste: Mínimo ⊂ Essencial ⊂ Avançado e Desempenho; Notebook ⊇ Essencial − localização; Essencial ≥ 30 e Avançado ≥ 50;
nenhum preset do dia a dia tira Calculadora, Relógio, Fotos, Bloco de Notas, Paint, Captura ou Câmera; no máximo um item de cada
escolha exclusiva (DNS, MPO) por preset e nenhum de IPv6; segurança (Defender, BitLocker) em nenhum. Aplicar preset **só marca**
os itens; o usuário ainda revisa e confirma. A ordem dos botões é a
de aparição (o ponto de restauração vem primeiro e define Mínimo, Essencial, Avançado, Notebook, Desempenho). O mecanismo é
genérico: qualquer módulo cujos alvos tenham `Presets` ganha os botões "Marcar:" e `-Preset <nome>` na CLI; `-Itens a,b` marca por id.

Testes: cada ajuste que é só registro tem ida e volta (aplica → `Aplicado` → desfaz → nenhum valor sobra) na chave de teste,
inclusive HKLM e HKU (redirecionados). Serviços vão por Mock. Na área de testes (`-RaizRegistro`/`TAMANDUA_REGISTRO_TESTE`)
o módulo só mostra ajustes de registro sem admin, e o motor recusa serviço e tarefa — nada de teste mexe no sistema.

**Perfis**: o usuário pode exportar/importar sua seleção (ajustes + programas) como JSON em `%APPDATA%\Tamandua\perfis\` —
útil para configurar uma máquina nova igual à antiga.

---

## 9. Módulos

| Módulo | O que faz no Windows | Escreve | Admin | Origem |
|---|---|---|---|---|
| `status` | CPU, memória, disco, rede, bateria, top processos, nota de saúde (CIM) | não | não | Mole |
| `limpar` | Temporários (usuário e Windows), despejos e relatórios de erro, logs antigos do Windows, downloads do Windows Update, Otimização de Entrega, shaders, cache de navegadores (Chrome, Edge, Brave, Firefox; só cache), Discord, Spotify, Steam, Epic, Battle.net, Ubisoft, Lixeira | sim | parcial | Mole + swept |
| `desinstalar` | Lista programas (Uninstall HKLM/HKCU/WOW6432 + Appx), roda o desinstalador, oferece restos → Lixeira | sim | depende | Mole |
| `programas` | Catálogo por categoria (winget), instalar em lote, ver o que já está instalado, atualizar todos (`winget upgrade`) | sim | depende | WinUtil |
| `ajustes` | Seção 8 | sim | parcial | WinUtil (melhorado) |
| `menu-contexto` | Menu clássico no Windows 11; tira itens do Windows (Compartilhar, Biblioteca, Paint 3D, "Novo", "Enviar para"...) e de programas (achados na hora) | sim | parcial | Atlas + próprio |
| `recursos` | Liga/desliga recursos opcionais (WSL, Hyper-V, Sandbox, .NET 3.5, NFS) com estado atual | sim | sim | WinUtil |
| `atualizacoes` | Política do Windows Update: padrão / só segurança (adiar recursos) / pausar. **Desativar totalmente não é oferecido** | sim | sim | WinUtil (restrito) |
| `otimizar` | Flush DNS, reconstruir cache de ícones, retrim SSD (`defrag /O`), limpeza de componentes DISM | sim | sim | Mole + WinUtil |
| `reparos` | `sfc /scannow`, `DISM /RestoreHealth`, reset de rede (winsock/IP), reset do Windows Update, chkdsk agendado | sim | sim | WinUtil |
| `historico` (núcleo) | Log de operações, com desfazer por item | — | — | Mole |

`analisar` e `purgar` existiram e foram retirados (lentos e pouco usados; para ver o que ocupa o disco, o WizTree faz melhor).
A navegação por pastas que só eles usavam (`Find-Alvos -Caminho`, duplo clique para abrir) também saiu: argumento solto depois
do nome do módulo na CLI é erro.

### Proteções específicas

- **menu-contexto:** tudo reversível pelo motor. Extensões (do Windows e de programas) são bloqueadas pelo CLSID em `HKLM\...\Shell Extensions\Blocked` (64 e 32 bits); comandos sem extensão ganham `ProgrammaticAccessOnly` na chave onde estão de verdade (HKCU ou HKLM\SOFTWARE\Classes); itens do "Novo" saem com `Remove-TmdChaveComCopia` (`reg export` em `estado\chaves\<id>.reg` antes, `Restore-` importa de volta); "Enviar para" só oculta os atalhos. Programa de terceiros = DLL/comando fora da pasta do Windows (ou em `DriverStore`); nome bare (`cmd.exe`) é do Windows. Itens que não existem na máquina não aparecem. No fim, `Restart-TmdExplorador` fecha o Explorador e o Windows o reabre como o usuário (nunca `explorer.exe` a partir do processo admin). Presets: Só o menu clássico, Recomendado, Limpo ao máximo. Testes: um "HKCR" falso dentro da chave de teste (`-RaizRegistro`); menu clássico, "Novo" e "Enviar para" não rodam lá.

- **Lista de proteção vale dentro das pastas:** ao apagar uma pasta, o que estiver dentro e bater com a lista (ex.: uma `chave.pem`
  num `target\deploy`) fica, e o resultado vira `Parcial` com "N protegido(s) pela lista de proteção".
- **limpar:** categorias são dados em `modulos/limpar/limpar.psm1` (`$script:Categorias`): pastas, idade mínima, `Filtro` de
  nomes (logs), `Processos` que precisam estar fechados, `RequerAdmin`, `SoSeExistir` (programa não instalado não aparece).
  Navegadores: só as pastas de cache de cada perfil (`Cache`, `Code Cache`, `GPUCache`, `Media Cache`; Firefox `cache2`,
  `startupCache`, `thumbnails`) — nunca `Cookies`, `Login Data`, `History`, `Bookmarks`, `Local Storage`. Programa aberto →
  item desmarcado e travado ("feche o Chrome"), e `Invoke-Acao` reconfere na hora. Spotify: só `Data` (streaming), nunca
  `Storage` (músicas offline). Steam: `logs`, `dumps`, `appcache\httpcache`; jogos nunca. Prefetch, miniaturas e cache do
  Office (swept tem) ficaram de fora: limpar o Prefetch deixa o Windows mais lento, miniaturas estão sempre presas pelo
  Explorador (o `otimizar` cuida dos ícones) e o cache do Office pode ter edições ainda não enviadas ao OneDrive.
  Categorias do sistema pedem admin num único UAC; sem admin, o Windows esconde algumas pastas e o tamanho só aparece ao limpar.
  Lixeira: `Get-TmdLixeira`/`Clear-TmdLixeira` no núcleo (SHQueryRecycleBin/SHEmptyRecycleBin), nunca vem marcada.
  Testes: `TAMANDUA_LIMPAR_RAIZ` (só dentro da pasta temporária real) troca Windows, ProgramData, AppData e Steam por
  subpastas dela e tira a exigência de admin — nenhum teste do limpar toca no sistema nem abre o UAC.
- **instaladores:** retirado em 2026-10 (achar instaladores esquecidos em Downloads não ajudava; o Limpar e o Desinstalar cobrem o que importa).
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
  Implementado: catálogo `modulos/programas/programas.json` (187 programas) gerado por `ferramentas/gerar-programas.ps1`
  a partir do WinUtil (`config/applications.json`: IDs do winget e sites) e do **FMHY** (`github.com/fmhy/edit`,
  `docs/*.md`, lidos por `ferramentas/Fmhy.ps1`). Regras do usuário:
  - **Só programas para baixar** (todo item é um pacote do winget/Microsoft Store; site não entra) e **só grátis** (a
    versão gratuita tem que bastar; `$Pagos` fica fora).
  - **Só o que está no FMHY.** No FMHY, a linha `* ⭐ **[Nome](link)**, [Outro](link) - Descrição` tem as entradas
    antes do " - "; links depois de " / " são do mesmo programa (GitHub, Discord) e não contam; a ⭐ vale só para o
    primeiro nome em negrito. Links `rentry…/FMHYB64` (versões crackeadas) e o `unsafe.md` são ignorados/proibidos.
    A estrela só conta se o link for do mesmo site do programa (o "Plex" ⭐ é o site de filmes; `$SemEstrela`).
  - **Exceção:** `$Populares` (Discord, Steam, Telegram, WhatsApp, Chrome, Epic, .NET, Visual C++) ficam, na categoria
    normal de cada um e sem estrela.
  - Programas com ⭐ no FMHY que não estão no WinUtil entram por `$DoFmhy` (escolhidos à mão: janela, usuário comum,
    nada de pirataria, linha de comando ou mod de jogo).
  - Desenvolvimento só com o básico. Dentro da categoria, os com estrela vêm primeiro.
  - **Categorias como pastas** (página com 4+ categorias, ou seja, Programas): na grade sem busca, cada categoria vira
    um quadro grande com 4 ícones (o "View: Category" do Iniciar do Windows 11, `ConvertTo-LinhasPorCategoria`);
    clicar abre, "Voltar" ou Esc fecham. Dentro, o `grupo` de cada programa (`$Grupos`) vira subtítulo ("Players de
    vídeo"...). Categoria de um item só (o "Atualizar tudo") aparece direto, do tamanho das pastas (`Grande`). É só
    visual: a marca fica no alvo, a busca e a lista mostram tudo solto. Páginas com poucas categorias continuam com as
    pastas de alternativas (`ConvertTo-LinhasComPastas`). Os quadros esticam para preencher a linha
    (`LarguraQuadro`/`LarguraPasta`, mínimo 150/196) e o subtítulo tem a largura das colunas (`LarguraLinhaGrade`);
    os três são recalculados no SizeChanged da lista. Comando curto: `docs/index.html` (GitHub Pages) é HTML e script
    ao mesmo tempo, e roda o `instalar.ps1`.
  - Sem preset na página Programas; os populares ficam na categoria normal deles (e nas pastas), sem estrela.
  - **Sem winget** (Windows LTSC/IoT não traz o "Instalador de Aplicativo"): a página abre do mesmo jeito (tudo "não
    verificado") e, ao instalar, `Install-TmdWinget` (`nucleo/Winget.ps1`) instala o winget antes: última versão do
    `github.com/microsoft/winget-cli` (~210 MB) + dependências da arquitetura do PC (~90 MB), só se a assinatura for
    válida e da Microsoft, por `Add-AppxPackage` para o usuário. Falhou: cada item diz por quê e nada mais é chamado.
    O winget é chamado pelo caminho achado (`Get-TmdCaminhoWinget`), porque o alias em `WindowsApps` pode não estar
    no PATH logo depois de instalar.
  - `winget export` (instalados) e `winget upgrade` (atualizações) rodam juntos (`Invoke-WingetVarios`, um runspace
    cada, mesmo jeito de chamar do `Invoke-Winget`; se o paralelo falhar, roda um de cada vez): ~1,7 s → ~1,1 s, com
    o mesmo resultado. Nos testes, o Mock do `Invoke-WingetVarios` chama o `Invoke-Winget` falso um de cada vez.
  - Nos detalhes, o comando do winget aparece sempre, até com o programa instalado ("Instalado com: winget install ...").
  O que justificou cada programa vai para `testes/modulos/programas/fmhy-referencia.json`, que os testes conferem.
  Programa só da Microsoft Store tem `"fonte": "msstore"` e o ID da loja em `wingetId` (instala com `--source msstore`).
  **Ícones vêm com o projeto** (`modulos/programas/icones/<id>.png`, 64x64; origem de cada um em `fontes.json`): quem vai
  instalar ainda não tem o programa no disco. `ferramentas/baixar-icones-programas.ps1` baixa (ícone do pacote no
  Chocolatey, ícone declarado pelo site, favicon do Google; `$Manuais` para os que o automático erra) e redesenha cada
  imagem num PNG novo; o programa nunca baixa nada. Sem ícone no projeto, usa o do programa instalado, e sem esse, a
  inicial. Instalados pelo `winget export` (JSON, fontes winget e msstore), atualizações pelo `winget upgrade` lendo as colunas pela **posição das palavras do
  cabeçalho** (um Id longo encosta na versão com um espaço só). Nada vem marcado; o selo diz "instalado",
  "atualizar para X" ou "não instalado". "Atualizar tudo" roda `winget upgrade --all`. Os termos são aceitos (`--accept-*`)
  só na confirmação, que avisa disso pelo `AvisoConfirmacao` do manifesto. Todo acesso ao winget passa por `Invoke-Winget`
  (Mock nos testes); códigos "nenhuma atualização" e "já instalado" contam como sucesso.
- **otimizar / reparos:** cada tarefa é um alvo próprio; tarefa longa (SFC, DISM) mostra progresso e pode ser cancelada antes de começar, nunca no meio.
  Implementado (reparos): `chkdsk C: /scan` (só verifica; problema que precisa de reinício vira Parcial com a instrução),
  `sfc /scannow`, `DISM /Online /Cleanup-Image /RestoreHealth`, `netsh winsock reset` + `int ip reset` (pede reinício) e
  "destravar o Windows Update" (para `wuauserv` e `bits`, apaga `SoftwareDistribution\Download` pelo núcleo e religa os
  serviços num `finally`). Nada vem marcado. Ainda sem barra de progresso: a interface mostra "Executando…".
  Implementado (otimizar): limpar cache de DNS e reconstruir o cache de ícones (fecha o Explorador, apaga
  `IconCache.db`/`iconcache_*.db` pelo núcleo, reabre o Explorador num `finally`) rodam como o usuário; `defrag C: /O`
  e `DISM /StartComponentCleanup` (sem `/ResetBase`) pedem admin.
- **recursos:** estado lido sem admin por `Win32_OptionalFeature` (CIM); marcar um item **inverte** o estado (o que fazer
  é decidido pelo estado lido na hora, não pelo alvo); mudança por `dism /Enable-Feature ... /All` ou `/Disable-Feature`
  com `/NoRestart`, via `Invoke-TmdPrograma` no processo elevado. 3010 = feito, pede reinício. Recurso que não existe na
  edição aparece com o selo "não existe nesta edição", sem caixa. SMB 1.0 é risco alto, com a explicação do porquê.
- **fonte:** troca a Segoe UI por qualquer família instalada (veio do `Set-SystemFont.ps1` da pasta Fonte; o FontKit.cs
  está em `nucleo\`, compilado por `Initialize-TmdFontKit` só quando a página precisa). Famílias: nomes do registro de
  fontes (máquina e usuário), sem o estilo do fim ("Rubik-BoldItalic" -> Rubik); `.ttc`, símbolos, a Segoe e família sem
  estilo normal ficam de fora. Ao aplicar, o peso de cada arquivo vem de dentro dele (OS/2) e cada uma das 13 vagas da
  Segoe UI (12 pesos + Segoe UI Variable) fica com o mais parecido (largura normal, itálico certo, peso mais perto).
  As cópias (`<original>_tmd<data>.ttf`, sufixo novo a cada troca porque fonte carregada não se sobrescreve) levam a
  tabela `name`, o peso/estilo e a altura de linha da Segoe (a conta do Set-SystemFont); o núcleo copia para
  `Windows\Fonts` (`Install-TmdArquivoFonte`, só nomes de cópia, nunca sobrescreve) e o registro muda por um ajuste
  comum, `fonte-sistema` (snapshot, `.reg` e desfazer pelo Histórico). "Segoe UI original" é o ajuste `fonte-original`.
  Tamanho: muda o `unitsPerEm`; automático = metade do caminho entre 100% e a mesma altura de "x"/"H" da Segoe UI
  (a OpenDyslexic dá 97%, que é o que tinha sido escolhido a olho). "Apagar cópias" só apaga cópias que o registro não
  usa (`Remove-TmdCopiaFonte`; carregada pelo Windows = `MoveFileEx` para apagar no boot) e pastas de trabalho velhas.
  Testes: registro (`TAMANDUA_REGISTRO_TESTE`) e pasta de fontes (`TAMANDUA_FONTES_TESTE`) falsos, com a Arial de modelo.
  Na janela é grade em pastas (como Programas): Sem serifa, Com serifa, Monoespaçadas, Manuscritas e decorativas, Outros
  alfabetos (pelo Panose e `post.isFixedPitch` lidos por `Tamandua.LeitorFonte`, que só lê o cabeçalho; sem Panose, pelo
  nome em palavras inteiras), depois Tamanho do texto e Segoe UI. Cada quadro mostra "Aa" na própria fonte
  (`AmostraFonte` = `file:///arquivo#Família`, para o WPF pegar o arquivo certo). Tamanho: Auto (padrão, nada marcado),
  90 a 110%, ou Personalizado (70 a 130%, régua no painel; na CLI, `tam-97.5`).
- **Grade em todas as páginas** (padrão; o manifesto pode pedir `Visualizacao = 'Lista'`, e o botão do alto troca). Página com 40+ itens e 4+ categorias vira pastas (Programas, Ajustes, Fonte); as outras ficam em seções com os quadros à vista. Sem imagem, o quadro mostra o ícone da categoria (`Get-GlifoCategoria`, por palavras do nome; o alvo pode mandar `Glifo`), e a pasta, o ícone grande. Páginas que só mostram (Status) trazem o detalhe e a barra no quadro; o Limpar mostra quanto libera; ajustes mostram a classificação. "não aplicado" não aparece no quadro. `NomeItens` no manifesto: "programa|programas", "ajuste|ajustes" (padrão "item|itens").
- **Conforto da janela:** clicar em qualquer parte do quadro (ou da linha) marca e desmarca; Espaço faz o mesmo pelo
  teclado. Toda página tem `Dica` (passos) no manifesto, com um × que fecha de vez naquela página. Preferências em
  `<dados>\config\interface.json` (tema escolhido no botão, grade/lista por página, tamanho da janela, dicas fechadas),
  só com `Start-TmdInterface -LembrarPreferencias` (o `tamandua.ps1` liga; testes nunca). Voltar a uma página já lida
  reaproveita as linhas montadas (`LinhasPorPagina`; Ajustes ~0,45 s -> ~0,2 s). O Histórico não mostra simulações.
- **Recursos genéricos da janela que a página Fonte usa** (servem para qualquer módulo):
  - Manifesto `Dica`: faixa de passos no alto da página. `Grupos` (`Nome`, `Rotulo`, `Vazio`): a barra de baixo diz o
    escolhido em cada grupo ("Fonte: Arial · Tamanho: automático"). `NomeItens` (`"opção|opções"`): o texto das pastas.
  - Alvo com `Exclusivo` (nome do grupo): um marcado por grupo; clicar no quadro já marca (`Set-TmdSelecao -Redesenhar`,
    que copia as marcas dos alvos para as linhas e dá `Items.Refresh`). A pasta mostra "✓ <escolhido>".
  - Alvo com `PedeValor` (`Titulo`, `Minimo`, `Maximo`, `Passo`, `Unidade`, `Padrao`): o painel de detalhes mostra régua e
    campo; o valor vai no alvo como `ValorEscolhido` (chega ao módulo também no processo de admin, pelo JSON do pedido).
  - Alvo com `Amostra`/`AmostraFonte`: texto grande no lugar do ícone e cartão "Prévia" no painel (quando é "Aa").
- **atualizacoes:** políticas do Windows Update como ajustes do motor (`modulos/atualizacoes/atualizacoes.json`, chaves em
  `HKLM:\SOFTWARE\Policies`): adiar versões grandes por 365 dias, esperar 4 dias pelas mensais, não reiniciar sozinho com
  alguém conectado, não instalar drivers, não compartilhar atualizações (`DODownloadMode = 0`). Presets "Equilibrado" e
  "Mais controle". Reversíveis pelo Histórico. Um teste garante que **nada no catálogo desliga o Windows Update**
  (`NoAutoUpdate`, `AUOptions`, serviços, servidor). No Windows Home, avisa que as políticas são ignoradas.
  Ao escolher o valor de um ajuste, confira se ele não **afrouxa** uma configuração mais restrita que o usuário já tenha
  (ex.: `DODownloadMode` 1 seria menos restrito que 0).
- Desfazer pelo Histórico ou `tamandua desfazer` usa `Undo-TmdAjusteComAdmin`: ajustes que mexeram em HKLM, serviço ou
  tarefa voltam num processo elevado (um UAC para o lote). Simular nunca exige admin, nem para aplicar nem para desfazer.

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
│  Limpar      │ ☐ Histórico de atividades   ○ Não     │ telemetria    │
│  Instaladores│ ☐ ID de anúncios            ◐ Parcial │ Risco: Baixo  │
│              │ ☐ Bing no Iniciar        🛡 ○ Não      │ 🛡 Requer admin│
│              │                                       │               │
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
- Tarefas em segundo plano recebem o **texto** do script e devolvem só dados. Rodam num conjunto de runspaces reaproveitados
  (`Initialize-TmdConjunto`: 2 a 4, abertos em segundo plano enquanto a janela aparece, já com o núcleo importado); o núcleo só
  é importado de novo se o caminho for outro. Um `DispatcherTimer` (100 ms) entrega o resultado na thread da janela — nada de
  WPF é tocado de outra thread.
- Desempenho da janela (medido com `ferramentas/medir-tempos.ps1`):
  - a primeira página do catálogo é lida **junto** com a lista de módulos (`ScriptPrimeiraPagina`), não depois;
  - depois que ela aparece, as outras páginas são lidas em segundo plano, uma por vez (`Start-TmdAntecipacao`); clicar numa
    página que está sendo lida espera essa mesma leitura;
  - páginas lidas ficam guardadas por 10 min (`$Estado.Cache`); Atualizar/F5 e o fim de uma ação sempre leem de novo, e
    qualquer ação (não simulada) apaga o cache inteiro. Status e Histórico nunca são guardados;
  - abrir uma página não roda o `Test-Requisitos` de novo (`Get-TmdModulo -SemRequisitos`: a lista já conferiu), e o
    carregador reaproveita o módulo já importado enquanto nenhum arquivo da pasta dele mudar.
- Todo evento passa por `Invoke-TmdProtegido`: erro vira texto na barra de status, a janela nunca cai.
- `Start-TmdInterface -AoCarregar {...} -FecharAposSeg N` existe para testes e capturas: os testes abrem a janela de verdade
  e ela fecha sozinha mesmo se algo travar. O relógio de `-FecharAposSeg` é desligado quando a janela fecha (antes, ele
  disparava depois e fechava a janela do teste seguinte).
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
8. **`analisar`** (retirado depois), 9. **`programas`**, 10. **`purgar`** (retirado depois), 11. **`instaladores`** (retirado depois), 12. **`desinstalar`**, 13. **`recursos`**, 14. **`otimizar`**, 15. **`reparos`**, 16. **`atualizacoes`**.

Definição de pronto do MVP: etapas 1–7 entregues, interface e CLI funcionando, `-Simular` em tudo, log de operações, histórico com desfazer.

**Situação:** MVP entregue; os 10 módulos do catálogo existem e estão disponíveis, com barra de progresso nas tarefas longas.
Próximos passos naturais: mais ajustes (incluindo criar/apagar chaves inteiras no motor), atualização do próprio Tamanduá,
limpeza agendada (o swept tem).

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
tamandua limpar [-Simular] [-Sim] [-Itens chrome,lixeira]
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

MicroWin/criação de ISO, atualização automática, instalador, agendamento, análise de disco (use o WizTree),
integração com menu de contexto do Explorer, Chocolatey. Tudo isso pode virar módulo depois.
