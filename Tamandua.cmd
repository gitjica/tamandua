@echo off
rem Abre o Tamandua com o PowerShell do Windows (5.1), de qualquer pasta.
rem -ExecutionPolicy Bypass vale so para esta execucao: nao muda nenhuma configuracao do Windows, e evita o bloqueio
rem de scripts (politica "Restricted" padrao e arquivos baixados da internet).
rem Sem argumentos (a janela): abre num console classico (conhost), minimizado, que some quando a janela aparece;
rem assim funciona tambem onde o Windows Terminal e o console padrao. Erro ao abrir: aparece numa caixa de mensagem.
if "%~1"=="" (
    start "" /min "%SystemRoot%\System32\conhost.exe" powershell.exe -NoProfile -ExecutionPolicy Bypass -STA -File "%~dp0tamandua.ps1" -EsconderConsole
    exit /b 0
)
rem Com argumentos (linha de comando): Tamandua.cmd limpar -Simular
powershell.exe -NoProfile -ExecutionPolicy Bypass -STA -File "%~dp0tamandua.ps1" %*
if errorlevel 1 (
    echo.
    echo O Tamandua terminou com erro. Os detalhes ficam em %LOCALAPPDATA%\Tamandua\logs\erro-ao-abrir.txt
    pause
)