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
    # Simular não muda nada: roda aqui mesmo, sem pedir admin.
    if ($Simular -or -not $Info.Manifesto['RequerAdmin'] -or (Test-TmdAdministrador)) {
        return @(& $acao -Alvos $Alvos -Simular:$Simular)
    }
    $elevar = @($Alvos | Where-Object { (Get-Propriedade -Objeto $_ -Nome 'RequerAdmin') -eq $true })
    $aqui = @($Alvos | Where-Object { (Get-Propriedade -Objeto $_ -Nome 'RequerAdmin') -ne $true })
    $porId = @{}
    if ($aqui.Count -gt 0) { foreach ($r in @(& $acao -Alvos $aqui)) { $porId[[string]$r.Id] = $r } }
    if ($elevar.Count -gt 0) { foreach ($r in @(Invoke-TmdAcaoElevada -Raiz $Raiz -Modulo $Info.Nome -Alvos $elevar)) { $porId[[string]$r.Id] = $r } }
    foreach ($a in $Alvos) { if ($porId.ContainsKey([string]$a.Id)) { $porId[[string]$a.Id] } }
}

function Invoke-TmdAcaoElevada {
    param([Parameter(Mandatory)][string]$Raiz, [Parameter(Mandatory)][string]$Modulo, [Parameter(Mandatory)][object[]]$Alvos)

    $pedido = New-TmdArquivoTemporario -Extensao '.json'
    $resposta = New-TmdArquivoTemporario -Extensao '.json'
    $semAdmin = {
        param($m)
        foreach ($a in $Alvos) { [pscustomobject]@{ Id = [string]$a.Id; Status = 'Ignorado'; Liberado = [int64]0; Motivo = $m; Mudancas = @() } }
    }
    try {
        $conteudo = [pscustomobject]@{ Modulo = $Modulo; Alvos = @($Alvos); Resposta = $resposta } | ConvertTo-Json -Depth 6
        [IO.File]::WriteAllText($pedido, $conteudo, (New-Object Text.UTF8Encoding $false))
        try {
            [void](Start-TmdProcessoElevado -Script (Join-Path $Raiz 'tamandua.ps1') -Pedido $pedido)
        }
        catch {
            return & $semAdmin "permissão de administrador negada ou cancelada ($((Get-TmdExcecaoInterna $_.Exception).Message))"
        }
        if (-not (Test-Path -LiteralPath $resposta) -or (Get-Item -LiteralPath $resposta).Length -eq 0) {
            return & $semAdmin 'o processo de administrador não devolveu resultado'
        }
        foreach ($r in ([IO.File]::ReadAllText($resposta, [Text.Encoding]::UTF8) | ConvertFrom-Json)) { $r }
    }
    finally {
        Remove-TmdArquivoTemporario -Caminho $pedido
        Remove-TmdArquivoTemporario -Caminho $resposta
    }
}

# Único ponto que pede o UAC (Mock nos testes). Espera o processo elevado terminar.
function Start-TmdProcessoElevado {
    param([Parameter(Mandatory)][string]$Script, [Parameter(Mandatory)][string]$Pedido)
    $argumentos = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', "`"$Script`"", '__elevado', "`"$Pedido`"")
    (Start-Process -FilePath 'powershell.exe' -Verb RunAs -ArgumentList $argumentos -WindowStyle Hidden -Wait -PassThru).ExitCode
}

# Lado elevado: lê o pedido, roda o Invoke-Acao do módulo e grava os resultados na resposta.
# Só aceita pedido e resposta que sejam temporários do Tamanduá.
function Invoke-TmdExecucaoElevada {
    param([Parameter(Mandatory)][string]$Pedido, [Parameter(Mandatory)][string]$Raiz)

    Test-TmdTemporarioValido -Caminho $Pedido
    $dados = [IO.File]::ReadAllText($Pedido, [Text.Encoding]::UTF8) | ConvertFrom-Json
    Test-TmdTemporarioValido -Caminho ([string]$dados.Resposta)
    $info = Get-TmdModulo -Raiz $Raiz -Nome ([string]$dados.Modulo)
    if (-not $info -or $info.Estado -ne 'ok') { throw "módulo $($dados.Modulo) não está disponível" }
    $resultados = @(& $info.Modulo.ExportedFunctions['Invoke-Acao'] -Alvos @($dados.Alvos))
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
