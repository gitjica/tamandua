# Ajudantes compartilhados pelos testes. Tudo acontece dentro da sandbox do Pester ($TestDrive).

$script:RaizProjeto = Split-Path -Parent $PSScriptRoot

# Configuração e log dos testes vão para a sandbox, nunca para %APPDATA% / %LOCALAPPDATA% reais.
# Vale também para os processos filhos (Invoke-Tamandua), que herdam o ambiente.
if ($TestDrive) {
    $env:TAMANDUA_CONFIG = Join-Path $TestDrive 'config-usuario'
    $env:TAMANDUA_DADOS = Join-Path $TestDrive 'dados-usuario'
}

$script:CodigoModuloValido = @'
function Test-Requisitos { @{ Ok = $true; Motivo = '' } }
function Find-Alvos { @() }
'@

# Copia o núcleo e o ponto de entrada para uma pasta nova. Com -Catalogo, troca o catálogo pelos nomes dados.
function New-ProjetoFalso {
    param([Parameter(Mandatory)][string]$Pai, [string[]]$Catalogo, [switch]$ComInterface)

    $raiz = Join-Path $Pai ([guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path (Join-Path $raiz 'modulos') -Force | Out-Null
    Copy-Item -LiteralPath (Join-Path $script:RaizProjeto 'nucleo') -Destination $raiz -Recurse
    Copy-Item -LiteralPath (Join-Path $script:RaizProjeto 'tamandua.ps1') -Destination $raiz
    Copy-Item -LiteralPath (Join-Path $script:RaizProjeto 'config') -Destination $raiz -Recurse
    if ($ComInterface) { Copy-Item -LiteralPath (Join-Path $script:RaizProjeto 'interface') -Destination $raiz -Recurse }
    if ($PSBoundParameters.ContainsKey('Catalogo')) {
        $linhas = foreach ($n in $Catalogo) { "        @{ Nome = '$n'; Grupo = 'Teste'; Descricao = 'Módulo $n' }" }
        $texto = "@{`r`n    Modulos = @(`r`n$($linhas -join "`r`n")`r`n    )`r`n}"
        Set-Content -LiteralPath (Join-Path $raiz 'nucleo\catalogo.psd1') -Value $texto -Encoding UTF8
    }
    $raiz
}

# Cria modulos\<Nome> com manifesto e código. Valores em -Manifesto sobrescrevem o padrão; $null remove o campo.
function New-ModuloFalso {
    param(
        [Parameter(Mandatory)][string]$Raiz,
        [Parameter(Mandatory)][string]$Nome,
        [hashtable]$Manifesto = @{},
        [string]$Codigo = $script:CodigoModuloValido,
        [string]$ManifestoBruto,
        [switch]$SemManifesto,
        [switch]$SemCodigo
    )

    $pasta = Join-Path $Raiz "modulos\$Nome"
    New-Item -ItemType Directory -Path $pasta -Force | Out-Null

    $campos = [ordered]@{
        Nome = $Nome; Versao = '0.1.0'; Descricao = "Módulo falso $Nome"; Arquivo = "$Nome.psm1"
        Escreve = $false; RequerAdmin = $false; ContratoMinimo = 1
    }
    foreach ($k in $Manifesto.Keys) {
        if ($null -eq $Manifesto[$k]) { $campos.Remove($k) } else { $campos[$k] = $Manifesto[$k] }
    }

    if (-not $SemManifesto) {
        $texto = if ($ManifestoBruto) { $ManifestoBruto } else { ConvertTo-Psd1 -Dados $campos }
        Set-Content -LiteralPath (Join-Path $pasta 'modulo.psd1') -Value $texto -Encoding UTF8
    }
    if (-not $SemCodigo) {
        $arquivo = if ($campos.Contains('Arquivo')) { $campos['Arquivo'] } else { "$Nome.psm1" }
        Set-Content -LiteralPath (Join-Path $pasta $arquivo) -Value $Codigo -Encoding UTF8
    }
    $pasta
}

function ConvertTo-Psd1 {
    param([Parameter(Mandatory)][System.Collections.IDictionary]$Dados)

    $linhas = foreach ($k in $Dados.Keys) {
        $v = $Dados[$k]
        $literal = if ($v -is [bool]) { if ($v) { '$true' } else { '$false' } }
        elseif ($v -is [int]) { "$v" }
        else { "'" + ([string]$v).Replace("'", "''") + "'" }
        "    $k = $literal"
    }
    "@{`r`n$($linhas -join "`r`n")`r`n}"
}

# Roda tamandua.ps1 num processo separado, sem console interativo, e devolve código e saída.
function Invoke-Tamandua {
    param([Parameter(Mandatory)][string]$Raiz, [string[]]$Argumentos = @())

    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = Join-Path $PSHOME 'powershell.exe'
    $psi.Arguments = "-NoProfile -ExecutionPolicy Bypass -File `"$(Join-Path $Raiz 'tamandua.ps1')`" $($Argumentos -join ' ')"
    $psi.UseShellExecute = $false
    $psi.CreateNoWindow = $true
    $psi.RedirectStandardInput = $true
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.StandardOutputEncoding = [Text.Encoding]::UTF8
    $psi.StandardErrorEncoding = [Text.Encoding]::UTF8

    $processo = [System.Diagnostics.Process]::Start($psi)
    $processo.StandardInput.Close()
    $saida = $processo.StandardOutput.ReadToEndAsync()
    $erro = $processo.StandardError.ReadToEndAsync()
    if (-not $processo.WaitForExit(60000)) {
        $processo.Kill()
        throw 'tamandua.ps1 não terminou em 60 s'
    }
    [pscustomobject]@{
        Codigo = $processo.ExitCode
        Saida  = $saida.Result
        Erro   = $erro.Result
        Tudo   = $saida.Result + $erro.Result
    }
}

# Árvore de arquivos para testes de remoção: { 'a.txt' = 'conteúdo'; 'sub\b.bin' = 'x' }. Devolve a pasta.
function New-ArvoreFalsa {
    param([Parameter(Mandatory)][string]$Pasta, [Parameter(Mandatory)][hashtable]$Arquivos)
    foreach ($rel in $Arquivos.Keys) {
        $caminho = Join-Path $Pasta $rel
        [void][IO.Directory]::CreateDirectory((Split-Path -Parent $caminho))
        [IO.File]::WriteAllText($caminho, [string]$Arquivos[$rel])
    }
    $Pasta
}

# Hash de todos os arquivos (caminho relativo + conteúdo), para provar que nada mudou.
function Get-AssinaturaPasta {
    param([Parameter(Mandatory)][string]$Pasta)
    if (-not (Test-Path -LiteralPath $Pasta)) { return '' }
    $linhas = Get-ChildItem -LiteralPath $Pasta -Recurse -Force | Sort-Object FullName | ForEach-Object {
        $rel = $_.FullName.Substring($Pasta.Length)
        if ($_.PSIsContainer) { "D $rel" } else { "F $rel $((Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash)" }
    }
    $linhas -join "`n"
}

# Comandos que escrevem no sistema e só podem aparecer no núcleo (Remocao.ps1 / MotorAjustes.ps1).
$script:ComandosProibidos = @(
    'Remove-Item', 'ri', 'rm', 'rmdir', 'del', 'erase', 'rd'
    'Clear-Content', 'Clear-RecycleBin'
    'Set-ItemProperty', 'New-ItemProperty', 'Remove-ItemProperty', 'Rename-ItemProperty'
    'Set-Service', 'Stop-Service', 'Start-Service', 'Restart-Service'
    'Enable-ScheduledTask', 'Disable-ScheduledTask', 'Unregister-ScheduledTask', 'Register-ScheduledTask'
    'Remove-AppxPackage', 'Remove-AppxProvisionedPackage'
    'Enable-WindowsOptionalFeature', 'Disable-WindowsOptionalFeature'
    'reg', 'reg.exe', 'sc', 'sc.exe', 'cmd', 'cmd.exe'
    'Write-Host'
)

# Varre .ps1/.psm1 de uma pasta e devolve onde aparece escrita no sistema (comandos ou [IO.File]::Delete etc.).
function Find-EscritaProibida {
    param([Parameter(Mandatory)][string]$Pasta)

    if (-not (Test-Path -LiteralPath $Pasta)) { return }
    # -Include é ignorado junto com -LiteralPath no 5.1; filtra pela extensão.
    $arquivos = Get-ChildItem -LiteralPath $Pasta -Recurse -File | Where-Object { $_.Extension -in '.ps1', '.psm1' }
    foreach ($arquivo in $arquivos) {
        $tokens = $null
        $erros = $null
        $ast = [System.Management.Automation.Language.Parser]::ParseFile($arquivo.FullName, [ref]$tokens, [ref]$erros)
        $achados = $ast.FindAll({
                param($no)
                if ($no -is [System.Management.Automation.Language.CommandAst]) {
                    return $script:ComandosProibidos -contains $no.GetCommandName()
                }
                if ($no -is [System.Management.Automation.Language.InvokeMemberExpressionAst]) {
                    return $no.Static -and ($no.Member.Extent.Text -in 'Delete', 'DeleteFile', 'DeleteDirectory')
                }
                $false
            }, $true)
        foreach ($a in $achados) {
            "$($arquivo.FullName):$($a.Extent.StartLineNumber): $($a.Extent.Text)"
        }
    }
}
