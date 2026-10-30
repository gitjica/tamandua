# Funções puras: transformam dados do núcleo no que a tela mostra. Não tocam em WPF, então são testáveis sem janela.

# Glifos da fonte Segoe Fluent Icons / Segoe MDL2 Assets.
$script:IconesModulo = @{
    status       = [string][char]0xE9D9
    limpar       = [string][char]0xE74D
    instaladores = [string][char]0xE896
    desinstalar  = [string][char]0xE738
    programas    = [string][char]0xE7B8
    ajustes      = [string][char]0xE9E9
    'menu-contexto' = [string][char]0xE8FD
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

# Linhas da lista de alvos, com um cabeçalho por categoria. -Busca filtra por nome, detalhe ou categoria.
# -Escreve: módulo que altera o sistema; cada linha ganha uma caixa de seleção.
function ConvertTo-LinhaAlvo {
    param([AllowEmptyCollection()][object[]]$Alvos = @(), [string]$Busca, [switch]$Escreve)

    $termo = if ($Busca) { $Busca.Trim() } else { '' }
    $linhas = [System.Collections.Generic.List[object]]::new()
    $categoriaAtual = $null
    foreach ($a in $Alvos) {
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
        $linhas.Add((New-LinhaAlvo -Tipo 'Alvo' -Nome $nome -Categoria $categoria -Detalhe $detalhe -Estado $estado `
                    -Nivel $(if ($nivel) { $nivel } else { 'Normal' }) -Valor $(if ($temValor) { [double]$valor } else { 0 }) `
                    -TemValor $temValor -Selo $selo -Id ([string](Get-ValorPropriedade $a 'Id')) -Alvo $a `
                    -TemCaixa ($Escreve -and (Get-ValorPropriedade $a 'Selecionavel') -ne $false) `
                    -Selecionado ($Escreve -and (Get-ValorPropriedade $a 'Selecionado') -eq $true) `
                    -Tamanho $(if ($tamanho -gt 0) { [int64]$tamanho } else { 0 }) `
                    -RequerAdmin ((Get-ValorPropriedade $a 'RequerAdmin') -eq $true) -ReservaCaixa $Escreve.IsPresent `
                    -IconePng (Get-ValorPropriedade $a 'IconePng')))
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
        [byte[]]$IconePng = $null
    )
    $inicial = if ($Nome) { $Nome.Trim().Substring(0, 1).ToUpperInvariant() } else { '' }
    [pscustomobject]@{
        Tipo = $Tipo; Id = $Id; Nome = $Nome; Categoria = $Categoria; Detalhe = $Detalhe; Estado = $Estado; Nivel = $Nivel
        Valor = $Valor; TemValor = $TemValor; Selo = $Selo; TemSelo = [bool]$Selo; Alvo = $Alvo
        TemCaixa = $TemCaixa; Selecionado = $Selecionado; Tamanho = $Tamanho; RequerAdmin = $RequerAdmin; ReservaCaixa = $ReservaCaixa
        IconePng = $IconePng; Inicial = $inicial; Imagem = $null; TemImagem = $false
    }
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
    }
}

# Frase que fecha a pergunta de confirmação: diz se dá para voltar atrás, e como.
function Get-AvisoConfirmacao {
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
        $a.Selecionado = $Preset -ne 'Nenhum' -and @(Get-ValorPropriedade $a 'Presets') -contains $Preset
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
            Mudancas     = @(if ($reversivel) { "Desfazer volta o ajuste '$($o.Id)' para o valor salvo antes de ele ser aplicado." })
        }
    }
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
