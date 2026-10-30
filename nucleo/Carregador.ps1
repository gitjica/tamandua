# Descobre os módulos e decide o estado de cada um: ok, faltando, quebrado ou indisponivel.
# Cada módulo é avaliado isolado: nada que um módulo faça impede a avaliação dos outros.

$script:CamposManifesto = [ordered]@{
    Nome           = [string]
    Versao         = [string]
    Descricao      = [string]
    Arquivo        = [string]
    Escreve        = [bool]
    RequerAdmin    = [bool]
    ContratoMinimo = [int]
}

# Roda em runspace separado: um Test-Requisitos que trava ou explode não afeta o processo principal.
$script:ScriptRequisitos = {
    param([string]$Arquivo)
    $ErrorActionPreference = 'Stop'
    $modulo = Import-Module -Name $Arquivo -Force -PassThru -DisableNameChecking
    & $modulo.ExportedFunctions['Test-Requisitos']
}

function Get-TmdCatalogo {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Raiz)

    $arquivo = Join-Path $Raiz 'nucleo\catalogo.psd1'
    try {
        # -ErrorAction explícito: no 5.1 o Import-PowerShellDataFile é uma função e ignora a preferência do chamador.
        $dados = Import-PowerShellDataFile -LiteralPath $arquivo -ErrorAction Stop
        $modulos = @($dados['Modulos'])
        foreach ($m in $modulos) {
            if (-not ($m -is [hashtable]) -or [string]::IsNullOrWhiteSpace($m['Nome'])) {
                throw 'toda entrada precisa ter Nome'
            }
        }
        [pscustomobject]@{ Modulos = $modulos; Erro = $null }
    }
    catch {
        [pscustomobject]@{ Modulos = @(); Erro = "catálogo inválido ($arquivo): $($_.Exception.Message)" }
    }
}

function Get-TmdModulo {
    [CmdletBinding()]
    param(
        [string]$Raiz = $script:RaizPadrao,
        [string]$Nome,
        [int]$TimeoutRequisitosSeg = 5,
        # Pula o Test-Requisitos: quem chama já sabe que o módulo está ok (a interface, ao abrir uma página).
        [switch]$SemRequisitos
    )

    $catalogo = Get-TmdCatalogo -Raiz $Raiz
    if ($catalogo.Erro) { Write-Warning $catalogo.Erro }

    $pastaModulos = Join-Path $Raiz 'modulos'
    $infos = [System.Collections.Generic.List[object]]::new()
    $conhecidos = @{}
    foreach ($c in $catalogo.Modulos) {
        $conhecidos[$c['Nome']] = $true
        $infos.Add((New-InfoModulo -Nome $c['Nome'] -Titulo $c['Titulo'] -Grupo $c['Grupo'] -Descricao $c['Descricao'] `
                    -Caminho (Join-Path $pastaModulos $c['Nome']) -NoCatalogo $true))
    }
    if (Test-Path -LiteralPath $pastaModulos -PathType Container) {
        foreach ($pasta in Get-ChildItem -LiteralPath $pastaModulos -Directory | Sort-Object Name) {
            if (-not $conhecidos.ContainsKey($pasta.Name)) {
                $infos.Add((New-InfoModulo -Nome $pasta.Name -Grupo 'Extras' -Descricao '' `
                            -Caminho $pasta.FullName -NoCatalogo $false))
            }
        }
    }

    $selecionados = @($infos | Where-Object { -not $Nome -or $_.Nome -eq $Nome })
    foreach ($info in $selecionados) { Resolve-EstadoModulo -Info $info }
    if (-not $SemRequisitos) {
        Test-RequisitosModulo -Infos @($selecionados | Where-Object { $_.Estado -eq 'ok' }) -TimeoutSeg $TimeoutRequisitosSeg
    }
    $selecionados
}

function New-InfoModulo {
    param([string]$Nome, [string]$Titulo, [string]$Grupo, [string]$Descricao, [string]$Caminho, [bool]$NoCatalogo)
    # Sem título no catálogo (módulo extra), usa o nome com inicial maiúscula.
    if (-not $Titulo) { $Titulo = $Nome.Substring(0, 1).ToUpper() + $Nome.Substring(1) }
    [pscustomobject]@{
        PSTypeName = 'Tamandua.InfoModulo'
        Nome       = $Nome
        Titulo     = $Titulo
        Grupo      = $Grupo
        Descricao  = $Descricao
        Caminho    = $Caminho
        NoCatalogo = $NoCatalogo
        Estado     = 'ok'
        Motivo     = ''
        Manifesto  = $null
        Modulo     = $null
    }
}

function Set-EstadoModulo {
    param([Parameter(Mandatory)]$Info, [Parameter(Mandatory)][string]$Estado, [string]$Motivo)
    $Info.Estado = $Estado
    $Info.Motivo = $Motivo
}

function Resolve-EstadoModulo {
    param([Parameter(Mandatory)]$Info)

    $relativo = "modulos\$($Info.Nome)"
    if (-not (Test-Path -LiteralPath $Info.Caminho -PathType Container)) {
        return Set-EstadoModulo $Info 'faltando' "pasta $relativo não encontrada"
    }
    $arquivoManifesto = Join-Path $Info.Caminho 'modulo.psd1'
    if (-not (Test-Path -LiteralPath $arquivoManifesto -PathType Leaf)) {
        return Set-EstadoModulo $Info 'faltando' "$relativo\modulo.psd1 não encontrado"
    }
    try {
        $manifesto = Import-PowerShellDataFile -LiteralPath $arquivoManifesto -ErrorAction Stop
    }
    catch {
        return Set-EstadoModulo $Info 'quebrado' "manifesto inválido: $($_.Exception.Message)"
    }
    $erro = Get-ErroManifesto -Manifesto $manifesto -NomePasta $Info.Nome
    if ($erro) { return Set-EstadoModulo $Info 'quebrado' "manifesto: $erro" }

    $Info.Manifesto = $manifesto
    if (-not $Info.NoCatalogo) { $Info.Descricao = $manifesto['Descricao'] }

    $arquivoCodigo = Join-Path $Info.Caminho $manifesto['Arquivo']
    if (-not (Test-Path -LiteralPath $arquivoCodigo -PathType Leaf)) {
        return Set-EstadoModulo $Info 'faltando' "$relativo\$($manifesto['Arquivo']) não encontrado"
    }
    # Reaproveita o módulo já importado neste runspace se nenhum arquivo da pasta mudou desde então
    # (a interface abre a mesma página várias vezes no mesmo runspace).
    $assinatura = Get-AssinaturaModulo -Pasta $Info.Caminho
    $guardado = $script:ModulosImportados[$arquivoCodigo]
    if ($guardado -and $guardado.Assinatura -eq $assinatura) {
        $Info.Modulo = $guardado.Modulo
        return
    }
    try {
        $modulo = Import-Module -Name $arquivoCodigo -Force -PassThru -DisableNameChecking -ErrorAction Stop
    }
    catch {
        [void]$script:ModulosImportados.Remove($arquivoCodigo)
        return Set-EstadoModulo $Info 'quebrado' "erro ao carregar: $($_.Exception.Message)"
    }
    $faltando = @(Get-FuncaoFaltando -Modulo $modulo -Escreve $manifesto['Escreve'])
    if ($faltando.Count -gt 0) {
        Remove-Module -ModuleInfo $modulo -Force
        [void]$script:ModulosImportados.Remove($arquivoCodigo)
        return Set-EstadoModulo $Info 'quebrado' "falta a função $($faltando -join ', ')"
    }
    $script:ModulosImportados[$arquivoCodigo] = @{ Modulo = $modulo; Assinatura = $assinatura }
    $Info.Modulo = $modulo
}

$script:ModulosImportados = @{}

# Nome, tamanho e data de cada arquivo da pasta do módulo (código, manifesto e dados .json).
function Get-AssinaturaModulo {
    param([Parameter(Mandatory)][string]$Pasta)
    $partes = foreach ($f in [IO.Directory]::GetFiles($Pasta)) {
        $i = [IO.FileInfo]::new($f)
        "$($i.Name)|$($i.Length)|$($i.LastWriteTimeUtc.Ticks)"
    }
    ($partes | Sort-Object) -join ';'
}

function Get-ErroManifesto {
    param([Parameter(Mandatory)][hashtable]$Manifesto, [Parameter(Mandatory)][string]$NomePasta)

    foreach ($campo in $script:CamposManifesto.Keys) {
        if (-not $Manifesto.ContainsKey($campo)) { return "falta o campo $campo" }
        $tipo = $script:CamposManifesto[$campo]
        if (-not ($Manifesto[$campo] -is $tipo)) { return "o campo $campo deveria ser $($tipo.Name)" }
    }
    if ($Manifesto['Nome'] -ne $NomePasta) {
        return "Nome '$($Manifesto['Nome'])' diferente da pasta '$NomePasta'"
    }
    if ($Manifesto['ContratoMinimo'] -gt $script:ContratoAtual) {
        return "exige o contrato $($Manifesto['ContratoMinimo']); este núcleo implementa o $script:ContratoAtual"
    }
    if ($Manifesto['Arquivo'] -notmatch '^[\w.-]+\.psm1$' -or $Manifesto['Arquivo'] -match '\.\.') {
        return 'Arquivo deve ser o nome de um .psm1 dentro da pasta do módulo'
    }
    $null
}

function Get-FuncaoFaltando {
    param([Parameter(Mandatory)][psmoduleinfo]$Modulo, [bool]$Escreve)

    $obrigatorias = @('Test-Requisitos', 'Find-Alvos')
    if ($Escreve) { $obrigatorias += 'Invoke-Acao' }
    $obrigatorias | Where-Object { -not $Modulo.ExportedFunctions.ContainsKey($_) }
}

function Test-RequisitosModulo {
    param([object[]]$Infos, [int]$TimeoutSeg)

    if (-not $Infos -or $Infos.Count -eq 0) { return }

    $pool = [runspacefactory]::CreateRunspacePool(1, [Math]::Min(8, $Infos.Count))
    $pool.Open()
    $tarefas = foreach ($info in $Infos) {
        $ps = [powershell]::Create()
        $ps.RunspacePool = $pool
        [void]$ps.AddScript($script:ScriptRequisitos).AddArgument($info.Modulo.Path)
        [pscustomobject]@{ Info = $info; PS = $ps; Async = $ps.BeginInvoke() }
    }

    $prazo = [DateTime]::UtcNow.AddSeconds($TimeoutSeg)
    $algumTravou = $false
    foreach ($t in $tarefas) {
        $restante = [int][Math]::Max(0, ($prazo - [DateTime]::UtcNow).TotalMilliseconds)
        if (-not $t.Async.AsyncWaitHandle.WaitOne($restante)) {
            Set-EstadoModulo $t.Info 'indisponivel' "Test-Requisitos não respondeu em $TimeoutSeg s"
            [void]$t.PS.BeginStop($null, $null)
            $algumTravou = $true
            continue
        }
        try {
            Set-ResultadoRequisitos -Info $t.Info -Saida $t.PS.EndInvoke($t.Async)
        }
        catch {
            $ex = $_.Exception
            while ($ex.InnerException) { $ex = $ex.InnerException }
            Set-EstadoModulo $t.Info 'indisponivel' "Test-Requisitos falhou: $($ex.Message)"
        }
        finally {
            $t.PS.Dispose()
        }
    }

    # Fechar o pool espera as tarefas travadas; nesse caso fecha em segundo plano.
    if ($algumTravou) { [void]$pool.BeginClose($null, $null) } else { $pool.Close(); $pool.Dispose() }
}

function Set-ResultadoRequisitos {
    param([Parameter(Mandatory)]$Info, $Saida)

    $itens = @($Saida)
    if ($itens.Count -ne 1) {
        return Set-EstadoModulo $Info 'quebrado' 'Test-Requisitos deve retornar um único objeto com Ok e Motivo'
    }
    $ok = Get-Propriedade -Objeto $itens[0] -Nome 'Ok'
    if (-not ($ok -is [bool])) {
        return Set-EstadoModulo $Info 'quebrado' 'Test-Requisitos deve retornar Ok = $true ou $false'
    }
    if (-not $ok) {
        $motivo = [string](Get-Propriedade -Objeto $itens[0] -Nome 'Motivo')
        if (-not $motivo) { $motivo = 'requisitos não atendidos' }
        Set-EstadoModulo $Info 'indisponivel' $motivo
    }
}

function Get-Propriedade {
    param($Objeto, [string]$Nome)

    if ($null -eq $Objeto) { return $null }
    if ($Objeto -is [System.Collections.IDictionary]) {
        if ($Objeto.Contains($Nome)) { return $Objeto[$Nome] }
        return $null
    }
    $propriedade = $Objeto.PSObject.Properties[$Nome]
    if ($propriedade) { return $propriedade.Value }
    $null
}
