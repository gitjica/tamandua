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
        Write-Host ("  {0,-$largura}" -f $nome) -NoNewline
        $i++
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
    Write-Host '  ajuda           esta ajuda'
    Write-Host '  versao          versão'
}
