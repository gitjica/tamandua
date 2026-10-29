# Reparos do Windows. Cada reparo é um alvo; todos precisam de administrador (o núcleo eleva o lote).
# Programas do sistema rodam pelo Invoke-TmdPrograma do núcleo (registra no log); arquivos, pelo Remove-TmdItem.

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$script:Reparos = [ordered]@{
    'chkdsk'         = @{ Nome = 'Verificar o disco C: (sem reiniciar)'; Categoria = 'Disco e arquivos do sistema'; Risco = 'Baixo'; Tempo = 'alguns minutos'
        Explicacao = 'chkdsk C: /scan: procura erros no sistema de arquivos com o Windows ligado. Não corrige nada; se achar problema, diz o que fazer.' }
    'sfc'            = @{ Nome = 'Verificar e reparar arquivos do sistema (SFC)'; Categoria = 'Disco e arquivos do sistema'; Risco = 'Baixo'; Tempo = '10 a 20 minutos'
        Explicacao = 'sfc /scannow: confere os arquivos protegidos do Windows e troca os corrompidos pela cópia boa.' }
    'dism'           = @{ Nome = 'Reparar a imagem do Windows (DISM)'; Categoria = 'Disco e arquivos do sistema'; Risco = 'Baixo'; Tempo = '10 a 30 minutos'
        Explicacao = 'DISM /Online /Cleanup-Image /RestoreHealth: conserta a cópia de onde o SFC tira os arquivos bons (usa o Windows Update). Rode antes do SFC se o SFC não conseguir reparar.' }
    'rede'           = @{ Nome = 'Resetar a rede (Winsock e TCP/IP)'; Categoria = 'Rede e atualizações'; Risco = 'Medio'; Tempo = 'segundos (pede reinício)'
        Explicacao = 'netsh winsock reset e netsh int ip reset: volta as configurações de rede ao padrão. IP fixo e alguns VPNs precisam ser configurados de novo.' }
    'windows-update' = @{ Nome = 'Destravar o Windows Update'; Categoria = 'Rede e atualizações'; Risco = 'Medio'; Tempo = '1 a 2 minutos'
        Explicacao = 'Para o Windows Update e o BITS, apaga as atualizações baixadas pela metade (SoftwareDistribution\Download) e liga os serviços de novo. Ele baixa tudo outra vez.' }
}

function Test-Requisitos {
    @{ Ok = $true; Motivo = '' }
}

# Lista fixa de reparos. Nada vem marcado: reparo é para quando há problema.
function Find-Alvos {
    foreach ($id in $script:Reparos.Keys) {
        $r = $script:Reparos[$id]
        [pscustomobject]@{
            Id = $id; Nome = $r.Nome; Categoria = $r.Categoria; Caminho = ''; Tamanho = [int64]0; Estado = 'NaoSeAplica'
            Detalhe = "Leva $($r.Tempo)."; Nivel = 'Normal'; Valor = $null; Risco = $r.Risco; Selecionado = $false
            Destino = 'NaoSeAplica'; RequerAdmin = $true; Reversivel = $false; Mudancas = @($r.Explicacao)
        }
    }
}

# -PastaDownload troca SoftwareDistribution\Download (testes).
function Invoke-Acao {
    param(
        [Parameter(Mandatory)][AllowEmptyCollection()][object[]]$Alvos,
        [switch]$Simular,
        [string]$PastaDownload = (Join-Path $env:SystemRoot 'SoftwareDistribution\Download')
    )
    foreach ($a in $Alvos) {
        $id = [string]$a.Id
        if (-not $script:Reparos.Contains($id)) { New-ResultadoReparo -Id $id -Status 'Erro' -Motivo 'reparo desconhecido'; continue }
        if ($Simular) { New-ResultadoReparo -Id $id -Status 'Simulado' -Mudancas @($script:Reparos[$id].Explicacao); continue }
        switch ($id) {
            'chkdsk' { Invoke-Chkdsk }
            'sfc' { Invoke-Sfc }
            'dism' { Invoke-Dism }
            'rede' { Invoke-ResetRede }
            'windows-update' { Invoke-ResetWindowsUpdate -PastaDownload $PastaDownload }
        }
    }
}

function Invoke-Chkdsk {
    $r = Invoke-TmdPrograma -Arquivo 'chkdsk.exe' -Argumentos 'C: /scan' -Modulo 'reparos' -Id 'chkdsk'
    switch ($r.Codigo) {
        0 { New-ResultadoReparo -Id 'chkdsk' -Status 'Feito' -Motivo 'nenhum problema encontrado' }
        1 { New-ResultadoReparo -Id 'chkdsk' -Status 'Feito' -Motivo 'erros encontrados e corrigidos' }
        2 { New-ResultadoReparo -Id 'chkdsk' -Status 'Feito' -Motivo 'limpeza feita, sem erros' }
        default { New-ResultadoReparo -Id 'chkdsk' -Status 'Parcial' -Motivo "problemas que precisam de reinício: rode ""chkdsk C: /f"" como administrador e reinicie (código $($r.Codigo))" }
    }
}

function Invoke-Sfc {
    $r = Invoke-TmdPrograma -Arquivo 'sfc.exe' -Argumentos '/scannow' -Modulo 'reparos' -Id 'sfc'
    if ($r.Codigo -eq 0) { return New-ResultadoReparo -Id 'sfc' -Status 'Feito' -Motivo 'detalhes em C:\Windows\Logs\CBS\CBS.log' }
    New-ResultadoReparo -Id 'sfc' -Status 'Erro' -Motivo "o SFC terminou com código $($r.Codigo); tente o DISM e depois o SFC de novo"
}

function Invoke-Dism {
    $r = Invoke-TmdPrograma -Arquivo 'DISM.exe' -Argumentos '/Online /Cleanup-Image /RestoreHealth' -Modulo 'reparos' -Id 'dism'
    if ($r.Codigo -eq 0) { return New-ResultadoReparo -Id 'dism' -Status 'Feito' -Motivo 'imagem do Windows verificada e reparada' }
    New-ResultadoReparo -Id 'dism' -Status 'Erro' -Motivo "o DISM terminou com código $($r.Codigo) (precisa de internet para baixar os arquivos bons)"
}

function Invoke-ResetRede {
    $w = Invoke-TmdPrograma -Arquivo 'netsh.exe' -Argumentos 'winsock reset' -Modulo 'reparos' -Id 'rede'
    $i = Invoke-TmdPrograma -Arquivo 'netsh.exe' -Argumentos 'int ip reset' -Modulo 'reparos' -Id 'rede'
    if ($w.Codigo -eq 0 -and $i.Codigo -eq 0) { return New-ResultadoReparo -Id 'rede' -Status 'Feito' -Motivo 'reinicie o computador para terminar' }
    New-ResultadoReparo -Id 'rede' -Status 'Erro' -Motivo "netsh terminou com código $($w.Codigo) (winsock) e $($i.Codigo) (ip)"
}

# Serviços parados -> downloads pela metade apagados (pelo núcleo) -> serviços ligados de novo, mesmo se algo falhar no meio.
function Invoke-ResetWindowsUpdate {
    param([Parameter(Mandatory)][string]$PastaDownload)
    $servicos = 'wuauserv', 'bits'
    $liberado = [int64]0
    $falhas = @()
    try {
        foreach ($s in $servicos) { [void](Invoke-TmdPrograma -Arquivo 'net.exe' -Argumentos "stop $s" -Modulo 'reparos' -Id 'windows-update') }
        if (Test-Path -LiteralPath $PastaDownload) {
            foreach ($item in @(Get-ChildItem -LiteralPath $PastaDownload -Force)) {
                $r = Remove-TmdItem -Caminho $item.FullName -Raizes $PastaDownload -Modulo 'reparos' -Id 'windows-update'
                $liberado += $r.Liberado
                if ($r.Status -notin 'Feito') { $falhas += $r.Motivo }
            }
        }
    }
    finally {
        foreach ($s in $servicos) { [void](Invoke-TmdPrograma -Arquivo 'net.exe' -Argumentos "start $s" -Modulo 'reparos' -Id 'windows-update') }
    }
    $motivo = "$(Format-TmdTamanho $liberado) de downloads pela metade apagados; o Windows Update baixa de novo"
    if ($falhas.Count -gt 0) { return New-ResultadoReparo -Id 'windows-update' -Status 'Parcial' -Motivo "$motivo; $($falhas.Count) item(ns) não apagados ($($falhas[0]))" -Liberado $liberado }
    New-ResultadoReparo -Id 'windows-update' -Status 'Feito' -Motivo $motivo -Liberado $liberado
}

function New-ResultadoReparo {
    param([string]$Id, [string]$Status, [string]$Motivo = '', [string[]]$Mudancas = @(), [int64]$Liberado = 0)
    [pscustomobject]@{ Id = $Id; Status = $Status; Liberado = $Liberado; Motivo = $Motivo; Mudancas = $Mudancas }
}

Export-ModuleMember -Function Test-Requisitos, Find-Alvos, Invoke-Acao
