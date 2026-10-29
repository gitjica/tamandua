# Tudo que a CLI desenha na tela passa por aqui. Módulos nunca escrevem no console.

$script:CorEstado = @{ ok = 'Green'; faltando = 'Red'; quebrado = 'Red'; indisponivel = 'Yellow' }
$script:RotuloEstado = @{ ok = 'ok'; faltando = 'faltando'; quebrado = 'quebrado'; indisponivel = 'indisponível' }

function Write-TmdModulos {
    [CmdletBinding()]
    param([Parameter(Mandatory)][AllowEmptyCollection()][object[]]$Modulos)

    Write-Host ''
    $grupoAtual = $null
    foreach ($m in $Modulos) {
        if ($m.Grupo -ne $grupoAtual) {
            $grupoAtual = $m.Grupo
            Write-Host $grupoAtual -ForegroundColor DarkYellow
        }
        $texto = if ($m.Estado -eq 'ok') { $m.Descricao } else { $m.Motivo }
        Write-Host ('  {0,-14}' -f $m.Nome) -NoNewline
        Write-Host ('{0,-14}' -f $script:RotuloEstado[$m.Estado]) -ForegroundColor $script:CorEstado[$m.Estado] -NoNewline
        Write-Host $texto -ForegroundColor Gray
    }
    $disponiveis = @($Modulos | Where-Object { $_.Estado -eq 'ok' }).Count
    Write-Host ''
    Write-Host "$disponiveis de $($Modulos.Count) módulos disponíveis."
}

$script:CorNivel = @{ Normal = 'Gray'; Atencao = 'Yellow'; Critico = 'Red' }
# Desconhecido não ganha rótulo: o Detalhe já diz "não foi possível ler" e sai em cinza.
$script:RotuloEstadoAlvo = @{ Aplicado = 'aplicado'; NaoAplicado = 'não aplicado'; Parcial = 'parcial' }
$script:CorEstadoAlvo = @{ Aplicado = 'Green'; NaoAplicado = 'DarkGray'; Parcial = 'Yellow' }

# Mostra os alvos de um módulo agrupados por Categoria, na ordem em que aparecem.
function Write-TmdAlvos {
    [CmdletBinding()]
    param([Parameter(Mandatory)][AllowEmptyCollection()][object[]]$Alvos)

    if ($Alvos.Count -eq 0) {
        Write-Host 'Nada encontrado.'
        return
    }
    $nomes = @($Alvos | ForEach-Object { [string](Get-Propriedade -Objeto $_ -Nome 'Nome') })
    $largura = [Math]::Min(28, ($nomes | ForEach-Object Length | Measure-Object -Maximum).Maximum + 2)
    $i = 0
    $categoriaAtual = $null
    foreach ($a in $Alvos) {
        $categoria = [string](Get-Propriedade -Objeto $a -Nome 'Categoria')
        if ($categoria -ne $categoriaAtual) {
            if ($null -ne $categoriaAtual) { Write-Host '' }
            $categoriaAtual = $categoria
            Write-Host $categoria -ForegroundColor DarkYellow
        }
        $nivel = [string](Get-Propriedade -Objeto $a -Nome 'Nivel')
        $cor = if ((Get-Propriedade -Objeto $a -Nome 'Estado') -eq 'Desconhecido') { 'DarkGray' }
        elseif ($script:CorNivel.ContainsKey($nivel)) { $script:CorNivel[$nivel] }
        else { 'Gray' }
        $nome = $nomes[$i]
        if ($nome.Length -gt $largura - 2) { $nome = $nome.Substring(0, $largura - 3) + '…' }
        $selecionado = Get-Propriedade -Objeto $a -Nome 'Selecionado'
        $marca = if ($null -eq $selecionado) { '  ' } elseif ($selecionado) { '[x] ' } else { '[ ] ' }
        Write-Host ("$marca{0,-$largura}" -f $nome) -NoNewline
        $i++
        $estado = [string](Get-Propriedade -Objeto $a -Nome 'Estado')
        # O módulo pode dar um texto próprio (ex.: "instalado", "não existe nesta edição"); a cor continua vindo do Estado.
        $selo = [string](Get-Propriedade -Objeto $a -Nome 'Selo')
        if (-not $selo -and $script:RotuloEstadoAlvo.ContainsKey($estado)) { $selo = $script:RotuloEstadoAlvo[$estado] }
        if ($selo) {
            $corSelo = if ($script:CorEstadoAlvo.ContainsKey($estado)) { $script:CorEstadoAlvo[$estado] } else { 'DarkGray' }
            Write-Host ('{0,-15}' -f $selo) -NoNewline -ForegroundColor $corSelo
            if ($selo.Length -ge 15) { Write-Host ' ' -NoNewline }
        }
        Write-Host ([string](Get-Propriedade -Objeto $a -Nome 'Detalhe')) -ForegroundColor $cor
    }
}

# 1536 -> "1,5 KB". Usa a cultura atual para o separador decimal.
function Format-TmdTamanho {
    [CmdletBinding()]
    param([Parameter(Mandatory)][double]$Bytes)

    if ($Bytes -lt 0) { return 'desconhecido' }
    $unidades = 'B', 'KB', 'MB', 'GB', 'TB'
    $i = 0
    while ($Bytes -ge 1024 -and $i -lt $unidades.Count - 1) {
        $Bytes /= 1024
        $i++
    }
    if ($i -eq 0) { return '{0:N0} B' -f $Bytes }
    '{0:N1} {1}' -f $Bytes, $unidades[$i]
}

$script:CorStatusOperacao = @{ Feito = 'Green'; Simulado = 'Cyan'; Ignorado = 'Gray'; Parcial = 'Yellow'; Erro = 'Red' }

# Resultado de Invoke-Acao: uma linha por alvo e o total liberado.
function Write-TmdResultados {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][AllowEmptyCollection()][object[]]$Resultados,
        [switch]$Simulado,
        # 'liberar' (limpeza: mostra espaço) ou 'desfazer'/'ajustar' (mostra as mudanças).
        [string]$Acao = 'liberar'
    )

    Write-Host $(if ($Simulado) { 'Simulação (nada foi alterado)' } else { 'Resultado' }) -ForegroundColor DarkYellow
    $total = [int64]0
    $largura = [Math]::Max(18, (@($Resultados | ForEach-Object { ([string]$_.Id).Length }) + 0 | Measure-Object -Maximum).Maximum + 2)
    foreach ($r in $Resultados) {
        $total += [int64]$r.Liberado
        $cor = if ($script:CorStatusOperacao.ContainsKey([string]$r.Status)) { $script:CorStatusOperacao[[string]$r.Status] } else { 'Gray' }
        Write-Host ("  {0,-$largura}" -f $r.Id) -NoNewline
        Write-Host ('{0,-10}' -f $r.Status) -NoNewline -ForegroundColor $cor
        if ($Acao -eq 'liberar') { Write-Host ('{0,10}' -f (Format-TmdTamanho $r.Liberado)) -NoNewline }
        if ($r.Motivo) { Write-Host "  $($r.Motivo)" -ForegroundColor DarkGray } else { Write-Host '' }
        foreach ($m in @(Get-Propriedade -Objeto $r -Nome 'Mudancas' | Where-Object { $_ })) { Write-Host "      $m" -ForegroundColor Gray }
    }
    Write-Host ''
    if ($Acao -ne 'liberar') {
        if ($Simulado) { Write-Host 'Para fazer de verdade, rode sem -Simular.' }
        return
    }
    if ($Simulado) { Write-Host "Liberaria $(Format-TmdTamanho $total). Para fazer de verdade, rode sem -Simular." }
    else { Write-Host "Liberado: $(Format-TmdTamanho $total). Veja os detalhes em: tamandua historico" -ForegroundColor Green }
}

function Write-TmdHistorico {
    [CmdletBinding()]
    param([Parameter(Mandatory)][AllowEmptyCollection()][object[]]$Operacoes)

    if ($Operacoes.Count -eq 0) {
        Write-Host 'Nenhuma operação registrada ainda.'
        return
    }
    foreach ($o in $Operacoes) {
        $data = try { ([datetime]$o.Data).ToString('dd/MM HH:mm') } catch { '?' }
        $cor = if ($script:CorStatusOperacao.ContainsKey([string]$o.Status)) { $script:CorStatusOperacao[[string]$o.Status] } else { 'Gray' }
        $tamanho = if ($o.Liberado -gt 0) { Format-TmdTamanho $o.Liberado } else { '' }
        Write-Host ("{0}  " -f $data) -NoNewline -ForegroundColor DarkGray
        Write-Host ('{0,-9}' -f $o.Status) -NoNewline -ForegroundColor $cor
        Write-Host ('{0,-13}{1,10}  ' -f $o.Modulo, $tamanho) -NoNewline
        $acao = [string](Get-Propriedade -Objeto $o -Nome 'Acao')
        if ($acao -in 'ajustar', 'desfazer') { Write-Host "$acao $($o.Id): $($o.Caminho)" -NoNewline } else { Write-Host $o.Caminho -NoNewline }
        if ((Get-Propriedade -Objeto $o -Nome 'Reversivel') -eq $true) { Write-Host "   (tamandua desfazer $($o.Id))" -ForegroundColor DarkYellow } else { Write-Host '' }
        if ($o.Motivo) { Write-Host "                   $($o.Motivo)" -ForegroundColor DarkGray }
    }
}

function Write-TmdEstadoModulo {
    param([Parameter(Mandatory)]$Modulo)

    Write-Host "O módulo '$($Modulo.Nome)' está $($script:RotuloEstado[$Modulo.Estado]): $($Modulo.Motivo)" `
        -ForegroundColor $script:CorEstado[$Modulo.Estado]
    Write-Host "Veja o estado de todos com: tamandua modulos"
}

function Write-TmdAjuda {
    Write-Host "Tamanduá $script:Versao - limpeza, ajustes e manutenção para Windows"
    Write-Host ''
    Write-Host 'Uso: tamandua [comando]'
    Write-Host ''
    Write-Host '  (sem comando)   abre a interface (ou o menu de texto, se ela faltar)'
    Write-Host '  menu            menu de texto'
    Write-Host '  modulos         estado de cada módulo'
    Write-Host '  <módulo>        executa um módulo (veja a lista em: tamandua modulos)'
    Write-Host '    <pasta>       em módulos que navegam (ex.: tamandua analisar C:\Users)'
    Write-Host '    -Simular      mostra o que seria feito, sem alterar nada'
    Write-Host '    -Sim          confirma sem perguntar (para scripts)'
    Write-Host '    -Preset X     marca os itens do preset X (ex.: tamandua ajustes -Preset Essencial)'
    Write-Host '    -Itens a,b    marca exatamente estes itens, pelo id'
    Write-Host '  historico       o que o Tamanduá já removeu, ajustou, simulou ou pulou'
    Write-Host '  desfazer <id>   volta um ajuste ao valor que estava antes (-Simular para ver antes)'
    Write-Host '  protegidos      abre a sua lista de proteção (caminhos que nunca são apagados)'
    Write-Host '  ajuda           esta ajuda'
    Write-Host '  versao          versão'
}
