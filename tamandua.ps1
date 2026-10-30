<#
.SYNOPSIS
    Tamanduá - limpeza, ajustes e manutenção para Windows.
.DESCRIPTION
    Sem argumentos abre a interface (ou o menu de texto, se ela faltar).
    Use "tamandua ajuda" para ver os comandos.
#>
[CmdletBinding()]
param(
    [Parameter(Position = 0)][string]$Comando,
    # Mostra o que seria feito, sem alterar nada.
    [switch]$Simular,
    # Confirma sem perguntar (para scripts).
    [switch]$Sim,
    # Marca os itens de um preset do módulo (ex.: tamandua ajustes -Preset Essencial).
    [string]$Preset,
    # Marca exatamente estes itens, pelo id (ex.: -Itens priv-id-anuncios,expl-extensoes).
    [string[]]$Itens,
    # Esconde a janela do console quando a interface aparece (o Tamandua.cmd e a cópia aberta como administrador usam).
    [switch]$EsconderConsole,
    [Parameter(ValueFromRemainingArguments = $true)][string[]]$Resto
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
try { [Console]::OutputEncoding = [Text.Encoding]::UTF8 } catch { Write-Verbose 'Console sem suporte a UTF-8.' }

# O programa é feito para o Windows PowerShell 5.1, num processo STA (a janela é WPF). Aberto no PowerShell 7 (pwsh)
# ou sem STA, abre de novo do jeito certo, com os mesmos argumentos, e devolve o código dele.
function Get-ArgumentosOriginais {
    $a = [System.Collections.Generic.List[string]]::new()
    if ($Comando) { $a.Add("`"$Comando`"") }
    if ($Simular) { $a.Add('-Simular') }
    if ($Sim) { $a.Add('-Sim') }
    if ($Preset) { $a.Add('-Preset'); $a.Add("`"$Preset`"") }
    if ($Itens) { $a.Add('-Itens'); $a.Add("`"$($Itens -join ',')`"") }
    if ($EsconderConsole) { $a.Add('-EsconderConsole') }
    foreach ($r in @($Resto | Where-Object { $_ })) { $a.Add("`"$r`"") }
    $a
}
$ehCore = $PSVersionTable.PSEdition -eq 'Core'
$semSta = -not $Comando -and [Threading.Thread]::CurrentThread.GetApartmentState() -ne 'STA'
if ($ehCore -or $semSta) {
    $ps = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
    $argumentos = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-STA', '-File', "`"$PSCommandPath`"") + @(Get-ArgumentosOriginais)
    $p = Start-Process -FilePath $ps -ArgumentList $argumentos -NoNewWindow -Wait -PassThru
    exit $p.ExitCode
}

# Erro ao abrir: grava os detalhes num arquivo (para quem for ajudar) e, sem comando (a janela), mostra uma caixa de
# mensagem, porque o console da cópia aberta como administrador fecha sozinho e ninguém conseguiria ler.
function Write-ErroAoAbrir {
    param([string]$Mensagem, $Erro)
    $pasta = Join-Path ([Environment]::GetFolderPath('LocalApplicationData')) 'Tamandua\logs'
    $arquivo = Join-Path $pasta 'erro-ao-abrir.txt'
    try {
        [void][IO.Directory]::CreateDirectory($pasta)
        $politica = try { (Get-ExecutionPolicy -List | ForEach-Object { "$($_.Scope)=$($_.ExecutionPolicy)" }) -join ', ' } catch { '?' }
        $texto = @(
            "Data: $((Get-Date).ToString('yyyy-MM-dd HH:mm:ss'))"
            "Windows: $([Environment]::OSVersion.VersionString) | PowerShell: $($PSVersionTable.PSVersion) $($PSVersionTable.PSEdition) | idioma: $([Globalization.CultureInfo]::CurrentCulture.Name)"
            "Pasta: $PSScriptRoot | comando: '$Comando' | admin: $(([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole('Administrators'))"
            "Política de scripts: $politica"
            ''
            $Mensagem
            $(if ($Erro) { "`n$($Erro | Out-String)`n$($Erro.ScriptStackTrace)" })
        ) -join "`r`n"
        [IO.File]::WriteAllText($arquivo, $texto, (New-Object Text.UTF8Encoding $true))
    }
    catch { $arquivo = '(não foi possível gravar o arquivo de erro)' }
    # Se o console foi escondido, volta a aparecer para mostrar o erro.
    try {
        Add-Type -Namespace Tamandua -Name ConsoleErro -MemberDefinition '[DllImport("kernel32.dll")] public static extern System.IntPtr GetConsoleWindow(); [DllImport("user32.dll")] public static extern bool ShowWindow(System.IntPtr h, int c);' -ErrorAction Stop
        [void][Tamandua.ConsoleErro]::ShowWindow([Tamandua.ConsoleErro]::GetConsoleWindow(), 9)
    }
    catch { Write-Verbose 'sem console para mostrar' }
    [Console]::Error.WriteLine("Tamanduá: $Mensagem")
    [Console]::Error.WriteLine("Detalhes em: $arquivo")
    if (-not $Comando -and $env:TAMANDUA_NAO_ELEVAR -ne '1' -and [Environment]::UserInteractive) {
        try {
            Add-Type -AssemblyName PresentationFramework
            [void][Windows.MessageBox]::Show("$Mensagem`n`nOs detalhes ficaram em:`n$arquivo`n`nSe for pedir ajuda, mande esse arquivo.", 'Tamanduá não conseguiu abrir', 'OK', 'Error')
        }
        catch { Write-Verbose 'sem caixa de mensagem' }
    }
}

# O núcleo é a única parte obrigatória; sem ele não há o que fazer.
$nucleo = Join-Path $PSScriptRoot 'nucleo\Tamandua.Nucleo.psm1'
if (-not (Test-Path -LiteralPath $nucleo -PathType Leaf)) {
    Write-ErroAoAbrir -Mensagem "Núcleo não encontrado em $nucleo. Baixe o programa de novo (a pasta inteira, não só o tamandua.ps1)."
    exit 1
}
try {
    if ($EsconderConsole) { $env:TAMANDUA_ESCONDER_CONSOLE = '1' }
    # -Global: os módulos usam funções exportadas do núcleo (ex.: Format-TmdTamanho).
    Import-Module -Name $nucleo -Force -DisableNameChecking -Global
    $codigo = Invoke-TmdCli -Comando $Comando -Argumentos $Resto -Raiz $PSScriptRoot -Simular:$Simular -Sim:$Sim -Preset $Preset -Itens $Itens
}
catch {
    Write-ErroAoAbrir -Mensagem "Erro inesperado: $($_.Exception.Message)" -Erro $_
    $codigo = 1
}
exit $codigo
