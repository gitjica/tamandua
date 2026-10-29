# Manutenção do Windows. Cada tarefa é um alvo; as que precisam de admin vão para o processo elevado (o núcleo separa),
# as outras rodam como o usuário (reiniciar o Explorer elevado deixaria a área de trabalho rodando como admin).

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$script:Tarefas = [ordered]@{
    'dns'         = @{ Nome = 'Limpar o cache de DNS'; Categoria = 'Rede'; Admin = $false; Tempo = 'na hora'
        Explicacao = 'ipconfig /flushdns: esquece endereços de sites guardados. Ajuda quando um site mudou de servidor e não abre.' }
    'icones'      = @{ Nome = 'Reconstruir o cache de ícones'; Categoria = 'Explorador de Arquivos'; Admin = $false; Tempo = 'alguns segundos'
        Explicacao = 'Fecha o Explorador, apaga IconCache.db e iconcache_*.db e abre o Explorador de novo. Ícones em branco ou errados voltam ao normal. A barra de tarefas some por uns segundos.' }
    'otimizar-c'  = @{ Nome = 'Otimizar a unidade C:'; Categoria = 'Disco'; Admin = $true; Tempo = 'de segundos a alguns minutos'
        Explicacao = 'defrag C: /O: faz a otimização certa para o tipo de disco (retrim no SSD, desfragmentação no HD). É o mesmo que o Windows faz agendado.' }
    'componentes' = @{ Nome = 'Limpar componentes antigos do Windows'; Categoria = 'Disco'; Admin = $true; Tempo = '5 a 15 minutos'
        Explicacao = 'DISM /Online /Cleanup-Image /StartComponentCleanup: remove versões antigas de componentes substituídas por atualizações. Atualizações recentes continuam desinstaláveis (sem /ResetBase).' }
}

function Test-Requisitos {
    @{ Ok = $true; Motivo = '' }
}

# -PastaLocal troca %LOCALAPPDATA% (testes).
function Find-Alvos {
    param([string]$PastaLocal = $env:LOCALAPPDATA)
    foreach ($id in $script:Tarefas.Keys) {
        $t = $script:Tarefas[$id]
        $detalhe = "Leva $($t.Tempo)."
        $tamanho = [int64]0
        if ($id -eq 'icones') {
            foreach ($f in Get-CacheIcones -PastaLocal $PastaLocal) { $tamanho += $f.Length }
            $detalhe = "$(Format-TmdTamanho $tamanho) de cache · $detalhe"
        }
        [pscustomobject]@{
            Id = $id; Nome = $t.Nome; Categoria = $t.Categoria; Caminho = ''; Tamanho = $tamanho; Estado = 'NaoSeAplica'
            Detalhe = $detalhe; Nivel = 'Normal'; Valor = $null; Risco = 'Baixo'; Selecionado = $false
            Destino = 'NaoSeAplica'; RequerAdmin = $t.Admin; Reversivel = $false; Mudancas = @($t.Explicacao)
        }
    }
}

function Invoke-Acao {
    param(
        [Parameter(Mandatory)][AllowEmptyCollection()][object[]]$Alvos,
        [switch]$Simular,
        [string]$PastaLocal = $env:LOCALAPPDATA
    )
    foreach ($a in $Alvos) {
        $id = [string]$a.Id
        if (-not $script:Tarefas.Contains($id)) { New-ResultadoOtimizar -Id $id -Status 'Erro' -Motivo 'tarefa desconhecida'; continue }
        if ($Simular) { New-ResultadoOtimizar -Id $id -Status 'Simulado' -Mudancas @($script:Tarefas[$id].Explicacao); continue }
        switch ($id) {
            'dns' { Invoke-LimparDns }
            'icones' { Invoke-ReconstruirIcones -PastaLocal $PastaLocal }
            'otimizar-c' { Invoke-OtimizarUnidade }
            'componentes' { Invoke-LimparComponentes }
        }
    }
}

function Invoke-LimparDns {
    $r = Invoke-TmdPrograma -Arquivo 'ipconfig.exe' -Argumentos '/flushdns' -Modulo 'otimizar' -Id 'dns'
    if ($r.Codigo -eq 0) { return New-ResultadoOtimizar -Id 'dns' -Status 'Feito' -Motivo 'cache de DNS limpo' }
    New-ResultadoOtimizar -Id 'dns' -Status 'Erro' -Motivo "ipconfig terminou com código $($r.Codigo)"
}

# Os arquivos ficam presos enquanto o Explorador roda: fecha, apaga (pelo núcleo) e abre de novo, mesmo se apagar falhar.
function Invoke-ReconstruirIcones {
    param([Parameter(Mandatory)][string]$PastaLocal)
    $liberado = [int64]0
    $pulados = @()
    [void](Invoke-TmdPrograma -Arquivo 'taskkill.exe' -Argumentos '/f /im explorer.exe' -Modulo 'otimizar' -Id 'icones')
    try {
        Start-Sleep -Milliseconds 800
        foreach ($f in Get-CacheIcones -PastaLocal $PastaLocal) {
            $r = Remove-TmdItem -Caminho $f.FullName -Raizes $f.DirectoryName -Modulo 'otimizar' -Id 'icones'
            $liberado += $r.Liberado
            if ($r.Status -ne 'Feito') { $pulados += $r.Motivo }
        }
    }
    finally {
        Start-Explorador
    }
    if ($pulados.Count -gt 0) { return New-ResultadoOtimizar -Id 'icones' -Status 'Parcial' -Motivo "$($pulados.Count) arquivo(s) não apagados ($($pulados[0])); reiniciar o computador resolve" -Liberado $liberado }
    New-ResultadoOtimizar -Id 'icones' -Status 'Feito' -Motivo 'o Windows recria o cache ao mostrar os ícones' -Liberado $liberado
}

function Get-CacheIcones {
    param([Parameter(Mandatory)][string]$PastaLocal)
    $antigo = Join-Path $PastaLocal 'IconCache.db'
    if (Test-Path -LiteralPath $antigo -PathType Leaf) { Get-Item -LiteralPath $antigo -Force }
    $pasta = Join-Path $PastaLocal 'Microsoft\Windows\Explorer'
    if (Test-Path -LiteralPath $pasta) {
        Get-ChildItem -LiteralPath $pasta -Force -File | Where-Object { $_.Name -like 'iconcache_*.db' }
    }
}

# Isolado para os testes não reabrirem o Explorador de verdade.
function Start-Explorador {
    if (-not (Get-Process -Name explorer -ErrorAction SilentlyContinue)) { Start-Process -FilePath 'explorer.exe' }
}

function Invoke-OtimizarUnidade {
    $r = Invoke-TmdPrograma -Arquivo 'defrag.exe' -Argumentos 'C: /O' -Modulo 'otimizar' -Id 'otimizar-c'
    if ($r.Codigo -eq 0) { return New-ResultadoOtimizar -Id 'otimizar-c' -Status 'Feito' -Motivo 'unidade C: otimizada' }
    New-ResultadoOtimizar -Id 'otimizar-c' -Status 'Erro' -Motivo "defrag terminou com código $($r.Codigo)"
}

function Invoke-LimparComponentes {
    $r = Invoke-TmdPrograma -Arquivo 'DISM.exe' -Argumentos '/Online /Cleanup-Image /StartComponentCleanup' -Modulo 'otimizar' -Id 'componentes'
    if ($r.Codigo -eq 0) { return New-ResultadoOtimizar -Id 'componentes' -Status 'Feito' -Motivo 'componentes antigos removidos' }
    New-ResultadoOtimizar -Id 'componentes' -Status 'Erro' -Motivo "DISM terminou com código $($r.Codigo)"
}

function New-ResultadoOtimizar {
    param([string]$Id, [string]$Status, [string]$Motivo = '', [string[]]$Mudancas = @(), [int64]$Liberado = 0)
    [pscustomobject]@{ Id = $Id; Status = $Status; Liberado = $Liberado; Motivo = $Motivo; Mudancas = $Mudancas }
}

Export-ModuleMember -Function Test-Requisitos, Find-Alvos, Invoke-Acao
