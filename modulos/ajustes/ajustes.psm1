# Ajustes do Windows. O módulo quase não tem código: lê ajustes.json e entrega cada ajuste ao motor do núcleo
# (Set-TmdAjuste / Get-TmdEstadoAjuste), que lê, guarda o valor de antes, escreve e confere.
# Entradas com "acao": true são ações únicas (ponto de restauração, Limpeza de Disco...): Invoke-TmdAcaoAjuste, sem desfazer.

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

function Get-CampoTexto {
    param($Objeto, [string]$Nome)
    $p = $Objeto.PSObject.Properties[$Nome]
    if ($p -and $p.Value) { [string]$p.Value } else { '' }
}

function Test-EhAcao {
    param($Ajuste)
    $p = $Ajuste.PSObject.Properties['acao']
    $p -and $p.Value -eq $true
}

# Na área de testes (registro redirecionado) só entram ajustes que são só registro e não pedem admin: serviço, script e
# ação mexeriam no sistema de verdade, e o que pede admin chamaria o UAC (os testes do motor cobrem esses).
function Get-AjusteDisponivel {
    param([string]$Catalogo, [string]$RaizRegistro)
    foreach ($a in Get-CatalogoAjustes -Arquivo $Catalogo) {
        if ($RaizRegistro -and ((Test-EhAcao $a) -or $a.requerAdmin -or @($a.mudancas | Where-Object { $_.tipo -ne 'Registro' }).Count -gt 0)) { continue }
        $a
    }
}

# Um alvo por ajuste, com o estado lido da máquina agora. Nada vem marcado: quem escolhe é você (ou um preset).
# A ordem do catálogo é a ordem da página e a dos botões de preset (eles aparecem na ordem em que surgem).
function Find-Alvos {
    param([string]$Catalogo = $script:ArquivoCatalogo, [string]$RaizRegistro = (Get-RaizRegistroPadrao))

    foreach ($a in Get-AjusteDisponivel -Catalogo $Catalogo -RaizRegistro $RaizRegistro) {
        $acao = Test-EhAcao $a
        $estado = if ($acao) { 'NaoSeAplica' } else { Get-TmdEstadoAjuste -Ajuste $a -RaizRegistro $RaizRegistro }
        # Já aplicado (pelo Tamanduá ou por outra ferramenta): marcar desfaz. Preset nunca marca estes.
        $desfaz = $estado -eq 'Aplicado'
        [pscustomobject]@{
            Id          = $a.id
            Nome        = $a.nome
            Categoria   = $a.categoria
            Caminho     = ''
            Tamanho     = [int64]0
            Estado      = $estado
            Desfaz      = $desfaz
            Selo        = if ($desfaz) { 'aplicado · marcar desfaz' } else { '' }
            Detalhe     = $a.descricao
            Nivel       = 'Normal'
            Valor       = $null
            Risco       = $a.risco
            # Recomendado, Opcional, Atencao ou Arriscado; e, quando pode dar problema, o quê e como resolver.
            Classificacao = Get-CampoTexto $a 'classificacao'
            Contratempo = Get-CampoTexto $a 'contratempo'
            SeAcontecer = Get-CampoTexto $a 'seAcontecer'
            Selecionado = $false
            Destino     = 'NaoSeAplica'
            RequerAdmin = [bool]$a.requerAdmin
            Reversivel  = -not $acao
            Presets     = @($a.presets)
            # @( ) por fora: "if (...) { @(...) }" desmonta a lista e uma mudança só viraria texto solto.
            Mudancas    = @(
                if ($acao) { "Faz uma vez (não tem desfazer): $($a.descricao)" }
                else {
                    if ($desfaz) { Get-TmdTextoDesfaz -Id $a.id }
                    $a.mudancas | ForEach-Object { Format-MudancaCatalogo -Mudanca $_ }
                })
        }
    }
}

# Aplica pela definição do catálogo, achada pelo Id. O alvo recebido só diz QUAL ajuste; o que mudar vem daqui.
# Ações marcadas com "primeiro" (o ponto de restauração) vão antes de tudo, venham em que posição vierem.
function Invoke-Acao {
    param(
        [Parameter(Mandatory)][AllowEmptyCollection()][object[]]$Alvos,
        [switch]$Simular,
        [string]$Catalogo = $script:ArquivoCatalogo,
        [string]$RaizRegistro = (Get-RaizRegistroPadrao)
    )

    $definicoes = @{}
    foreach ($a in Get-AjusteDisponivel -Catalogo $Catalogo -RaizRegistro $RaizRegistro) { $definicoes[$a.id] = $a }
    $primeiro = {
        $d = $definicoes[[string]$_.Id]
        $d -and $d.PSObject.Properties['primeiro'] -and $d.primeiro -eq $true
    }
    $ordenados = @($Alvos | Where-Object $primeiro) + @($Alvos | Where-Object { -not (& $primeiro) })
    foreach ($alvo in $ordenados) {
        $id = [string]$alvo.Id
        if (-not $definicoes.ContainsKey($id)) {
            [pscustomobject]@{ Id = $id; Status = 'Erro'; Liberado = [int64]0; Motivo = 'ajuste desconhecido'; Mudancas = @() }
            continue
        }
        $d = $definicoes[$id]
        if (Test-EhAcao $d) { Invoke-TmdAcaoAjuste -Ajuste $d -Simular:$Simular -Modulo 'ajustes'; continue }
        if ($alvo.PSObject.Properties['Desfaz'] -and $alvo.Desfaz -eq $true) { Undo-TmdAjuste -Id $id -Ajuste $d -Simular:$Simular -RaizRegistro $RaizRegistro -Modulo 'ajustes'; continue }
        Set-TmdAjuste -Ajuste $d -Simular:$Simular -RaizRegistro $RaizRegistro -Modulo 'ajustes'
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
