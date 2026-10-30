# Permissão de administrador (seção 7.6 do guia): o programa roda sem admin e, quando um módulo com RequerAdmin = $true
# vai executar, as ações vão num ÚNICO processo elevado (um só pedido do UAC por lote), que roda o mesmo núcleo
# e devolve os resultados por um arquivo temporário.

function Test-TmdAdministrador {
    [CmdletBinding()]
    param()
    $identidade = [Security.Principal.WindowsIdentity]::GetCurrent()
    (New-Object Security.Principal.WindowsPrincipal($identidade)).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

# Executa Invoke-Acao do módulo. Se o manifesto tem RequerAdmin e este processo não é admin, só os alvos com
# RequerAdmin = $true vão para o processo elevado; os outros rodam aqui (ex.: reiniciar o Explorer não deve virar admin).
# Os resultados voltam na ordem dos alvos.
function Invoke-TmdAcaoModulo {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Info,
        [Parameter(Mandatory)][AllowEmptyCollection()][object[]]$Alvos,
        [switch]$Simular,
        [string]$Raiz = $script:RaizPadrao
    )
    $acao = $Info.Modulo.ExportedFunctions['Invoke-Acao']
    # Simular não muda nada e é rápido: roda aqui mesmo, de uma vez, sem pedir admin.
    if ($Simular) { return @(& $acao -Alvos $Alvos -Simular) }
    if (-not $Info.Manifesto['RequerAdmin'] -or (Test-TmdAdministrador)) {
        return @(Invoke-TmdAcaoPorItem -Acao $acao -Alvos $Alvos)
    }
    $elevar = @($Alvos | Where-Object { (Get-Propriedade -Objeto $_ -Nome 'RequerAdmin') -eq $true })
    $aqui = @($Alvos | Where-Object { (Get-Propriedade -Objeto $_ -Nome 'RequerAdmin') -ne $true })
    $porId = @{}
    if ($aqui.Count -gt 0) { foreach ($r in @(Invoke-TmdAcaoPorItem -Acao $acao -Alvos $aqui)) { $porId[[string]$r.Id] = $r } }
    if ($elevar.Count -gt 0) { foreach ($r in @(Invoke-TmdAcaoElevada -Raiz $Raiz -Modulo $Info.Nome -Alvos $elevar)) { $porId[[string]$r.Id] = $r } }
    foreach ($a in $Alvos) { if ($porId.ContainsKey([string]$a.Id)) { $porId[[string]$a.Id] } }
}

# Um alvo por vez, avisando o progresso antes de cada um ("2 de 5: Temporários do usuário").
# -Progresso: arquivo onde o processo elevado deixa o progresso para o processo normal mostrar.
function Invoke-TmdAcaoPorItem {
    param([Parameter(Mandatory)]$Acao, [Parameter(Mandatory)][AllowEmptyCollection()][object[]]$Alvos, [string]$Progresso)
    $total = $Alvos.Count
    $i = 0
    foreach ($a in $Alvos) {
        $i++
        $nome = [string](Get-Propriedade -Objeto $a -Nome 'Nome')
        if (-not $nome) { $nome = [string]$a.Id }
        Write-TmdProgresso -Texto $nome -Atual $i -Total $total
        if ($Progresso) { Save-TmdProgresso -Arquivo $Progresso -Texto $nome -Atual $i -Total $total }
        @(& $Acao -Alvos @($a))
    }
    Complete-TmdProgresso
}

# Progresso pelo canal normal do PowerShell: a CLI mostra a barra do console; a interface lê das tarefas.
function Write-TmdProgresso {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Texto, [int]$Atual, [int]$Total)
    $porcento = if ($Total -gt 0) { [int](100 * ($Atual - 1) / $Total) } else { -1 }
    Write-Progress -Activity 'Tamanduá' -Status $Texto -CurrentOperation "$Atual de $Total" -PercentComplete $porcento
}

function Complete-TmdProgresso {
    Write-Progress -Activity 'Tamanduá' -Completed
}

function Save-TmdProgresso {
    param([string]$Arquivo, [string]$Texto, [int]$Atual, [int]$Total)
    try {
        $json = [pscustomobject]@{ Texto = $Texto; Atual = $Atual; Total = $Total } | ConvertTo-Json -Compress
        [IO.File]::WriteAllText($Arquivo, $json, (New-Object Text.UTF8Encoding $false))
    }
    catch { Write-Verbose "progresso não gravado: $($_.Exception.Message)" }
}

function Read-TmdProgresso {
    param([string]$Arquivo)
    try {
        if (-not (Test-Path -LiteralPath $Arquivo)) { return $null }
        $texto = [IO.File]::ReadAllText($Arquivo, [Text.Encoding]::UTF8)
        if (-not $texto) { return $null }
        $texto | ConvertFrom-Json
    }
    catch { $null }   # pode estar no meio de uma gravação; lê de novo na próxima volta
}

# Desfaz ajustes pelo Id; os que precisam de admin (ex.: política em HKLM) vão juntos num processo elevado.
function Undo-TmdAjusteComAdmin {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string[]]$Ids, [string]$Raiz = $script:RaizPadrao, [string]$Modulo = 'historico')

    $admin = Test-TmdAdministrador
    $elevar = @($Ids | Where-Object { -not $admin -and (Test-TmdDesfazerPrecisaAdmin -Id $_) })
    $porId = @{}
    $locais = @($Ids | Where-Object { $elevar -notcontains $_ })
    $i = 0
    foreach ($id in $locais) {
        $i++
        Write-TmdProgresso -Texto $id -Atual $i -Total $locais.Count
        $porId[$id] = Undo-TmdAjuste -Id $id -Modulo $Modulo
    }
    if ($locais.Count -gt 0) { Complete-TmdProgresso }
    if ($elevar.Count -gt 0) {
        $alvos = @($elevar | ForEach-Object { [pscustomobject]@{ Id = $_ } })
        foreach ($r in @(Invoke-TmdAcaoElevada -Raiz $Raiz -Modulo '__desfazer' -Alvos $alvos)) { $porId[[string]$r.Id] = $r }
    }
    foreach ($id in $Ids) { if ($porId.ContainsKey($id)) { $porId[$id] } }
}

function Invoke-TmdAcaoElevada {
    param([Parameter(Mandatory)][string]$Raiz, [Parameter(Mandatory)][string]$Modulo, [Parameter(Mandatory)][object[]]$Alvos)

    $pedido = New-TmdArquivoTemporario -Extensao '.json'
    $resposta = New-TmdArquivoTemporario -Extensao '.json'
    $progresso = New-TmdArquivoTemporario -Extensao '.json'
    $semAdmin = {
        param($m)
        foreach ($a in $Alvos) { [pscustomobject]@{ Id = [string]$a.Id; Status = 'Ignorado'; Liberado = [int64]0; Motivo = $m; Mudancas = @() } }
    }
    try {
        # Modulo '__desfazer' = desfazer ajustes pelo Id (Histórico); qualquer outro = Invoke-Acao daquele módulo.
        $conteudo = [pscustomobject]@{ Modulo = $Modulo; Alvos = @($Alvos); Resposta = $resposta; Progresso = $progresso } | ConvertTo-Json -Depth 6
        [IO.File]::WriteAllText($pedido, $conteudo, (New-Object Text.UTF8Encoding $false))
        try {
            $processo = Start-TmdProcessoElevado -Script (Join-Path $Raiz 'tamandua.ps1') -Pedido $pedido
        }
        catch {
            return & $semAdmin "permissão de administrador negada ou cancelada ($((Get-TmdExcecaoInterna $_.Exception).Message))"
        }
        # Enquanto o processo elevado trabalha, repassa o progresso que ele deixa no arquivo.
        $ultimo = ''
        while (-not $processo.HasExited) {
            $p = Read-TmdProgresso -Arquivo $progresso
            if ($p) {
                $chave = "$($p.Atual)|$($p.Texto)"
                if ($chave -ne $ultimo) { Write-TmdProgresso -Texto ([string]$p.Texto) -Atual ([int]$p.Atual) -Total ([int]$p.Total); $ultimo = $chave }
            }
            Start-Sleep -Milliseconds 300
        }
        Complete-TmdProgresso
        if (-not (Test-Path -LiteralPath $resposta) -or (Get-Item -LiteralPath $resposta).Length -eq 0) {
            return & $semAdmin 'o processo de administrador não devolveu resultado'
        }
        foreach ($r in ([IO.File]::ReadAllText($resposta, [Text.Encoding]::UTF8) | ConvertFrom-Json)) { $r }
    }
    finally {
        Remove-TmdArquivoTemporario -Caminho $pedido
        Remove-TmdArquivoTemporario -Caminho $resposta
        Remove-TmdArquivoTemporario -Caminho $progresso
    }
}

# Ao abrir o programa (sem comando), pede admin uma vez, como o WinUtil: assim ajustes do sistema, serviços e limpezas
# do Windows rodam sem pedir de novo a cada ação. Recusou o UAC: abre assim mesmo, e cada ação que precisar pede na hora.
# Devolve $true quando outra cópia, como administrador, foi aberta (esta deve terminar).
# Testes: TAMANDUA_NAO_ELEVAR=1 (Ajudantes.ps1 liga) nunca pede.
function Request-TmdAdminAoAbrir {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Script)
    if ($env:TAMANDUA_NAO_ELEVAR -eq '1' -or (Test-TmdAdministrador)) { return $false }
    try {
        Start-TmdReaberturaElevada -Script $Script
        $true
    }
    catch {
        Write-Verbose "admin recusado ao abrir: $($_.Exception.Message)"
        $false
    }
}

# Abre o Tamanduá de novo como administrador (Mock nos testes).
function Start-TmdReaberturaElevada {
    param([Parameter(Mandatory)][string]$Script)
    $argumentos = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-STA', '-File', "`"$Script`"")
    Start-Process -FilePath 'powershell.exe' -Verb RunAs -ArgumentList $argumentos | Out-Null
}

# Único ponto que pede o UAC (Mock nos testes). Devolve o processo, sem esperar: quem chama acompanha o progresso.
function Start-TmdProcessoElevado {
    param([Parameter(Mandatory)][string]$Script, [Parameter(Mandatory)][string]$Pedido)
    $argumentos = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', "`"$Script`"", '__elevado', "`"$Pedido`"")
    Start-Process -FilePath 'powershell.exe' -Verb RunAs -ArgumentList $argumentos -WindowStyle Hidden -PassThru
}

# Lado elevado: lê o pedido, roda o Invoke-Acao do módulo e grava os resultados na resposta.
# Só aceita pedido e resposta que sejam temporários do Tamanduá.
function Invoke-TmdExecucaoElevada {
    param([Parameter(Mandatory)][string]$Pedido, [Parameter(Mandatory)][string]$Raiz)

    Test-TmdTemporarioValido -Caminho $Pedido
    $dados = [IO.File]::ReadAllText($Pedido, [Text.Encoding]::UTF8) | ConvertFrom-Json
    Test-TmdTemporarioValido -Caminho ([string]$dados.Resposta)
    $progresso = [string](Get-Propriedade -Objeto $dados -Nome 'Progresso')
    if ($progresso) { Test-TmdTemporarioValido -Caminho $progresso }
    if ([string]$dados.Modulo -eq '__desfazer') {
        $acao = { param([object[]]$Alvos) foreach ($a in $Alvos) { Undo-TmdAjuste -Id ([string]$a.Id) -Modulo 'historico' } }
    }
    else {
        $info = Get-TmdModulo -Raiz $Raiz -Nome ([string]$dados.Modulo)
        if (-not $info -or $info.Estado -ne 'ok') { throw "módulo $($dados.Modulo) não está disponível" }
        $acao = $info.Modulo.ExportedFunctions['Invoke-Acao']
    }
    $resultados = @(Invoke-TmdAcaoPorItem -Acao $acao -Alvos @($dados.Alvos) -Progresso $progresso)
    $json = if ($resultados.Count -eq 0) { '[]' } else { ConvertTo-Json -InputObject $resultados -Depth 6 }
    [IO.File]::WriteAllText([string]$dados.Resposta, $json, (New-Object Text.UTF8Encoding $false))
}

function Test-TmdTemporarioValido {
    param([string]$Caminho)
    $completo = [IO.Path]::GetFullPath($Caminho)
    $temp = [IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\')
    if ((Split-Path -Parent $completo) -ne $temp -or (Split-Path -Leaf $completo) -notlike 'tamandua-*.json') {
        throw "arquivo de pedido inválido: $Caminho"
    }
}

# Roda um programa do sistema (sfc, dism, netsh...) e devolve código de saída e saída. Registra no log.
function Invoke-TmdPrograma {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Arquivo,
        [string]$Argumentos = '',
        [string]$Modulo = '',
        [string]$Id = ''
    )
    $psi = New-Object Diagnostics.ProcessStartInfo
    $psi.FileName = $Arquivo
    $psi.Arguments = $Argumentos
    $psi.UseShellExecute = $false
    $psi.CreateNoWindow = $true
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $p = [Diagnostics.Process]::Start($psi)
    $saida = $p.StandardOutput.ReadToEndAsync()
    $erro = $p.StandardError.ReadToEndAsync()
    $p.WaitForExit()
    $linhas = @(($saida.Result + "`n" + $erro.Result) -split "`r?`n" | ForEach-Object { $_ -replace "`0", '' } | Where-Object { $_.Trim() })
    $status = if ($p.ExitCode -eq 0) { 'Feito' } else { 'Erro' }
    Write-TmdOperacao -Modulo $Modulo -Id $Id -Acao 'executar' -Caminho "$Arquivo $Argumentos".Trim() -Status $status -Motivo "código $($p.ExitCode)"
    [pscustomobject]@{ Codigo = $p.ExitCode; Saida = $linhas }
}
