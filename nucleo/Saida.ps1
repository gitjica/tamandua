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
