# Funções puras: transformam dados do núcleo no que a tela mostra. Não tocam em WPF, então são testáveis sem janela.

# Glifos da fonte Segoe Fluent Icons / Segoe MDL2 Assets.
$script:IconesModulo = @{
    status       = [string][char]0xE9D9
    analisar     = [string][char]0xEB05
    limpar       = [string][char]0xE74D
    purgar       = [string][char]0xE8B7
    instaladores = [string][char]0xE896
    desinstalar  = [string][char]0xE738
    programas    = [string][char]0xE7B8
    ajustes      = [string][char]0xE9E9
    recursos     = [string][char]0xE8F1
    atualizacoes = [string][char]0xE895
    otimizar     = [string][char]0xEC4A
    reparos      = [string][char]0xE90F
}
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
function ConvertTo-LinhaAlvo {
    param([AllowEmptyCollection()][object[]]$Alvos = @(), [string]$Busca)

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
        $selo = if ($script:TextoSelo.ContainsKey($estado)) { $script:TextoSelo[$estado] } else { '' }
        $linhas.Add((New-LinhaAlvo -Tipo 'Alvo' -Nome $nome -Categoria $categoria -Detalhe $detalhe -Estado $estado `
                    -Nivel $(if ($nivel) { $nivel } else { 'Normal' }) -Valor $(if ($temValor) { [double]$valor } else { 0 }) `
                    -TemValor $temValor -Selo $selo -Id ([string](Get-ValorPropriedade $a 'Id')) -Alvo $a))
    }
    , $linhas.ToArray()
}

# Toda linha tem as mesmas propriedades: o WPF liga tudo pelo nome, e cabeçalho e item usam o mesmo modelo.
function New-LinhaAlvo {
    param(
        [string]$Tipo, [string]$Nome, [string]$Categoria = '', [string]$Detalhe = '', [string]$Estado = '',
        [string]$Nivel = 'Normal', [double]$Valor = 0, [bool]$TemValor = $false, [string]$Selo = '', [string]$Id = '', $Alvo = $null
    )
    [pscustomobject]@{
        Tipo = $Tipo; Id = $Id; Nome = $Nome; Categoria = $Categoria; Detalhe = $Detalhe; Estado = $Estado; Nivel = $Nivel
        Valor = $Valor; TemValor = $TemValor; Selo = $Selo; TemSelo = [bool]$Selo; Alvo = $Alvo
    }
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
