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
        [switch]$Sim,
        [string]$Preset,
        [string[]]$Itens
    )

    # Pelo "powershell -File", "-Itens a,b" chega como um texto só: separa pela vírgula.
    $Itens = @($Itens | Where-Object { $_ } | ForEach-Object { $_ -split ',' } | ForEach-Object { $_.Trim() } | Where-Object { $_ })
    if (($Preset -or $Itens) -and ([string]::IsNullOrWhiteSpace($Comando) -or $Comando -in 'modulos', 'menu', 'historico', 'protegidos', 'ajuda', 'versao', 'desfazer')) {
        Write-Host '-Preset e -Itens só valem junto com um módulo (ex.: tamandua ajustes -Preset Essencial).' -ForegroundColor Yellow
        return $script:CodigoSaida.Erro
    }
    if ($Comando -eq 'desfazer') { return Invoke-TmdDesfazer -Argumentos $Argumentos -Simular:$Simular -Sim:$Sim -Raiz $Raiz }
    # Comando interno: o processo elevado (pedido do UAC) executa as ações de um lote. Não aparece na ajuda.
    if ($Comando -eq '__elevado') {
        try {
            Invoke-TmdExecucaoElevada -Pedido $Argumentos[0] -Raiz $Raiz
            return $script:CodigoSaida.Ok
        }
        catch {
            [Console]::Error.WriteLine("Tamanduá (admin): $($_.Exception.Message)")
            return $script:CodigoSaida.Erro
        }
    }
    $comandosDoNucleo = 'modulos', 'menu', 'historico', 'protegidos', 'ajuda', 'versao'
    if ($Argumentos -and ([string]::IsNullOrWhiteSpace($Comando) -or $Comando -in $comandosDoNucleo)) {
        Write-Host "Opções ainda não suportadas: $($Argumentos -join ' ')" -ForegroundColor Yellow
        return $script:CodigoSaida.Erro
    }
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
        default { return Invoke-TmdComandoModulo -Nome $Comando -Raiz $Raiz -Simular:$Simular -Sim:$Sim -Preset $Preset -Itens $Itens -Argumentos $Argumentos }
    }
}

# tamandua desfazer <id-do-ajuste> [-Simular] [-Sim]: volta o ajuste para o valor salvo antes de ele ser aplicado.
function Invoke-TmdDesfazer {
    param([string[]]$Argumentos, [switch]$Simular, [switch]$Sim, [string]$Raiz = $script:RaizPadrao)

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
    # Ajuste que mexeu em HKLM, serviço ou tarefa: pede o UAC para voltar.
    $r = @(Undo-TmdAjusteComAdmin -Ids @($id) -Raiz $Raiz)[0]
    Write-TmdResultados -Resultados @($r) -Acao 'desfazer'
    if ($r.Status -eq 'Feito') { return $script:CodigoSaida.Ok }
    $script:CodigoSaida.Erro
}

# Módulo de leitura: mostra os alvos. Módulo que escreve: mostra, simula ou confirma, executa e mostra o resultado.
function Invoke-TmdComandoModulo {
    param(
        [Parameter(Mandatory)][string]$Nome, [Parameter(Mandatory)][string]$Raiz,
        [switch]$Simular, [switch]$Sim, [string]$Preset, [string[]]$Itens, [string[]]$Argumentos
    )

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
    if (-not $escreve -and ($Simular -or $Sim -or $Preset -or $Itens)) {
        Write-Host "O módulo '$Nome' só lê o sistema; -Simular, -Sim, -Preset e -Itens não se aplicam." -ForegroundColor Yellow
        return $script:CodigoSaida.Erro
    }
    # [string[]] nulo em StrictMode: @($Argumentos).Count lança no 5.1, então testa direto.
    if ($Argumentos) {
        Write-Host "O módulo '$Nome' não aceita: $($Argumentos -join ' ')" -ForegroundColor Yellow
        return $script:CodigoSaida.Erro
    }
    try {
        $alvos = @(& $info.Modulo.ExportedFunctions['Find-Alvos'])
    }
    catch {
        Write-Host "O módulo '$Nome' falhou: $($_.Exception.Message)" -ForegroundColor Red
        return $script:CodigoSaida.Erro
    }
    if ($Preset -or $Itens) {
        $erroSelecao = Set-TmdSelecaoCli -Alvos $alvos -Preset $Preset -Itens $Itens
        if ($erroSelecao) {
            Write-Host $erroSelecao -ForegroundColor Yellow
            return $script:CodigoSaida.Erro
        }
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
    $tipoResultado = if ($info.Manifesto['Resultado'] -eq 'Mudancas') { 'ajustar' } else { 'liberar' }
    $acao = $info.Modulo.ExportedFunctions['Invoke-Acao']

    try {
        if ($Simular) {
            Write-TmdResultados -Resultados @(& $acao -Alvos $selecionados -Simular) -Simulado -Acao $tipoResultado
            return $script:CodigoSaida.Ok
        }
        $pergunta = "$rotulo $($selecionados.Count) item(ns)" + $(if ($bytes -gt 0) { " ($(Format-TmdTamanho $bytes))" } else { '' }) + '?'
        if ($info.Manifesto['AvisoConfirmacao']) { Write-Host ([string]$info.Manifesto['AvisoConfirmacao']) -ForegroundColor Yellow }
        if (-not (Confirm-TmdExecucao -Pergunta $pergunta -Sim:$Sim)) {
            Write-Host 'Cancelado. Nada foi alterado.'
            return $script:CodigoSaida.Cancelado
        }
        # Módulo com RequerAdmin: o núcleo pede o UAC uma vez e roda o lote elevado.
        $resultados = @(Invoke-TmdAcaoModulo -Info $info -Alvos $selecionados -Raiz $Raiz)
    }
    catch {
        Write-Host "O módulo '$Nome' falhou: $($_.Exception.Message)" -ForegroundColor Red
        return $script:CodigoSaida.Erro
    }
    Write-TmdResultados -Resultados $resultados -Acao $tipoResultado
    $reversiveis = @($selecionados | Where-Object { (Get-Propriedade -Objeto $_ -Nome 'Reversivel') -eq $true }).Count
    if ($reversiveis -gt 0) { Write-Host 'Para voltar um ajuste: tamandua desfazer <id> (os ids estão em: tamandua historico).' }
    if (@($resultados | Where-Object { $_.Status -eq 'Erro' }).Count -gt 0) { return $script:CodigoSaida.Erro }
    $script:CodigoSaida.Ok
}

# -Preset marca os alvos cuja lista Presets tem o nome; -Itens marca exatamente os ids. Devolve a mensagem de erro, se houver.
function Set-TmdSelecaoCli {
    param([object[]]$Alvos, [string]$Preset, [string[]]$Itens)

    if ($Preset) {
        $conhecidos = @($Alvos | ForEach-Object { Get-Propriedade -Objeto $_ -Nome 'Presets' } | Where-Object { $_ } | Select-Object -Unique)
        if ($conhecidos -notcontains $Preset) {
            if ($conhecidos.Count -eq 0) { return 'Este módulo não tem presets.' }
            return "Preset desconhecido: $Preset. Disponíveis: $($conhecidos -join ', ')"
        }
    }
    if ($Itens) {
        $ids = @($Alvos | ForEach-Object { $_.Id })
        $faltando = @($Itens | Where-Object { $ids -notcontains $_ })
        if ($faltando.Count -gt 0) { return "Itens desconhecidos: $($faltando -join ', '). Veja os ids com: tamandua <módulo> -Simular" }
    }
    foreach ($a in $Alvos) {
        $marcar = $false
        if ($Preset -and @(Get-Propriedade -Objeto $a -Nome 'Presets') -contains $Preset) { $marcar = $true }
        if ($Itens -and $Itens -contains $a.Id) { $marcar = $true }
        if ($a.PSObject.Properties['Selecionado']) { $a.Selecionado = $marcar }
    }
    $null
}

function Start-TmdPrincipal {
    param([Parameter(Mandatory)][string]$Raiz)

    # Abriu outra cópia como administrador: esta termina aqui.
    if (Request-TmdAdminAoAbrir -Script (Join-Path $Raiz 'tamandua.ps1')) { return $script:CodigoSaida.Ok }
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
