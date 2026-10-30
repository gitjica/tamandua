# Abre o Tamandua direto do GitHub, sem baixar nada a mao. No PowerShell:
#
#   irm gitjica.github.io/tamandua | iex     (docs/index.html, que roda este arquivo)
#   irm https://raw.githubusercontent.com/gitjica/tamandua/main/instalar.ps1 | iex
#
# Baixa a versao mais nova (o ZIP do GitHub), coloca em %LOCALAPPDATA%\Tamandua\app (troca a versao anterior; o
# historico e as configuracoes ficam onde estao) e abre o programa, igual ao Tamandua.cmd.
#
# Este arquivo e so ASCII e sem BOM de proposito: o "iex" nao aceita o BOM, e sem BOM acento sairia errado.
# Testes: TAMANDUA_ORIGEM troca de onde vem o ZIP (endereco ou arquivo); TAMANDUA_SO_BAIXAR=1 nao abre o programa.

& {
    $ErrorActionPreference = 'Stop'
    $origem = if ($env:TAMANDUA_ORIGEM) { $env:TAMANDUA_ORIGEM } else { 'https://github.com/gitjica/tamandua/archive/refs/heads/main.zip' }
    $base = Join-Path $env:LOCALAPPDATA 'Tamandua'
    $app = Join-Path $base 'app'
    $temp = Join-Path ([IO.Path]::GetTempPath()) ('tamandua-instalar-' + [guid]::NewGuid().ToString('N'))
    try {
        [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
        [void][IO.Directory]::CreateDirectory($temp)
        $zip = Join-Path $temp 'tamandua.zip'
        Write-Host 'Baixando o Tamandua...' -ForegroundColor Cyan
        if (Test-Path -LiteralPath $origem -PathType Leaf) { Copy-Item -LiteralPath $origem -Destination $zip }
        else {
            $antes = $ProgressPreference
            $ProgressPreference = 'SilentlyContinue'
            try { Invoke-WebRequest -UseBasicParsing -Uri $origem -OutFile $zip -UserAgent 'Tamandua' -TimeoutSec 300 }
            finally { $ProgressPreference = $antes }
        }

        Add-Type -AssemblyName System.IO.Compression.FileSystem
        $extraido = Join-Path $temp 'extraido'
        [IO.Compression.ZipFile]::ExtractToDirectory($zip, $extraido)
        # O ZIP do GitHub vem com uma pasta por fora (tamandua-main); o programa e a que tem o tamandua.ps1 e o nucleo.
        $raiz = @(Get-ChildItem -LiteralPath $extraido -Recurse -Filter 'tamandua.ps1' -File |
                Where-Object { Test-Path -LiteralPath (Join-Path $_.DirectoryName 'nucleo\Tamandua.Nucleo.psm1') } |
                Select-Object -First 1 | ForEach-Object DirectoryName)
        if ($raiz.Count -eq 0) { throw 'o arquivo baixado nao tem o Tamandua dentro' }

        # Troca so a pasta do programa (app); logs, historico e estado salvo ficam em Tamandua\, fora dela.
        [void][IO.Directory]::CreateDirectory($base)
        if (Test-Path -LiteralPath $app) { Remove-Item -LiteralPath $app -Recurse -Force }
        Move-Item -LiteralPath $raiz[0] -Destination $app
        Write-Host "Tamandua em $app" -ForegroundColor Green

        if ($env:TAMANDUA_SO_BAIXAR -eq '1') { return }
        # Como o Tamandua.cmd: Windows PowerShell 5.1, so nesta execucao sem bloqueio de scripts, console classico
        # minimizado que some quando a janela aparece.
        $script = Join-Path $app 'tamandua.ps1'
        $ps = @('powershell.exe', '-NoProfile', '-ExecutionPolicy', 'Bypass', '-STA', '-File', "`"$script`"", '-EsconderConsole')
        $conhost = Join-Path $env:SystemRoot 'System32\conhost.exe'
        if (Test-Path -LiteralPath $conhost) { Start-Process -FilePath $conhost -ArgumentList $ps -WindowStyle Minimized }
        else { Start-Process -FilePath 'powershell.exe' -ArgumentList $ps[1..($ps.Count - 1)] }
        Write-Host 'Abrindo... (pode pedir permissao de administrador)' -ForegroundColor Green
    }
    catch {
        Write-Host "Nao deu para abrir o Tamandua: $($_.Exception.Message)" -ForegroundColor Red
        Write-Host 'Tente baixar o ZIP em https://github.com/gitjica/tamandua e abrir o Tamandua.cmd.' -ForegroundColor Yellow
    }
    finally {
        if (Test-Path -LiteralPath $temp) { Remove-Item -LiteralPath $temp -Recurse -Force -ErrorAction SilentlyContinue }
    }
}
