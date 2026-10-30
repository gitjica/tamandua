# Programas pelo winget: mostra o catálogo com o que já está instalado e o que tem atualização; instala ou atualiza os escolhidos.
# Só IDs exatos do catálogo (programas.json), sempre da fonte "winget". Todo acesso ao winget passa por Invoke-Winget (Mock nos testes).

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$script:ArquivoCatalogo = Join-Path $PSScriptRoot 'programas.json'
# Códigos de saída do winget que não são erro para nós.
$script:SemAtualizacao = -1978335189   # 0x8A15002B: nenhuma atualização aplicável
$script:JaInstalado = -1978335135      # 0x8A150061: pacote já instalado

function Test-Requisitos {
    if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
        return @{ Ok = $false; Motivo = 'winget não encontrado. Instale o "Instalador de Aplicativo" (App Installer) pela Microsoft Store.' }
    }
    @{ Ok = $true; Motivo = '' }
}

function Get-CatalogoProgramas {
    param([string]$Arquivo = $script:ArquivoCatalogo)
    foreach ($p in ([IO.File]::ReadAllText($Arquivo, [Text.Encoding]::UTF8) | ConvertFrom-Json)) { $p }
}

# Único ponto que chama o winget. Devolve código de saída e linhas de saída.
function Invoke-Winget {
    param([Parameter(Mandatory)][string[]]$Argumentos)
    # No 5.1, stderr de programa externo com ErrorActionPreference = Stop vira exceção; aqui só interessam saída e código.
    $ErrorActionPreference = 'Continue'
    $saida = @(& winget @Argumentos 2>$null)
    [pscustomobject]@{ Codigo = $LASTEXITCODE; Saida = $saida }
}

# IDs instalados que a fonte winget conhece (pelo "winget export", que dá JSON em vez de tabela).
function Get-WingetInstalado {
    $arquivo = New-TmdArquivoTemporario -Extensao '.json'
    try {
        $r = Invoke-Winget -Argumentos @('export', '-o', $arquivo, '--source', 'winget', '--disable-interactivity')
        if (-not (Test-Path -LiteralPath $arquivo)) { throw "winget export falhou (código $($r.Codigo))" }
        $json = [IO.File]::ReadAllText($arquivo, [Text.Encoding]::UTF8) | ConvertFrom-Json
        $ids = @{}
        foreach ($fonte in @($json.Sources)) { foreach ($p in @($fonte.Packages)) { $ids[[string]$p.PackageIdentifier] = $true } }
        $ids
    }
    finally {
        Remove-TmdArquivoTemporario -Caminho $arquivo
    }
}

# Id -> versão nova, pela tabela do "winget upgrade" (Nome, Id, Versão, Disponível).
# As colunas saem das posições das palavras do cabeçalho: um Id longo encosta na versão com um espaço só.
function Get-WingetAtualizacao {
    $r = Invoke-Winget -Argumentos @('upgrade', '--source', 'winget', '--disable-interactivity')
    $mapa = @{}
    $linhas = @($r.Saida | ForEach-Object { ([string]$_ -split "`r")[-1] })
    $traco = -1
    for ($i = 0; $i -lt $linhas.Count; $i++) { if ($linhas[$i] -match '^-{10,}') { $traco = $i; break } }
    if ($traco -lt 1) { return $mapa }
    $inicios = @([regex]::Matches($linhas[$traco - 1], '\S+') | ForEach-Object { $_.Index })
    if ($inicios.Count -lt 4) { return $mapa }
    for ($i = $traco + 1; $i -lt $linhas.Count; $i++) {
        $l = $linhas[$i]
        if (-not $l.Trim() -or $l -match '^\d+ ' -or $l.Length -le $inicios[3]) { continue }
        $id = $l.Substring($inicios[1], $inicios[2] - $inicios[1]).Trim()
        $fim = if ($inicios.Count -gt 4) { [Math]::Min($l.Length, $inicios[4]) } else { $l.Length }
        $nova = $l.Substring($inicios[3], $fim - $inicios[3]).Trim()
        if ($id -and $nova) { $mapa[$id] = $nova }
    }
    $mapa
}

function Find-Alvos {
    param([string]$Catalogo = $script:ArquivoCatalogo)

    $instalados = Get-WingetInstalado
    $atualizacoes = Get-WingetAtualizacao
    $icones = Get-TmdIconesInstalados
    foreach ($p in Get-CatalogoProgramas -Arquivo $Catalogo) {
        $instalado = $instalados.ContainsKey($p.wingetId)
        $nova = if ($atualizacoes.ContainsKey($p.wingetId)) { $atualizacoes[$p.wingetId] } else { $null }
        $estado = if (-not $instalado) { 'NaoAplicado' } elseif ($nova) { 'Parcial' } else { 'Aplicado' }
        $selo = if (-not $instalado) { 'não instalado' } elseif ($nova) { "atualizar para $nova" } else { 'instalado' }
        $acao = if (-not $instalado) { 'install' } elseif ($nova) { 'upgrade' } else { $null }
        $livre = if ($p.livre) { ' Software livre.' } else { '' }
        New-AlvoPrograma -Id $p.id -Nome $p.nome -Categoria $p.categoria -Estado $estado -Selo $selo -Icone (Find-IconePrograma -Icones $icones -Nome $p.nome -Instalado $instalado) `
            -Detalhe "$($p.descricao)$livre" -Mudancas @(
            $(if ($acao) { "winget $acao --id $($p.wingetId) --exact --source winget" } else { 'Já instalado e atualizado: nada a fazer.' })
        )
    }
    $outras = @($atualizacoes.Keys | Sort-Object)
    if ($outras.Count -gt 0) {
        New-AlvoPrograma -Id 'atualizar-tudo' -Nome "Atualizar tudo ($($outras.Count))" -Categoria 'Atualizações' -Estado 'Parcial' `
            -Selo "$($outras.Count) com atualização" -Detalhe ($outras -join ', ') -Mudancas @('winget upgrade --all --source winget')
    }
}

# Onde achar o ícone do programa instalado com esse nome ("7-Zip" acha "7-Zip 24.08 (x64)"); sem registro com esse
# nome, o atalho do menu Iniciar. Não instalado: sem ícone (não há arquivo dele no disco; a tela mostra a inicial).
function Find-IconePrograma {
    param([hashtable]$Icones, [string]$Nome, [bool]$Instalado)
    if (-not $Instalado) { return , @() }
    $simples = ConvertTo-TmdNomeSimples $Nome
    if (-not $simples) { return , @() }
    if ($Icones) { foreach ($k in $Icones.Keys) { if ($k.StartsWith($simples)) { return , @($Icones[$k]) } } }
    , @(Get-TmdCandidatosIcone -Nome $Nome)
}

function New-AlvoPrograma {
    param([string]$Id, [string]$Nome, [string]$Categoria, [string]$Estado, [string]$Selo, [string]$Detalhe, [string[]]$Mudancas, [string[]]$Icone = @())
    [pscustomobject]@{
        Id = $Id; Nome = $Nome; Categoria = $Categoria; Caminho = ''; Tamanho = [int64]0; Estado = $Estado; Selo = $Selo
        Detalhe = $Detalhe; Nivel = 'Normal'; Valor = $null; Risco = 'Baixo'; Selecionado = $false; Destino = 'NaoSeAplica'
        RequerAdmin = $false; Reversivel = $null; Mudancas = $Mudancas; Icone = $Icone
    }
}

# Instala o que não está instalado, atualiza o que tem atualização. O que fazer sai do catálogo e do estado lido agora.
function Invoke-Acao {
    param(
        [Parameter(Mandatory)][AllowEmptyCollection()][object[]]$Alvos,
        [switch]$Simular,
        [string]$Catalogo = $script:ArquivoCatalogo
    )

    # Nome diferente do parâmetro: variáveis do PowerShell não diferenciam maiúsculas ($porId x $Catalogo).
    $porId = @{}
    foreach ($p in Get-CatalogoProgramas -Arquivo $Catalogo) { $porId[$p.id] = $p }
    $instalados = Get-WingetInstalado
    $atualizacoes = Get-WingetAtualizacao
    $comuns = @('--source', 'winget', '--silent', '--disable-interactivity', '--accept-package-agreements', '--accept-source-agreements')

    foreach ($a in $Alvos) {
        $id = [string]$a.Id
        if ($id -eq 'atualizar-tudo') {
            $argumentos = @('upgrade', '--all') + $comuns
            $nome = 'Atualizar tudo'
        }
        elseif ($porId.ContainsKey($id)) {
            $p = $porId[$id]
            $nome = $p.nome
            if (-not $instalados.ContainsKey($p.wingetId)) { $argumentos = @('install', '--id', $p.wingetId, '--exact') + $comuns }
            elseif ($atualizacoes.ContainsKey($p.wingetId)) { $argumentos = @('upgrade', '--id', $p.wingetId, '--exact') + $comuns }
            else {
                New-ResultadoPrograma -Id $id -Nome $nome -Status 'Feito' -Motivo 'já instalado e atualizado' -Simular $Simular
                continue
            }
        }
        else {
            New-ResultadoPrograma -Id $id -Nome $id -Status 'Erro' -Motivo 'programa fora do catálogo' -Simular $Simular
            continue
        }

        $comando = "winget $($argumentos -join ' ')"
        if ($Simular) {
            New-ResultadoPrograma -Id $id -Nome $nome -Status 'Simulado' -Mudancas @($comando) -Simular $true
            continue
        }
        $r = Invoke-Winget -Argumentos $argumentos
        switch ($r.Codigo) {
            0 { New-ResultadoPrograma -Id $id -Nome $nome -Status 'Feito' -Mudancas @($comando) -Simular $false }
            $script:SemAtualizacao { New-ResultadoPrograma -Id $id -Nome $nome -Status 'Feito' -Motivo 'já estava atualizado' -Simular $false }
            $script:JaInstalado { New-ResultadoPrograma -Id $id -Nome $nome -Status 'Feito' -Motivo 'já estava instalado' -Simular $false }
            default {
                $ultima = @($r.Saida | Where-Object { "$_".Trim() } | Select-Object -Last 1)
                $texto = "winget terminou com código $($r.Codigo)"
                if ($ultima.Count -gt 0) { $texto += ": $($ultima[0])" }
                New-ResultadoPrograma -Id $id -Nome $nome -Status 'Erro' -Motivo $texto -Mudancas @($comando) -Simular $false
            }
        }
    }
}

# Resultado + uma linha no log de operações do núcleo.
function New-ResultadoPrograma {
    param([string]$Id, [string]$Nome, [string]$Status, [string]$Motivo = '', [string[]]$Mudancas = @(), [bool]$Simular)
    Write-TmdOperacao -Modulo 'programas' -Id $Id -Acao 'instalar' -Caminho $Nome -Status $Status -Motivo $Motivo -Simulado $Simular
    [pscustomobject]@{ Id = $Id; Status = $Status; Liberado = [int64]0; Motivo = $Motivo; Mudancas = $Mudancas }
}

Export-ModuleMember -Function Test-Requisitos, Find-Alvos, Invoke-Acao
