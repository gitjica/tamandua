# Funções puras: transformam dados do núcleo no que a tela mostra. Não tocam em WPF, então são testáveis sem janela.

# Glifos da fonte Segoe Fluent Icons / Segoe MDL2 Assets.
$script:IconesModulo = @{
    status       = [string][char]0xE9D9
    limpar       = [string][char]0xE74D
    desinstalar  = [string][char]0xE738
    programas    = [string][char]0xE7B8
    ajustes      = [string][char]0xE9E9
    'menu-contexto' = [string][char]0xE8FD
    fonte        = [string][char]0xE8D2
    recursos     = [string][char]0xE8F1
    atualizacoes = [string][char]0xE895
    otimizar     = [string][char]0xEC4A
    reparos      = [string][char]0xE90F
    historico    = [string][char]0xE81C
}

# A página Histórico não é um módulo: é do núcleo, e a interface a acrescenta no fim da barra lateral.
$script:PaginaHistorico = [pscustomobject]@{
    Nome = 'historico'; Titulo = 'Histórico'; Grupo = 'Registro'; Estado = 'ok'; Motivo = ''; Escreve = $true
    Descricao = 'O que o Tamanduá já fez. Ajustes podem ser desfeitos daqui.'; RotuloAcao = 'Desfazer'; Especial = $true
}
$script:CorStatusHistorico = @{ Erro = 'Critico'; Parcial = 'Atencao' }
$script:IconePadrao = [string][char]0xE74C
$script:MarcadorEstado = @{
    ok           = ''
    faltando     = [string][char]0xE711
    quebrado     = [string][char]0xE783
    indisponivel = [string][char]0xE7BA
}
$script:TextoSelo = @{ Aplicado = 'aplicado'; NaoAplicado = 'não aplicado'; Parcial = 'parcial'; Desconhecido = 'não lido' }

function Get-ValorPropriedade {
    param($Objeto, [string]$Nome)
    if ($null -eq $Objeto) { return $null }
    if ($Objeto -is [System.Collections.IDictionary]) {
        if ($Objeto.Contains($Nome)) { return $Objeto[$Nome] }
        return $null
    }
    $p = $Objeto.PSObject.Properties[$Nome]
    if ($p) { return $p.Value }
    $null
}

# Lista da barra lateral: um cabeçalho por grupo, na ordem em que os grupos aparecem, seguido dos módulos dele.
function ConvertTo-ItemNavegacao {
    param([AllowEmptyCollection()][object[]]$Modulos = @())

    $itens = [System.Collections.Generic.List[object]]::new()
    $grupoAtual = $null
    foreach ($m in $Modulos) {
        if ($m.Grupo -ne $grupoAtual) {
            $grupoAtual = $m.Grupo
            $itens.Add([pscustomobject]@{
                    Tipo = 'Grupo'; Nome = ''; Rotulo = $m.Grupo; Icone = ''; Marcador = ''; Estado = ''; Motivo = $null
                })
        }
        $icone = if ($script:IconesModulo.ContainsKey($m.Nome)) { $script:IconesModulo[$m.Nome] } else { $script:IconePadrao }
        $motivo = if ($m.Motivo) { $m.Motivo } else { $null }
        $itens.Add([pscustomobject]@{
                Tipo     = 'Modulo'
                Nome     = $m.Nome
                Rotulo   = $m.Titulo
                Icone    = $icone
                Marcador = $script:MarcadorEstado[$m.Estado]
                Estado   = $m.Estado
                Motivo   = $motivo
            })
    }
    , $itens.ToArray()
}

# Ícone de cada categoria na grade (Segoe Fluent Icons), pelo nome dela. A ordem importa: "Rede (DNS)" é DNS antes de
# Rede, "Caches do Windows" é cache antes de Windows. Sem acerto: sem ícone (o quadro mostra a inicial).
$script:GlifosCategoria = [ordered]@{
    'Privacidade'                      = 0xE72E
    'Segurança'                        = 0xEA18
    'DNS'                              = 0xE774
    'Navegador'                        = 0xE774
    'Cache'                            = 0xEDA2
    'Disco'                            = 0xEDA2
    'Relatório|log'                    = 0xE9F9
    'Limpeza|Temporário|Lixeira'       = 0xE74D
    'jogo'                             = 0xE7FC
    'Desempenho'                       = 0xEC4A
    'Itens do Windows'                 = 0xE8FD
    'Programa'                         = 0xE7B8
    'Apps'                             = 0xE71D
    'Explorador'                       = 0xE8B7
    'Barra de tarefas'                 = 0xE7C4
    'Aparência|Estilo'                 = 0xE790
    'Mouse|teclado'                    = 0xE962
    'Energia'                          = 0xE945
    'Rede'                             = 0xE701
    'Avançado'                         = 0xE7BA
    'Processo|Resumo'                  = 0xE9D9
    'atualiza|Quando'                  = 0xE895
    'Reinício'                         = 0xE7E8
    'Desenvolvimento|virtualização'    = 0xE943
    'Compatibilidade'                  = 0xE8F1
    'Mídia|impressão'                  = 0xE749
    'Sistema'                          = 0xE770
}

function Get-GlifoCategoria {
    param([string]$Categoria)
    if (-not $Categoria) { return '' }
    foreach ($p in $script:GlifosCategoria.Keys) { if ($Categoria -match $p) { return [string][char]$script:GlifosCategoria[$p] } }
    ''
}

# Linhas da lista de alvos, com um cabeçalho por categoria. -Busca filtra por nome, detalhe ou categoria.
# -Escreve: módulo que altera o sistema; cada linha ganha uma caixa de seleção.
# -Cache (Id -> linha): linhas já montadas para estes mesmos alvos são reusadas (só a marca é atualizada). A busca
# refaz a lista a cada tecla e montar 190 linhas custava ~0,35 s; quem chama zera o cache quando os alvos mudam.
function ConvertTo-LinhaAlvo {
    param([AllowEmptyCollection()][object[]]$Alvos = @(), [string]$Busca, [switch]$Escreve, [hashtable]$Cache)

    $termo = if ($Busca) { $Busca.Trim() } else { '' }
    $linhas = [System.Collections.Generic.List[object]]::new()
    $categoriaAtual = $null
    foreach ($a in $Alvos) {
        $id = [string](Get-ValorPropriedade $a 'Id')
        $guardada = if ($null -ne $Cache -and $id -and $Cache.ContainsKey($id) -and [object]::ReferenceEquals($Cache[$id].Alvo, $a)) { $Cache[$id] } else { $null }
        if ($guardada) {
            if ($termo -and "$($guardada.Nome) $($guardada.Detalhe) $($guardada.Categoria)".IndexOf($termo, [StringComparison]::OrdinalIgnoreCase) -lt 0) { continue }
            if ($guardada.Categoria -ne $categoriaAtual) {
                $categoriaAtual = $guardada.Categoria
                $linhas.Add((New-LinhaAlvo -Tipo 'Categoria' -Nome $categoriaAtual))
            }
            $guardada.Selecionado = $Escreve -and (Get-ValorPropriedade $a 'Selecionado') -eq $true
            $linhas.Add($guardada)
            continue
        }
        $nome = [string](Get-ValorPropriedade $a 'Nome')
        $categoria = [string](Get-ValorPropriedade $a 'Categoria')
        $detalhe = [string](Get-ValorPropriedade $a 'Detalhe')
        if ($termo -and "$nome $detalhe $categoria".IndexOf($termo, [StringComparison]::OrdinalIgnoreCase) -lt 0) { continue }

        if ($categoria -ne $categoriaAtual) {
            $categoriaAtual = $categoria
            $linhas.Add((New-LinhaAlvo -Tipo 'Categoria' -Nome $categoria))
        }
        $estado = [string](Get-ValorPropriedade $a 'Estado')
        $nivel = [string](Get-ValorPropriedade $a 'Nivel')
        $valor = Get-ValorPropriedade $a 'Valor'
        $temValor = $null -ne $valor -and ($valor -is [int] -or $valor -is [long] -or $valor -is [double] -or $valor -is [decimal])
        # O módulo pode trocar o texto do selo (ex.: "instalado", "atualizar para 1.2"); a cor continua vindo do Estado.
        $seloProprio = [string](Get-ValorPropriedade $a 'Selo')
        $selo = if ($seloProprio) { $seloProprio } elseif ($script:TextoSelo.ContainsKey($estado)) { $script:TextoSelo[$estado] } else { '' }
        $tamanho = Get-ValorPropriedade $a 'Tamanho'
        $linha = New-LinhaAlvo -Tipo 'Alvo' -Nome $nome -Categoria $categoria -Detalhe $detalhe -Estado $estado `
            -Nivel $(if ($nivel) { $nivel } else { 'Normal' }) -Valor $(if ($temValor) { [double]$valor } else { 0 }) `
            -TemValor $temValor -Selo $selo -Id $id -Alvo $a `
            -TemCaixa ($Escreve -and (Get-ValorPropriedade $a 'Selecionavel') -ne $false) `
            -Selecionado ($Escreve -and (Get-ValorPropriedade $a 'Selecionado') -eq $true) `
            -Tamanho $(if ($tamanho -gt 0) { [int64]$tamanho } else { 0 }) `
            -RequerAdmin ((Get-ValorPropriedade $a 'RequerAdmin') -eq $true) -ReservaCaixa $Escreve.IsPresent `
            -IconePng (Get-ValorPropriedade $a 'IconePng') -Classe ([string](Get-ValorPropriedade $a 'Classificacao')) `
            -Estrela ((Get-ValorPropriedade $a 'Estrela') -eq $true) `
            -Amostra ([string](Get-ValorPropriedade $a 'Amostra')) -AmostraFonte ([string](Get-ValorPropriedade $a 'AmostraFonte')) `
            -Glifo $(if (Get-ValorPropriedade $a 'Glifo') { [string](Get-ValorPropriedade $a 'Glifo') } elseif (-not (Get-ValorPropriedade $a 'IconePng')) { Get-GlifoCategoria -Categoria $categoria } else { '' }) `
            -MostraDetalhe (-not $Escreve)
        if ($null -ne $Cache -and $id) { $Cache[$id] = $linha }
        $linhas.Add($linha)
    }
    , $linhas.ToArray()
}

# Toda linha tem as mesmas propriedades: o WPF liga tudo pelo nome, e cabeçalho e item usam o mesmo modelo.
function New-LinhaAlvo {
    param(
        [string]$Tipo, [string]$Nome, [string]$Categoria = '', [string]$Detalhe = '', [string]$Estado = '',
        [string]$Nivel = 'Normal', [double]$Valor = 0, [bool]$TemValor = $false, [string]$Selo = '', [string]$Id = '', $Alvo = $null,
        [bool]$TemCaixa = $false, [bool]$Selecionado = $false, [int64]$Tamanho = 0, [bool]$RequerAdmin = $false,
        # Em página de módulo que escreve, item sem caixa ainda guarda o espaço dela (as colunas não desalinham).
        [bool]$ReservaCaixa = $false,
        # Grade: ícone em PNG (vira imagem na janela, em Set-TmdImagensLinha); sem ícone, o quadro mostra a inicial do nome.
        [byte[]]$IconePng = $null,
        # Ajustes: Recomendado, Opcional, Atencao ou Arriscado (selo colorido). Programas: estrela do FMHY.
        [string]$Classe = '', [bool]$Estrela = $false,
        # Grade: texto grande no lugar do ícone (a página Fonte mostra "Aa" desenhado na própria fonte de AmostraFonte).
        [string]$Amostra = '', [string]$AmostraFonte = '',
        # Grade: ícone (Segoe Fluent Icons) no lugar da inicial, e o detalhe à vista no quadro (páginas que só mostram, como Status).
        [string]$Glifo = '', [bool]$MostraDetalhe = $false
    )
    $inicial = if ($Glifo) { $Glifo } elseif ($Nome) { $Nome.Trim().Substring(0, 1).ToUpperInvariant() } else { '' }
    $rotulo = if ($script:RotuloClasse.ContainsKey($Classe)) { $script:RotuloClasse[$Classe] } else { '' }
    [pscustomobject]@{
        Tipo = $Tipo; Id = $Id; Nome = $Nome; Categoria = $Categoria; Detalhe = $Detalhe; Estado = $Estado; Nivel = $Nivel
        Valor = $Valor; TemValor = $TemValor; Selo = $Selo; TemSelo = [bool]$Selo; Alvo = $Alvo
        TemCaixa = $TemCaixa; Selecionado = $Selecionado; Tamanho = $Tamanho; RequerAdmin = $RequerAdmin; ReservaCaixa = $ReservaCaixa
        IconePng = $IconePng; Inicial = $inicial; Imagem = $null; TemImagem = $false
        Classe = $Classe; RotuloClasse = $rotulo; TemClasse = [bool]$rotulo; DicaClasse = $(if ($rotulo) { $script:DicaClasse[$Classe] } else { $null })
        Estrela = $Estrela; Grande = $false
        # Sem AmostraFonte, a fonte da própria janela (o Binding não aceita texto vazio como fonte).
        Amostra = $Amostra; AmostraFonte = $(if ($AmostraFonte) { $AmostraFonte } else { 'Segoe UI' }); TemAmostra = [bool]$Amostra
        TemGlifo = [bool]$Glifo; MostraDetalhe = $MostraDetalhe -and [bool]$Detalhe
        TamanhoTexto = $(if ($Tamanho -gt 0) { Format-TamanhoTela $Tamanho } else { '' }); TemTamanho = $Tamanho -gt 0
        # Pastas: até 4 miniaturas (imagens, ou as amostras de texto dos itens) e os itens dentro. Toda linha tem as
        # propriedades (vazias): Binding que não acha a propriedade custa caro no WPF, multiplicado por cada quadro da grade.
        Mini0 = $null; Mini1 = $null; Mini2 = $null; Mini3 = $null; Membros = $null
        MiniTexto0 = ''; MiniTexto1 = ''; MiniTexto2 = ''; MiniTexto3 = ''
        MiniFonte0 = 'Segoe UI'; MiniFonte1 = 'Segoe UI'; MiniFonte2 = 'Segoe UI'; MiniFonte3 = 'Segoe UI'; TemMiniTexto = $false
        GlifoPasta = ''; TemGlifoPasta = $false
    }
}

# Pastas de alternativas (como as do menu Iniciar do Windows 11). Fechadas: os itens de um mesmo Grupo (2 ou mais
# na categoria) viram uma linha 'Pasta' no lugar do primeiro, com até 4 miniaturas. -PastaAberta: só os itens dela,
# com um título e um quadro 'Voltar'. Só muda o que aparece: a marca de cada item continua no próprio alvo.
function ConvertTo-LinhasComPastas {
    param([AllowEmptyCollection()][object[]]$Linhas = @(), [string]$PastaAberta = '')
    # Uma passada para saber o grupo de cada linha e juntar os membros; outra para montar a saída.
    $grupos = [object[]]::new($Linhas.Count)
    $membrosDe = @{}
    for ($i = 0; $i -lt $Linhas.Count; $i++) {
        $l = $Linhas[$i]
        $g = if ($l.Tipo -eq 'Alvo') { [string](Get-ValorPropriedade $l.Alvo 'Grupo') } else { '' }
        $grupos[$i] = $g
        if (-not $g) { continue }
        $chave = if ($PastaAberta) { $g } else { "$($l.Categoria)|$g" }
        if (-not $membrosDe.ContainsKey($chave)) { $membrosDe[$chave] = [System.Collections.Generic.List[object]]::new() }
        $membrosDe[$chave].Add($l)
    }
    if ($PastaAberta) {
        if (-not $membrosDe.ContainsKey($PastaAberta)) { return , $Linhas }
        $saida = @((New-LinhaAlvo -Tipo 'Categoria' -Nome $PastaAberta), (New-LinhaPasta -Tipo 'Voltar' -Nome 'Voltar' -Membros @())) + $membrosDe[$PastaAberta].ToArray()
        return , $saida
    }
    $feitas = @{}
    $saida = [System.Collections.Generic.List[object]]::new()
    for ($i = 0; $i -lt $Linhas.Count; $i++) {
        $l = $Linhas[$i]; $g = $grupos[$i]
        $chave = "$($l.Categoria)|$g"
        if (-not $g -or $membrosDe[$chave].Count -lt 2) { $saida.Add($l); continue }
        if ($feitas.ContainsKey($chave)) { continue }
        $feitas[$chave] = $true
        $saida.Add((New-LinhaPasta -Tipo 'Pasta' -Nome $g -Categoria $l.Categoria -Membros $membrosDe[$chave].ToArray()))
    }
    , $saida.ToArray()
}

# Categorias como pastas (o "View: Category" do menu Iniciar do Windows 11). Fechada: um quadro grande por categoria,
# com os 4 primeiros ícones. Aberta: o Voltar e os itens da categoria, separados por tipo (o Grupo de cada um vira um
# subtítulo, "Players de vídeo", "Edição de imagem"...); os sem grupo vêm primeiro. Só muda o que aparece.
function ConvertTo-LinhasPorCategoria {
    param([AllowEmptyCollection()][object[]]$Linhas = @(), [string]$Aberta = '')
    $ordem = [System.Collections.Generic.List[string]]::new()
    $membros = @{}
    foreach ($l in $Linhas) {
        if ($l.Tipo -ne 'Alvo') { continue }
        if (-not $membros.ContainsKey($l.Categoria)) { $membros[$l.Categoria] = [System.Collections.Generic.List[object]]::new(); $ordem.Add($l.Categoria) }
        $membros[$l.Categoria].Add($l)
    }
    if (-not $Aberta) {
        # Categoria de um item só (o "Atualizar tudo") não vira pasta: o item aparece direto, antes das pastas.
        # Fica do tamanho das pastas (Grande); quem chama zera isso nas outras vistas, porque a linha vem do cache.
        $sos = @(foreach ($cat in $ordem) { if ($membros[$cat].Count -eq 1) { $membros[$cat][0].Grande = $true; $membros[$cat][0] } })
        $pastas = @(foreach ($cat in $ordem) { if ($membros[$cat].Count -gt 1) { New-LinhaPasta -Tipo 'Secao' -Nome $cat -Membros $membros[$cat].ToArray() } })
        return , @($sos + $pastas)
    }
    if (-not $membros.ContainsKey($Aberta)) { return , $Linhas }
    $soltos = [System.Collections.Generic.List[object]]::new()
    $grupos = [ordered]@{}
    foreach ($l in $membros[$Aberta]) {
        $g = [string](Get-ValorPropriedade $l.Alvo 'Grupo')
        if (-not $g) { $soltos.Add($l); continue }
        if (-not $grupos.Contains($g)) { $grupos[$g] = [System.Collections.Generic.List[object]]::new() }
        $grupos[$g].Add($l)
    }
    $saida = [System.Collections.Generic.List[object]]::new()
    $saida.Add((New-LinhaAlvo -Tipo 'Categoria' -Nome $Aberta))
    $saida.Add((New-LinhaPasta -Tipo 'Voltar' -Nome 'Voltar' -Membros @()))
    foreach ($l in $soltos) { $saida.Add($l) }
    foreach ($g in $grupos.Keys) {
        $saida.Add((New-LinhaAlvo -Tipo 'Categoria' -Nome $g))
        foreach ($l in $grupos[$g]) { $saida.Add($l) }
    }
    , $saida.ToArray()
}

# Como contar os itens de uma pasta: "singular|plural" (NomeItens no manifesto: "programa|programas", "opção|opções").
$script:NomeItens = 'item|itens'

function New-LinhaPasta {
    param([string]$Tipo, [string]$Nome, [string]$Categoria = '', [object[]]$Membros)
    $nomes = @($script:NomeItens -split '\|', 2)
    $um = $nomes[0]
    $varios = if ($nomes.Count -gt 1) { $nomes[1] } else { $nomes[0] }
    $marcadas = @($Membros | Where-Object Selecionado)
    # Item de escolha única marcado (ex.: a fonte escolhida): a pasta diz qual.
    $unico = $marcadas.Count -eq 1 -and $marcadas[0].Alvo -and [string](Get-ValorPropriedade $marcadas[0].Alvo 'Exclusivo')
    $selo = if ($Tipo -eq 'Voltar') { '' } elseif ($unico) { "$([char]0x2713) $($marcadas[0].Nome)" } elseif ($marcadas.Count -gt 0) { "$($marcadas.Count) de $($Membros.Count) marcados" } elseif ($Membros.Count -eq 1) { "1 $um" } else { "$($Membros.Count) $varios" }
    $linha = New-LinhaAlvo -Tipo $Tipo -Nome $Nome -Categoria $Categoria -Selo $selo `
        -Detalhe $(if ($Tipo -eq 'Voltar') { 'Fechar a pasta' } elseif ($Tipo -eq 'Secao') { "$($Membros.Count) $($varios): $(($Membros | Select-Object -First 6 | ForEach-Object Nome) -join ', ')$(if ($Membros.Count -gt 6) { '...' })" } else { "Alternativas: $(($Membros | ForEach-Object Nome) -join ', ')" })
    if ($Tipo -eq 'Voltar') { $linha.Inicial = [string][char]0x2190 }
    # Miniaturas: imagens dos primeiros com ícone (objetos .NET puros, como em Set-TmdImagensLinha); sem imagens, as
    # amostras de texto dos primeiros (o "Aa" de cada fonte).
    $i = 0
    foreach ($m in $Membros) { if ($m.TemImagem -and $i -lt 4) { $linha."Mini$i" = $m.Imagem; $i++ } }
    if ($i -eq 0) {
        foreach ($m in $Membros) {
            if (-not $m.TemAmostra -or $i -ge 4) { continue }
            $linha."MiniTexto$i" = $m.Amostra
            $linha."MiniFonte$i" = $m.AmostraFonte
            $i++
        }
        $linha.TemMiniTexto = $i -gt 0
    }
    # Nem imagem nem amostra (Ajustes): o ícone da categoria, grande.
    if ($i -eq 0) {
        $comGlifo = @($Membros | Where-Object { $_.TemGlifo })
        if ($comGlifo.Count -gt 0) { $linha.GlifoPasta = $comGlifo[0].Inicial; $linha.TemGlifoPasta = $true }
    }
    $linha.Membros = $Membros
    $linha
}

# Conteúdo do painel de detalhes, em pedaços (a janela desenha cada um num cartão): o que é, selos (estado,
# classificação, estrela), o que pode dar errado e como resolver (com o tom da classificação) e o que acontece.
function Get-DetalheAlvo {
    param([Parameter(Mandatory)]$Linha)
    $selos = [System.Collections.Generic.List[object]]::new()
    if ($Linha.TemSelo) {
        $tom = switch ($Linha.Estado) { 'Aplicado' { 'Sucesso' } 'Parcial' { 'Aviso' } default { 'TextoSecundario' } }
        $fundo = switch ($Linha.Estado) { 'Aplicado' { 'SucessoFundo' } 'Parcial' { 'AvisoFundo' } default { 'SuperficieLateral' } }
        $selos.Add([pscustomobject]@{ Texto = $Linha.Selo; Tom = $tom; Fundo = $fundo; Dica = $null })
    }
    if ($Linha.TemClasse) {
        $cores = @{ Recomendado = 'Sucesso', 'SucessoFundo'; Opcional = 'TextoSecundario', 'SuperficieLateral'; Atencao = 'Aviso', 'AvisoFundo'; Arriscado = 'Perigo', 'PerigoFundo' }
        $cor = $cores[$Linha.Classe]
        $selos.Add([pscustomobject]@{ Texto = $Linha.RotuloClasse; Tom = $cor[0]; Fundo = $cor[1]; Dica = $script:DicaClasse[$Linha.Classe] })
    }
    if ($Linha.Estrela) { $selos.Add([pscustomobject]@{ Texto = "$([char]0x2B50) Recomendado pelo FMHY"; Tom = 'Aviso'; Fundo = 'AvisoFundo'; Dica = $null }) }
    $sobre = [string]$Linha.Detalhe
    $mudancas = @(Get-ValorPropriedade $Linha.Alvo 'Mudancas' | Where-Object { $_ })
    [pscustomobject]@{
        Sobre    = $sobre
        Selos    = $selos.ToArray()
        Problema = [string](Get-ValorPropriedade $Linha.Alvo 'Contratempo')
        Solucao  = [string](Get-ValorPropriedade $Linha.Alvo 'SeAcontecer')
        Tom      = switch ($Linha.Classe) { 'Arriscado' { 'Perigo' } 'Atencao' { 'Aviso' } default { '' } }
        Mudancas = if ($mudancas.Count -gt 0) { '• ' + ($mudancas -join "`n• ") } else { '' }
    }
}

# Os quatro selos de classificação dos ajustes, com a explicação que aparece ao parar o mouse em cima.
$script:RotuloClasse = @{ Recomendado = 'Recomendado'; Opcional = 'Opcional'; Atencao = 'Atenção'; Arriscado = 'Arriscado' }
$script:DicaClasse = @{
    Recomendado = 'Bom para quase todo mundo, sem efeito colateral que se note.'
    Opcional    = 'Questão de gosto: não atrapalha nada.'
    Atencao     = 'Funciona, mas pode dar um contratempo em certos casos. Veja nos detalhes o que pode acontecer e como resolver.'
    Arriscado   = 'Mexe em segurança ou em algo que o Windows usa por baixo. Só se souber o que está fazendo; veja nos detalhes.'
}

# Igual ao Format-TmdTamanho do núcleo; a interface não carrega o núcleo na thread da janela.
function Format-TamanhoTela {
    param([double]$Bytes)
    $unidades = 'B', 'KB', 'MB', 'GB', 'TB'
    $i = 0
    while ($Bytes -ge 1024 -and $i -lt $unidades.Count - 1) { $Bytes /= 1024; $i++ }
    if ($i -eq 0) { return '{0:N0} B' -f $Bytes }
    '{0:N1} {1}' -f $Bytes, $unidades[$i]
}

# "2 selecionados · 3,2 GB", contando só linhas de alvo marcadas (e que podem ser marcadas).
# O que está escolhido em cada grupo de escolha única (manifesto Grupos): "Fonte: Arial · Tamanho: automático".
# Grupo sem escolha mostra o texto Vazio dele; itens marcados fora dos grupos entram como "+ N item(ns)".
function Get-ResumoGrupos {
    param([AllowEmptyCollection()][object[]]$Grupos = @(), [AllowEmptyCollection()][object[]]$Alvos = @())
    $marcados = @($Alvos | Where-Object { (Get-ValorPropriedade $_ 'Selecionado') -eq $true })
    $partes = [System.Collections.Generic.List[string]]::new()
    foreach ($g in $Grupos) {
        $escolhido = @($marcados | Where-Object { [string](Get-ValorPropriedade $_ 'Exclusivo') -eq $g.Nome })
        $texto = if ($escolhido.Count -eq 0) { $g.Vazio } else {
            $a = $escolhido[0]
            $valor = Get-ValorPropriedade $a 'ValorEscolhido'
            if ($null -ne $valor) { "$(Get-ValorPropriedade $a 'Nome') ($(Get-ValorPropriedade $a 'Selo'))" } else { [string](Get-ValorPropriedade $a 'Nome') }
        }
        $partes.Add("$($g.Rotulo): $texto")
    }
    $outros = @($marcados | Where-Object { -not [string](Get-ValorPropriedade $_ 'Exclusivo') }).Count
    if ($outros -gt 0) { $partes.Add("+ $outros $(if ($outros -eq 1) { 'item' } else { 'itens' })") }
    $partes -join ' · '
}

function Get-ResumoSelecao {
    param([AllowEmptyCollection()][object[]]$Linhas = @())
    $marcadas = @($Linhas | Where-Object { $_.Tipo -eq 'Alvo' -and $_.Selecionado -and $_.TemCaixa })
    $bytes = [int64]0
    foreach ($l in $marcadas) { $bytes += $l.Tamanho }
    $texto = if ($marcadas.Count -eq 1) { '1 selecionado' } else { "$($marcadas.Count) selecionados" }
    if ($bytes -gt 0) { $texto += " · $(Format-TamanhoTela $bytes)" }
    $alvos = @($marcadas | ForEach-Object { $_.Alvo })
    [pscustomobject]@{
        Quantidade      = $marcadas.Count
        Bytes           = $bytes
        Texto           = $texto
        Alvos           = $alvos
        Irreversiveis   = @($alvos | Where-Object { (Get-ValorPropriedade $_ 'Reversivel') -eq $false }).Count
        Reversiveis     = @($alvos | Where-Object { (Get-ValorPropriedade $_ 'Reversivel') -eq $true }).Count
        NaLixeira       = @($alvos | Where-Object { (Get-ValorPropriedade $_ 'Destino') -eq 'Lixeira' }).Count
        Desfazendo      = @($alvos | Where-Object { (Get-ValorPropriedade $_ 'Desfaz') -eq $true }).Count
        # Arriscados que vão ser aplicados (desfazer um arriscado só volta ao normal).
        Arriscados      = @($alvos | Where-Object { (Get-ValorPropriedade $_ 'Classificacao') -eq 'Arriscado' -and (Get-ValorPropriedade $_ 'Desfaz') -ne $true } |
                ForEach-Object { [string](Get-ValorPropriedade $_ 'Nome') })
    }
}

# Frase que fecha a pergunta de confirmação: diz se dá para voltar atrás, e como.
function Get-AvisoConfirmacao {
    param([Parameter(Mandatory)]$Resumo, [bool]$Especial)
    $desfaz = if ((Get-ValorPropriedade $Resumo 'Desfazendo') -gt 0) { " $($Resumo.Desfazendo) já aplicado(s) será(ão) DESFEITO(S)." } else { '' }
    $arriscados = @(Get-ValorPropriedade $Resumo 'Arriscados' | Where-Object { $_ })
    $risco = if ($arriscados.Count -gt 0) { " ARRISCADO ($($arriscados.Count)): $($arriscados -join ', ') — veja nos detalhes o que pode dar errado." } else { '' }
    $risco + $desfaz + (Get-AvisoReversao -Resumo $Resumo -Especial $Especial)
}

function Get-AvisoReversao {
    param([Parameter(Mandatory)]$Resumo, [bool]$Especial)
    if ($Resumo.Irreversiveis -gt 0) { return ' Isso não pode ser desfeito.' }
    if ($Resumo.Quantidade -gt 0 -and $Resumo.NaLixeira -eq $Resumo.Quantidade) { return ' Vai para a Lixeira (dá para recuperar de lá).' }
    if ($Resumo.Quantidade -gt 0 -and $Resumo.Reversiveis -eq $Resumo.Quantidade -and -not $Especial) { return ' Dá para desfazer pelo Histórico.' }
    ''
}

# Nomes de preset que aparecem nos alvos, na ordem em que surgem, mais "Nenhum" para desmarcar tudo.
function Get-PresetAlvo {
    param([AllowEmptyCollection()][object[]]$Alvos = @())
    $nomes = [System.Collections.Generic.List[string]]::new()
    foreach ($a in $Alvos) {
        foreach ($p in @(Get-ValorPropriedade $a 'Presets')) {
            if ($p -and -not $nomes.Contains([string]$p)) { $nomes.Add([string]$p) }
        }
    }
    if ($nomes.Count -eq 0) { return , @() }
    $nomes.Add('Nenhum')
    , $nomes.ToArray()
}

# Marca exatamente os alvos do preset (e desmarca o resto). Devolve quantos ficaram marcados.
function Set-SelecaoPreset {
    param([AllowEmptyCollection()][object[]]$Alvos = @(), [Parameter(Mandatory)][string]$Preset)
    $n = 0
    foreach ($a in $Alvos) {
        if (-not $a.PSObject.Properties['Selecionado']) { continue }
        # Item já aplicado (Desfaz): marcado ele seria desfeito, então preset nunca marca.
        $a.Selecionado = $Preset -ne 'Nenhum' -and (Get-ValorPropriedade $a 'Desfaz') -ne $true -and @(Get-ValorPropriedade $a 'Presets') -contains $Preset
        if ($a.Selecionado) { $n++ }
    }
    $n
}

# Operações do log -> linhas da página Histórico, agrupadas por dia. Só ajustes reversíveis ganham caixa.
function ConvertTo-AlvoHistorico {
    param([AllowEmptyCollection()][object[]]$Operacoes = @())
    $i = 0
    foreach ($o in $Operacoes) {
        $i++
        $data = try { [datetime]$o.Data } catch { $null }
        $acao = [string](Get-ValorPropriedade $o 'Acao')
        $nome = if ($acao -in 'ajustar', 'desfazer') { "$(if ($acao -eq 'ajustar') { 'Ajuste' } else { 'Desfeito' }): $($o.Caminho)" } else { [string]$o.Caminho }
        $partes = @([string]$o.Status)
        if ($o.Simulado) { $partes[0] = 'Simulado' }
        if ($o.Modulo) { $partes += [string]$o.Modulo }
        if ($o.Liberado -gt 0) { $partes += Format-TamanhoTela $o.Liberado }
        if ($data) { $partes += $data.ToString('HH:mm') }
        if ($o.Motivo) { $partes += [string]$o.Motivo }
        $reversivel = (Get-ValorPropriedade $o 'Reversivel') -eq $true
        [pscustomobject]@{
            Id           = "op-$i"
            IdAjuste     = [string]$o.Id
            Nome         = $nome
            Categoria    = if ($data) { $data.ToString('dd/MM/yyyy') } else { 'sem data' }
            Estado       = 'NaoSeAplica'
            Detalhe      = $partes -join ' · '
            Nivel        = if ($script:CorStatusHistorico.ContainsKey([string]$o.Status)) { $script:CorStatusHistorico[[string]$o.Status] } else { 'Normal' }
            Selecionavel = $reversivel
            Selecionado  = $false
            Mudancas     = @(Get-MotivoHistorico -Operacao $o -Acao $acao -Reversivel $reversivel)
        }
    }
}

# O que o Histórico diz de uma operação no painel de detalhes: como desfazer, ou por que não dá.
function Get-MotivoHistorico {
    param($Operacao, [string]$Acao, [bool]$Reversivel)
    $paginaAjustes = 'Para voltar ao padrão do Windows, marque o ajuste na página Ajustes (o selo diz "aplicado"; marcar desfaz).'
    if ($Reversivel) { return "Desfazer volta o ajuste '$($Operacao.Id)' para o valor salvo antes de ele ser aplicado." }
    if ($Operacao.Simulado) { return 'Foi só uma simulação: nada mudou, então não há o que desfazer.' }
    if ($Acao -eq 'ajustar' -and [string]$Operacao.Motivo -eq 'já estava aplicado') { return "Já estava aplicado antes (por outra ferramenta): o Tamanduá não mudou nada aqui. $paginaAjustes" }
    if ($Acao -eq 'ajustar' -and [string]$Operacao.Status -eq 'Feito') { return "O valor de antes não está mais salvo (o ajuste já foi desfeito ou aplicado de novo depois). $paginaAjustes" }
    if ($Acao -eq 'ajustar') { return 'Não foi aplicado, então não há o que desfazer.' }
    if ($Acao -eq 'remover') { return 'Remoção de arquivos: o que foi para a Lixeira se recupera de lá; o resto não volta.' }
    if ($Acao -eq 'desfazer') { return 'Isto já é um desfazer.' }
    'Este tipo de operação não tem desfazer.'
}

# Resumo de Invoke-Acao para a barra de status, com a cor (token do tema) que combina.
# -Acao 'desfazer' fala de ajustes desfeitos em vez de espaço liberado.
function Get-TextoResultado {
    param([AllowEmptyCollection()][object[]]$Resultados = @(), [bool]$Simulado, [string]$Acao = 'liberar', [bool]$DaParaDesfazer = $true)

    if ($Acao -eq 'ajustar') {
        $ok = @($Resultados | Where-Object { $_.Status -in 'Feito', 'Simulado' }).Count
        $falhas = @($Resultados | Where-Object { $_.Status -notin 'Feito', 'Simulado' })
        $palavra = if ($DaParaDesfazer) { 'ajuste(s)' } else { 'item(ns)' }
        if ($Simulado) { return [pscustomobject]@{ Texto = "Simulação: $ok $palavra seriam aplicados. Nada foi alterado."; Cor = 'TextoSecundario' } }
        if ($falhas.Count -gt 0) {
            $cor = if (@($falhas | Where-Object Status -eq 'Erro').Count -gt 0) { 'Perigo' } else { 'Aviso' }
            return [pscustomobject]@{ Texto = "Concluídos: $ok · não concluído ($($falhas[0].Id)): $($falhas[0].Motivo)"; Cor = $cor }
        }
        if ($DaParaDesfazer) { return [pscustomobject]@{ Texto = "Aplicados: $ok ajuste(s). Dá para desfazer pelo Histórico."; Cor = 'Sucesso' } }
        return [pscustomobject]@{ Texto = "Concluídos: $ok item(ns)."; Cor = 'Sucesso' }
    }
    if ($Acao -eq 'desfazer') {
        $ok = @($Resultados | Where-Object { $_.Status -in 'Feito', 'Simulado' }).Count
        $falhas = @($Resultados | Where-Object { $_.Status -notin 'Feito', 'Simulado' })
        if ($Simulado) { return [pscustomobject]@{ Texto = "Simulação: $ok ajuste(s) seriam desfeitos. Nada foi alterado."; Cor = 'TextoSecundario' } }
        if ($falhas.Count -gt 0) { return [pscustomobject]@{ Texto = "Desfeitos: $ok · não desfeito: $($falhas[0].Motivo)"; Cor = 'Perigo' } }
        return [pscustomobject]@{ Texto = "Desfeitos: $ok ajuste(s), de volta ao valor de antes."; Cor = 'Sucesso' }
    }
    $bytes = [int64]0
    foreach ($r in $Resultados) { $bytes += [int64]$r.Liberado }
    if ($Simulado) {
        return [pscustomobject]@{ Texto = "Simulação: liberaria $(Format-TamanhoTela $bytes). Nada foi alterado."; Cor = 'TextoSecundario' }
    }
    $erros = @($Resultados | Where-Object { $_.Status -eq 'Erro' })
    $parciais = @($Resultados | Where-Object { $_.Status -in 'Parcial', 'Ignorado' })
    $texto = "Liberado: $(Format-TamanhoTela $bytes)"
    $cor = 'Sucesso'
    if ($parciais.Count -gt 0) {
        $motivos = @($parciais | ForEach-Object { $_.Motivo } | Where-Object { $_ })
        if ($motivos.Count -gt 0) { $texto += " · $($motivos[0])" }
        $cor = 'Aviso'
    }
    if ($erros.Count -gt 0) {
        $texto += " · erro: $($erros[0].Motivo)"
        $cor = 'Perigo'
    }
    [pscustomobject]@{ Texto = $texto; Cor = $cor }
}

# O que mostrar no lugar da lista quando o módulo não está ok.
function Get-MensagemModulo {
    param([Parameter(Mandatory)]$Modulo)

    $continua = 'O resto do Tamanduá continua funcionando normalmente.'
    switch ($Modulo.Estado) {
        'faltando' {
            return [pscustomobject]@{ Icone = [string][char]0xEA86; Tom = 'Perigo'; Titulo = 'Módulo faltando'
                Texto = "$(Format-Frase $Modulo.Motivo) $continua" }
        }
        'quebrado' {
            return [pscustomobject]@{ Icone = $script:MarcadorEstado.quebrado; Tom = 'Perigo'; Titulo = 'Módulo com defeito'
                Texto = "$(Format-Frase $Modulo.Motivo) $continua" }
        }
        'indisponivel' {
            return [pscustomobject]@{ Icone = $script:MarcadorEstado.indisponivel; Tom = 'Aviso'; Titulo = 'Indisponível nesta máquina'
                Texto = "$(Format-Frase $Modulo.Motivo) $continua" }
        }
    }
    $null
}

# "pasta x não encontrada" -> "Pasta x não encontrada."
function Format-Frase {
    param([string]$Texto)
    if (-not $Texto) { return '' }
    $t = $Texto.Substring(0, 1).ToUpper() + $Texto.Substring(1)
    if ($t -notmatch '[.!?]$') { $t += '.' }
    $t
}

function Get-TextoEstadoAlvo {
    param([Parameter(Mandatory)]$Linha)

    switch ($Linha.Estado) {
        'Aplicado' { return 'Estado: aplicado' }
        'NaoAplicado' { return 'Estado: não aplicado' }
        'Parcial' { return 'Estado: parcialmente aplicado' }
        'Desconhecido' { return 'Não foi possível ler este item.' }
    }
    switch ($Linha.Nivel) {
        'Atencao' { return 'Pede atenção' }
        'Critico' { return 'Crítico' }
    }
    'Normal'
}

# Linha da barra de status depois de carregar uma página.
function Get-TextoStatusPagina {
    param([int]$Quantidade, [bool]$Escreve, [datetime]$Quando)

    $itens = if ($Quantidade -eq 1) { '1 item' } else { "$Quantidade itens" }
    $modo = if ($Escreve) { 'nada é alterado sem confirmação' } else { 'módulo só de leitura' }
    "$itens · atualizado às $($Quando.ToString('HH:mm:ss')) · $modo"
}

# "45 s", "3 min 05 s", "1 h 02 min": quanto tempo a tarefa já está rodando.
function Format-TempoDecorrido {
    param([Parameter(Mandatory)][timespan]$Tempo)
    $s = [int][math]::Floor($Tempo.TotalSeconds)
    if ($s -lt 60) { return "$s s" }
    if ($s -lt 3600) { return '{0} min {1:00} s' -f [math]::Floor($s / 60), ($s % 60) }
    '{0} h {1:00} min' -f [math]::Floor($s / 3600), [math]::Floor(($s % 3600) / 60)
}

# Traduz um registro de Write-Progress do núcleo (Status = item, CurrentOperation = "2 de 5") para a barra.
# Com um item só não há fração a mostrar: a barra fica indeterminada e o texto diz o que está rodando.
function ConvertFrom-TmdProgresso {
    param([Parameter(Mandatory)]$Registro, [Parameter(Mandatory)][timespan]$Decorrido, [string]$Verbo = 'Executando')
    $atual = 0
    $total = 0
    if ([string]$Registro.CurrentOperation -match '^(\d+) de (\d+)$') { $atual = [int]$Matches[1]; $total = [int]$Matches[2] }
    $partes = @("$Verbo $($Registro.StatusDescription)…")
    if ($total -gt 1) { $partes += "$atual de $total" }
    $partes += "há $(Format-TempoDecorrido -Tempo $Decorrido)"
    [pscustomobject]@{
        Texto         = $partes -join ' · '
        Indeterminado = ($total -le 1 -or $Registro.PercentComplete -lt 0)
        Porcento      = [math]::Max(0, [int]$Registro.PercentComplete)
    }
}
