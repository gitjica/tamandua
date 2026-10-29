# Interpreta a linha de comando e devolve o código de saída.
# Toda saída para o usuário vai para o host; o pipeline carrega só o código.

$script:CodigoSaida = @{ Ok = 0; Erro = 1; Indisponivel = 2; Cancelado = 3 }

function Invoke-TmdCli {
    [CmdletBinding()]
    param(
        [string]$Comando,
        [string[]]$Argumentos,
        [string]$Raiz = $script:RaizPadrao
    )

    if ($Argumentos) {
        Write-Host "Opções ainda não suportadas: $($Argumentos -join ' ')" -ForegroundColor Yellow
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
        default { return Invoke-TmdComandoModulo -Nome $Comando -Raiz $Raiz }
    }
}

function Invoke-TmdComandoModulo {
    param([Parameter(Mandatory)][string]$Nome, [Parameter(Mandatory)][string]$Raiz)

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
    try {
        $alvos = @(& $info.Modulo.ExportedFunctions['Find-Alvos'])
    }
    catch {
        Write-Host "O módulo '$Nome' falhou: $($_.Exception.Message)" -ForegroundColor Red
        return $script:CodigoSaida.Erro
    }
    Write-TmdAlvos -Alvos $alvos
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
