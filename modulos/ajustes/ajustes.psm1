# Ajustes do Windows. O módulo quase não tem código: lê ajustes.json e entrega cada ajuste ao motor do núcleo
# (Set-TmdAjuste / Get-TmdEstadoAjuste), que lê, guarda o valor de antes, escreve e confere.

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$script:ArquivoCatalogo = Join-Path $PSScriptRoot 'ajustes.json'

# Testes: TAMANDUA_REGISTRO_TESTE redireciona o registro para uma chave de teste (só vale em HKCU:\Software\TamanduaTestes).
function Get-RaizRegistroPadrao {
    $r = $env:TAMANDUA_REGISTRO_TESTE
    if ($r -and $r -like 'HKCU:\Software\TamanduaTestes\*') { return $r }
    ''
}

function Test-Requisitos {
    try {
        $n = @(Get-CatalogoAjustes).Count
        if ($n -eq 0) { return @{ Ok = $false; Motivo = 'ajustes.json está vazio' } }
        @{ Ok = $true; Motivo = '' }
    }
    catch {
        @{ Ok = $false; Motivo = "não foi possível ler ajustes.json: $($_.Exception.Message)" }
    }
}

function Get-CatalogoAjustes {
    param([string]$Arquivo = $script:ArquivoCatalogo)
    # No 5.1, ConvertFrom-Json de uma lista devolve a lista inteira como UM objeto; o foreach a desmonta.
    foreach ($a in ([IO.File]::ReadAllText($Arquivo, [Text.Encoding]::UTF8) | ConvertFrom-Json)) { $a }
}

# Na área de testes (registro redirecionado) só entram ajustes que são só registro e não pedem admin: serviço e
# script mexeriam no sistema de verdade, e o que pede admin chamaria o UAC (os testes do motor cobrem esses).
function Get-AjusteDisponivel {
    param([string]$Catalogo, [string]$RaizRegistro)
    foreach ($a in Get-CatalogoAjustes -Arquivo $Catalogo) {
        if ($RaizRegistro -and ($a.requerAdmin -or @($a.mudancas | Where-Object { $_.tipo -ne 'Registro' }).Count -gt 0)) { continue }
        $a
    }
}

# Primeiro item da página: não é um ajuste (não tem estado nem desfazer), é a rede de segurança antes deles.
$script:IdPontoRestauracao = 'seg-ponto-restauracao'
# Ordem também é a ordem dos botões de preset na janela (vêm na ordem em que aparecem).
$script:PresetsPontoRestauracao = @('Mínimo', 'Essencial', 'Avançado', 'Notebook', 'Desempenho')

# Um alvo por ajuste, com o estado lido da máquina agora. Nada vem marcado: quem escolhe é você (ou um preset).
function Find-Alvos {
    param([string]$Catalogo = $script:ArquivoCatalogo, [string]$RaizRegistro = (Get-RaizRegistroPadrao))

    if (-not $RaizRegistro) {
        [pscustomobject]@{
            Id = $script:IdPontoRestauracao; Nome = 'Criar ponto de restauração antes'; Categoria = 'Segurança'; Caminho = ''
            Tamanho = [int64]0; Estado = 'NaoSeAplica'; Nivel = 'Normal'; Valor = $null; Risco = 'Baixo'
            Detalhe = 'Um ponto de restauração do Windows antes dos outros ajustes marcados: se algo der errado, dá para voltar o sistema inteiro.'
            Selecionado = $false; Destino = 'NaoSeAplica'; RequerAdmin = $true; Reversivel = $false; Presets = $script:PresetsPontoRestauracao
            Mudancas = @('Liga a Proteção do Sistema no disco do Windows, se estiver desligada.', 'Cria o ponto (Checkpoint-Computer); leva de alguns segundos a alguns minutos.')
        }
    }
    foreach ($a in Get-AjusteDisponivel -Catalogo $Catalogo -RaizRegistro $RaizRegistro) {
        [pscustomobject]@{
            Id          = $a.id
            Nome        = $a.nome
            Categoria   = $a.categoria
            Caminho     = ''
            Tamanho     = [int64]0
            Estado      = Get-TmdEstadoAjuste -Ajuste $a -RaizRegistro $RaizRegistro
            Detalhe     = $a.descricao
            Nivel       = 'Normal'
            Valor       = $null
            Risco       = $a.risco
            Selecionado = $false
            Destino     = 'NaoSeAplica'
            RequerAdmin = [bool]$a.requerAdmin
            Reversivel  = $true
            Presets     = @($a.presets)
            Mudancas    = @($a.mudancas | ForEach-Object { Format-MudancaCatalogo -Mudanca $_ })
        }
    }
}

# Aplica pela definição do catálogo, achada pelo Id. O alvo recebido só diz QUAL ajuste; o que mudar vem daqui.
function Invoke-Acao {
    param(
        [Parameter(Mandatory)][AllowEmptyCollection()][object[]]$Alvos,
        [switch]$Simular,
        [string]$Catalogo = $script:ArquivoCatalogo,
        [string]$RaizRegistro = (Get-RaizRegistroPadrao)
    )

    $definicoes = @{}
    foreach ($a in Get-AjusteDisponivel -Catalogo $Catalogo -RaizRegistro $RaizRegistro) { $definicoes[$a.id] = $a }
    # O ponto de restauração vai antes de qualquer ajuste, venha em que posição vier.
    $ordenados = @($Alvos | Where-Object { [string]$_.Id -eq $script:IdPontoRestauracao }) + @($Alvos | Where-Object { [string]$_.Id -ne $script:IdPontoRestauracao })
    foreach ($alvo in $ordenados) {
        $id = [string]$alvo.Id
        if ($id -eq $script:IdPontoRestauracao -and -not $RaizRegistro) {
            New-TmdPontoRestauracao -Id $id -Simular:$Simular -Modulo 'ajustes'
            continue
        }
        if (-not $definicoes.ContainsKey($id)) {
            [pscustomobject]@{ Id = $id; Status = 'Erro'; Liberado = [int64]0; Motivo = 'ajuste desconhecido'; Mudancas = @() }
            continue
        }
        Set-TmdAjuste -Ajuste $definicoes[$id] -Simular:$Simular -RaizRegistro $RaizRegistro -Modulo 'ajustes'
    }
}

function Format-MudancaCatalogo {
    param([Parameter(Mandatory)]$Mudanca)
    $p = $Mudanca.PSObject.Properties['padraoWindows']
    $padrao = if (-not $p -or $null -eq $p.Value) { 'não existe' } else { [string]$p.Value }
    switch ($Mudanca.tipo) {
        'Registro' { return "$($Mudanca.caminho)\$($Mudanca.nome) = $($Mudanca.valor) (padrão do Windows: $padrao)" }
        'Servico' { return "serviço $($Mudanca.nome): $($Mudanca.inicializacao) (padrão do Windows: $padrao)" }
        'Tarefa' { return "tarefa $($Mudanca.caminho)$($Mudanca.nome): $(if ($Mudanca.habilitada) { 'ativada' } else { 'desativada' })" }
        default { return "script: $($Mudanca.aplicar)" }
    }
}

Export-ModuleMember -Function Test-Requisitos, Find-Alvos, Invoke-Acao
