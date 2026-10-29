# Interpreta a linha de comando e devolve o código de saída.
# Toda saída para o usuário vai para o host; o pipeline carrega só o código.

$script:CodigoSaida = @{ Ok = 0; Erro = 1; Indisponivel = 2; Cancelado = 3 }

function Invoke-TmdCli {
    [CmdletBinding()]
    param(
        [string]$Comando,
        [string[]]$Argumentos,
        [string]$Raiz = $script:RaizPadrao,
        [switch]$Simular,
        [switch]$Sim
    )

    if ($Comando -eq 'desfazer') { return Invoke-TmdDesfazer -Argumentos $Argumentos -Simular:$Simular -Sim:$Sim }
    if ($Argumentos) {
        Write-Host "Opções ainda não suportadas: $($Argumentos -join ' ')" -ForegroundColor Yellow
        return $script:CodigoSaida.Erro
    }
    $comandosDoNucleo = 'modulos', 'menu', 'historico', 'protegidos', 'ajuda', 'versao'
    if (($Simular -or $Sim) -and ([string]::IsNullOrWhiteSpace($Comando) -or $Comando -in $comandosDoNucleo)) {
        Write-Host '-Simular e -Sim só valem junto com um módulo (ex.: tamandua limpar -Simular).' -ForegroundColor Yellow
        return $script:CodigoSaida.Erro
    }
    if ([string]::IsNullOrWhiteSpace($Comando)) { return Start-TmdPrincipal -Raiz $Raiz }

    switch ($Comando.ToLowerInvariant()) {
        'modulos' {
            Write-TmdModulos -Modulos @(Get-TmdModulo -Raiz $Raiz)
            return $script:CodigoSaida.Ok
        }
        'menu' { return Start-TmdMenu -Raiz $Raiz }
        'historico' {
            Write-TmdHistorico -Operacoes @(Get-TmdHistorico -Ultimos 40)
            return $script:CodigoSaida.Ok
        }
        'protegidos' { return Open-TmdListaProtecao }
        'ajuda' {
            Write-TmdAjuda
            return $script:CodigoSaida.Ok
        }
        'versao' {
            Write-Host "Tamanduá $script:Versao"
            return $script:CodigoSaida.Ok
        }
        default { return Invoke-TmdComandoModulo -Nome $Comando -Raiz $Raiz -Simular:$Simular -Sim:$Sim }
    }
}

# tamandua desfazer <id-do-ajuste> [-Simular] [-Sim]: volta o ajuste para o valor salvo antes de ele ser aplicado.
function Invoke-TmdDesfazer {
    param([string[]]$Argumentos, [switch]$Simular, [switch]$Sim)

    if (@($Argumentos).Count -ne 1) {
        Write-Host 'Uso: tamandua desfazer <id-do-ajuste>   (os ids aparecem em: tamandua historico)' -ForegroundColor Yellow
        return $script:CodigoSaida.Erro
    }
    $id = $Argumentos[0]
    if (-not (Test-TmdAjusteReversivel -Id $id)) {
        Write-Host "Não há o que desfazer para '$id': nenhum estado salvo." -ForegroundColor Yellow
        return $script:CodigoSaida.Erro
    }
    if ($Simular) {
        Write-TmdResultados -Resultados @(Undo-TmdAjuste -Id $id -Simular -Modulo 'historico') -Simulado -Acao 'desfazer'
        return $script:CodigoSaida.Ok
    }
    if (-not (Confirm-TmdExecucao -Pergunta "Desfazer o ajuste '$id'?" -Sim:$Sim)) {
        Write-Host 'Cancelado. Nada foi alterado.'
        return $script:CodigoSaida.Cancelado
    }
    $r = Undo-TmdAjuste -Id $id -Modulo 'historico'
    Write-TmdResultados -Resultados @($r) -Acao 'desfazer'
    if ($r.Status -eq 'Feito') { return $script:CodigoSaida.Ok }
    $script:CodigoSaida.Erro
}

# Módulo de leitura: mostra os alvos. Módulo que escreve: mostra, simula ou confirma, executa e mostra o resultado.
function Invoke-TmdComandoModulo {
    param([Parameter(Mandatory)][string]$Nome, [Parameter(Mandatory)][string]$Raiz, [switch]$Simular, [switch]$Sim)

    $info = Get-TmdModulo -Raiz $Raiz -Nome $Nome
    if (-not $info) {
        Write-Host "Comando desconhecido: $Nome" -ForegroundColor Red
        Write-Host ''
        Write-TmdAjuda
        return $script:CodigoSaida.Erro
    }
    if ($info.Estado -ne 'ok') {
        Write-TmdEstadoModulo -Modulo $info
        return $script:CodigoSaida.Indisponivel
    }
    $escreve = [bool]$info.Manifesto['Escreve']
    if (-not $escreve -and ($Simular -or $Sim)) {
        Write-Host "O módulo '$Nome' só lê o sistema; -Simular e -Sim não se aplicam." -ForegroundColor Yellow
        return $script:CodigoSaida.Erro
    }
    try {
        $alvos = @(& $info.Modulo.ExportedFunctions['Find-Alvos'])
    }
    catch {
        Write-Host "O módulo '$Nome' falhou: $($_.Exception.Message)" -ForegroundColor Red
        return $script:CodigoSaida.Erro
    }
    Write-TmdAlvos -Alvos $alvos
    if (-not $escreve) { return $script:CodigoSaida.Ok }

    $selecionados = @($alvos | Where-Object { (Get-Propriedade -Objeto $_ -Nome 'Selecionado') -eq $true })
    Write-Host ''
    if ($selecionados.Count -eq 0) {
        Write-Host 'Nada selecionado para fazer.'
        return $script:CodigoSaida.Ok
    }
    $bytes = [int64]0
    foreach ($a in $selecionados) { $t = Get-Propriedade -Objeto $a -Nome 'Tamanho'; if ($t -gt 0) { $bytes += $t } }
    $rotulo = if ($info.Manifesto['RotuloAcao']) { [string]$info.Manifesto['RotuloAcao'] } else { 'Aplicar' }
    $acao = $info.Modulo.ExportedFunctions['Invoke-Acao']

    try {
        if ($Simular) {
            Write-TmdResultados -Resultados @(& $acao -Alvos $selecionados -Simular) -Simulado
            return $script:CodigoSaida.Ok
        }
        $pergunta = "$rotulo $($selecionados.Count) item(ns)" + $(if ($bytes -gt 0) { " ($(Format-TmdTamanho $bytes))" } else { '' }) + '?'
        if (-not (Confirm-TmdExecucao -Pergunta $pergunta -Sim:$Sim)) {
            Write-Host 'Cancelado. Nada foi alterado.'
            return $script:CodigoSaida.Cancelado
        }
        $resultados = @(& $acao -Alvos $selecionados)
    }
    catch {
        Write-Host "O módulo '$Nome' falhou: $($_.Exception.Message)" -ForegroundColor Red
        return $script:CodigoSaida.Erro
    }
    Write-TmdResultados -Resultados $resultados
    if (@($resultados | Where-Object { $_.Status -eq 'Erro' }).Count -gt 0) { return $script:CodigoSaida.Erro }
    $script:CodigoSaida.Ok
}

function Start-TmdPrincipal {
    param([Parameter(Mandatory)][string]$Raiz)

    $motivo = Start-InterfaceGrafica -Raiz $Raiz
    if ($null -eq $motivo) { return $script:CodigoSaida.Ok }
    Write-Host "Interface gráfica indisponível: $motivo." -ForegroundColor Yellow
    Write-Host 'Abrindo o menu de texto.'
    Start-TmdMenu -Raiz $Raiz
}

# Devolve $null se a interface abriu e foi fechada normalmente, ou o motivo de não ter aberto.
function Start-InterfaceGrafica {
    param([Parameter(Mandatory)][string]$Raiz)

    $arquivo = Join-Path $Raiz 'interface\Interface.psm1'
    if (-not (Test-Path -LiteralPath $arquivo -PathType Leaf)) { return 'pasta interface não encontrada' }
    try {
        $modulo = Import-Module -Name $arquivo -Force -PassThru -DisableNameChecking -ErrorAction Stop
        if (-not $modulo.ExportedFunctions.ContainsKey('Start-TmdInterface')) {
            return 'interface\Interface.psm1 não tem a função Start-TmdInterface'
        }
        & $modulo.ExportedFunctions['Start-TmdInterface'] -Raiz $Raiz | Out-Null
        return $null
    }
    catch {
        return "erro ao abrir: $($_.Exception.Message)"
    }
}

function Test-TmdInterativo {
    [Environment]::UserInteractive -and -not [Console]::IsInputRedirected
}

# Sem -Sim e sem console interativo, a resposta é sempre não: script nenhum apaga nada sem dizer -Sim.
function Confirm-TmdExecucao {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Pergunta, [switch]$Sim)

    if ($Sim) { return $true }
    if (-not (Test-TmdInterativo)) {
        Write-Host 'Sem console interativo: nada foi alterado. Em scripts, confirme com -Sim.' -ForegroundColor Yellow
        return $false
    }
    $resposta = Read-Host "$Pergunta [s/N]"
    $resposta -match '^\s*(s|sim)\s*$'
}

# Garante que a lista de proteção do usuário existe, mostra onde está e abre no Bloco de Notas se houver console.
function Open-TmdListaProtecao {
    $arquivo = Get-TmdArquivoProtecaoUsuario
    if (-not (Test-Path -LiteralPath $arquivo)) {
        [void][IO.Directory]::CreateDirectory((Split-Path -Parent $arquivo))
        $modelo = @(
            '# Sua lista de proteção: o Tamanduá nunca apaga caminhos que batem com estes padrões.'
            '# Um padrão por linha (* e ?), comparado com o caminho completo. Ex.:'
            '# %USERPROFILE%\Projetos\cliente-importante\*'
            '# *\node_modules\pacote-que-demora-pra-baixar*'
        )
        [IO.File]::WriteAllLines($arquivo, $modelo, (New-Object Text.UTF8Encoding $true))
    }
    Write-Host "Lista de proteção: $arquivo"
    if (Test-TmdInterativo) { Start-Process -FilePath 'notepad.exe' -ArgumentList "`"$arquivo`"" }
    $script:CodigoSaida.Ok
}

function Start-TmdMenu {
    param([Parameter(Mandatory)][string]$Raiz)

    $modulos = @(Get-TmdModulo -Raiz $Raiz)
    if (-not (Test-TmdInterativo)) {
        Write-TmdModulos -Modulos $modulos
        Write-Host 'Sem console interativo. Use: tamandua <comando>'
        return $script:CodigoSaida.Ok
    }

    while ($true) {
        Write-TmdModulos -Modulos $modulos
        $disponiveis = @($modulos | Where-Object { $_.Estado -eq 'ok' })
        if ($disponiveis.Count -eq 0) {
            Write-Host 'Nenhum módulo disponível ainda.'
            return $script:CodigoSaida.Ok
        }
        Write-Host ''
        for ($i = 0; $i -lt $disponiveis.Count; $i++) {
            Write-Host ("  [{0}] {1}" -f ($i + 1), $disponiveis[$i].Nome)
        }
        Write-Host '  [0] Sair'
        $escolha = Read-Host 'Escolha'
        if ($escolha -in '', '0') { return $script:CodigoSaida.Ok }
        $numero = 0
        if ([int]::TryParse($escolha, [ref]$numero) -and $numero -ge 1 -and $numero -le $disponiveis.Count) {
            [void](Invoke-TmdComandoModulo -Nome $disponiveis[$numero - 1].Nome -Raiz $Raiz)
        }
        else {
            Write-Host 'Opção inválida.' -ForegroundColor Yellow
        }
    }
}
