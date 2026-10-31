# Recursos opcionais do Windows ("Ativar ou desativar recursos do Windows"). Marcar um item inverte o estado dele:
# o que está desligado é ligado, o que está ligado é desligado. Estado lido sem admin (CIM); mudança pelo DISM, elevada.

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Nome do recurso no Windows -> como aparece aqui. Ordem = ordem na tela.
$script:Recursos = [ordered]@{
    'Microsoft-Windows-Subsystem-Linux' = @{ Id = 'wsl'; Nome = 'Subsistema do Windows para Linux (WSL)'; Categoria = 'Desenvolvimento e virtualização'; Risco = 'Baixo'
        Explicacao = 'Roda Linux dentro do Windows. Para o WSL 2, ligue também a Plataforma de Máquina Virtual.' }
    'VirtualMachinePlatform'            = @{ Id = 'plataforma-vm'; Nome = 'Plataforma de Máquina Virtual'; Categoria = 'Desenvolvimento e virtualização'; Risco = 'Baixo'
        Explicacao = 'Base de virtualização usada pelo WSL 2 e pelo Android para Windows.' }
    'HypervisorPlatform'                = @{ Id = 'plataforma-hipervisor'; Nome = 'Plataforma do Hipervisor do Windows'; Categoria = 'Desenvolvimento e virtualização'; Risco = 'Baixo'
        Explicacao = 'Deixa VirtualBox, VMware e emuladores usarem o hipervisor do Windows.' }
    'Microsoft-Hyper-V-All'             = @{ Id = 'hyper-v'; Nome = 'Hyper-V'; Categoria = 'Desenvolvimento e virtualização'; Risco = 'Medio'
        Explicacao = 'Máquinas virtuais da Microsoft. Pode deixar outros programas de virtualização mais lentos.' }
    'Containers-DisposableClientVM'     = @{ Id = 'sandbox'; Nome = 'Área Restrita do Windows (Sandbox)'; Categoria = 'Desenvolvimento e virtualização'; Risco = 'Baixo'
        Explicacao = 'Um Windows descartável para testar programas suspeitos: tudo some ao fechar.' }
    'NetFx3'                            = @{ Id = 'dotnet35'; Nome = '.NET Framework 3.5'; Categoria = 'Compatibilidade'; Risco = 'Baixo'
        Explicacao = 'Exigido por programas e jogos antigos. Ligar baixa os arquivos pelo Windows Update.' }
    'ServicesForNFS-ClientOnly'         = @{ Id = 'nfs'; Nome = 'Cliente NFS'; Categoria = 'Rede'; Risco = 'Baixo'
        Explicacao = 'Acessa pastas compartilhadas de servidores Linux/NAS por NFS.' }
    'TelnetClient'                      = @{ Id = 'telnet'; Nome = 'Cliente Telnet'; Categoria = 'Rede'; Risco = 'Baixo'
        Explicacao = 'Comando telnet, útil para testar se uma porta de rede responde.' }
    'TFTP'                              = @{ Id = 'tftp'; Nome = 'Cliente TFTP'; Categoria = 'Rede'; Risco = 'Baixo'
        Explicacao = 'Comando tftp, usado para atualizar roteadores e aparelhos de rede.' }
    'SMB1Protocol'                      = @{ Id = 'smb1'; Nome = 'Compartilhamento SMB 1.0 (antigo)'; Categoria = 'Rede'; Risco = 'Alto'
        Explicacao = 'Protocolo antigo e inseguro (usado por ataques como o WannaCry). Só ligue se um aparelho muito antigo exigir; deixe desligado no resto do tempo.' }
    'MediaPlayback'                     = @{ Id = 'midia'; Nome = 'Recursos de Mídia'; Categoria = 'Mídia e impressão'; Risco = 'Medio'
        Explicacao = 'Windows Media Player legado e codecs usados por alguns programas. Desligar pode quebrar programas que tocam vídeo.' }
    'Printing-PDFServices-Features'     = @{ Id = 'imprimir-pdf'; Nome = 'Microsoft Print to PDF'; Categoria = 'Mídia e impressão'; Risco = 'Baixo'
        Explicacao = 'Impressora virtual que salva qualquer coisa como PDF.' }
    'Printing-XPSServices-Features'     = @{ Id = 'xps'; Nome = 'Gravador de Documentos XPS'; Categoria = 'Mídia e impressão'; Risco = 'Baixo'
        Explicacao = 'Impressora virtual de XPS (formato pouco usado hoje).' }
}

# Só confere o DISM: ler os recursos de verdade leva ~2 s (Win32_OptionalFeature) e fica para quando a página abrir.
function Test-Requisitos {
    if (Test-Path -LiteralPath (Join-Path $env:SystemRoot 'System32\Dism.exe') -PathType Leaf) { return @{ Ok = $true; Motivo = '' } }
    @{ Ok = $false; Motivo = 'DISM não encontrado: esta instalação do Windows não permite ligar ou desligar recursos.' }
}

# Nome do recurso -> 'ligado' | 'desligado'. Recursos que não existem nesta edição não aparecem. Só leitura, sem admin.
# -Rapido (para mostrar a página): lê do registro do Windows (CBS\Notifications\OptionalFeatures, Selection 1/0), ~0,1 s
# contra ~2,4 s do Win32_OptionalFeature; sem essa chave, cai no CIM. Ligar e desligar sempre decidem pelo CIM.
function Get-EstadoRecurso {
    param([switch]$Rapido)
    if ($Rapido) {
        $chave = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\Notifications\OptionalFeatures'
        $mapa = @{}
        foreach ($k in @(Get-ChildItem -LiteralPath $chave -ErrorAction SilentlyContinue)) {
            $selecao = (Get-ItemProperty -LiteralPath $k.PSPath -ErrorAction SilentlyContinue).PSObject.Properties['Selection']
            if ($selecao) { $mapa[$k.PSChildName] = if ([int]$selecao.Value -eq 1) { 'ligado' } else { 'desligado' } }
        }
        if ($mapa.Count -gt 0) { return $mapa }
    }
    $mapa = @{}
    foreach ($f in Get-CimInstance -ClassName Win32_OptionalFeature) {
        $mapa[[string]$f.Name] = switch ([int]$f.InstallState) { 1 { 'ligado' } 2 { 'desligado' } default { 'outro' } }
    }
    $mapa
}

function Find-Alvos {
    $estados = Get-EstadoRecurso -Rapido
    foreach ($nome in $script:Recursos.Keys) {
        $r = $script:Recursos[$nome]
        $existe = $estados.ContainsKey($nome) -and $estados[$nome] -ne 'outro'
        $ligado = $existe -and $estados[$nome] -eq 'ligado'
        $estado = if (-not $existe) { 'Desconhecido' } elseif ($ligado) { 'Aplicado' } else { 'NaoAplicado' }
        $selo = if (-not $existe) { 'não existe nesta edição' } elseif ($ligado) { 'ligado' } else { 'desligado' }
        $mudanca = if (-not $existe) { 'Não existe nesta edição do Windows.' } elseif ($ligado) { "Desliga: dism /Online /Disable-Feature /FeatureName:$nome" } else { "Liga: dism /Online /Enable-Feature /FeatureName:$nome /All" }
        [pscustomobject]@{
            Id = $r.Id; Nome = $r.Nome; Categoria = $r.Categoria; Caminho = ''; Tamanho = [int64]0
            Estado = $estado; Selo = $selo; Detalhe = $r.Explicacao; Nivel = 'Normal'; Valor = $null; Risco = $r.Risco
            Selecionado = $false; Selecionavel = $existe; Destino = 'NaoSeAplica'; RequerAdmin = $true; Reversivel = $null
            Mudancas = @($mudanca, 'Para voltar, marque de novo e execute: o estado se inverte.')
        }
    }
}

# Decide ligar ou desligar pelo estado lido AGORA (não pelo que veio no alvo) e chama o DISM pelo núcleo.
function Invoke-Acao {
    param([Parameter(Mandatory)][AllowEmptyCollection()][object[]]$Alvos, [switch]$Simular)

    $estados = Get-EstadoRecurso
    foreach ($a in $Alvos) {
        $id = [string]$a.Id
        $nome = @($script:Recursos.Keys | Where-Object { $script:Recursos[$_].Id -eq $id })
        if ($nome.Count -eq 0) { New-ResultadoRecurso -Id $id -Status 'Erro' -Motivo 'recurso fora do catálogo'; continue }
        $nome = $nome[0]
        if (-not $estados.ContainsKey($nome) -or $estados[$nome] -eq 'outro') { New-ResultadoRecurso -Id $id -Status 'Ignorado' -Motivo 'não existe nesta edição do Windows'; continue }
        $ligar = $estados[$nome] -ne 'ligado'
        $argumentos = if ($ligar) { "/Online /Enable-Feature /FeatureName:$nome /All /NoRestart /Quiet" } else { "/Online /Disable-Feature /FeatureName:$nome /NoRestart /Quiet" }
        $verbo = if ($ligar) { 'ligar' } else { 'desligar' }
        if ($Simular) { New-ResultadoRecurso -Id $id -Status 'Simulado' -Mudancas @("$($verbo): dism $argumentos"); continue }

        $r = Invoke-TmdPrograma -Arquivo 'dism.exe' -Argumentos $argumentos -Modulo 'recursos' -Id $id
        switch ($r.Codigo) {
            0 { New-ResultadoRecurso -Id $id -Status 'Feito' -Motivo "$($script:Recursos[$nome].Nome): $(if ($ligar) { 'ligado' } else { 'desligado' })" }
            3010 { New-ResultadoRecurso -Id $id -Status 'Feito' -Motivo "$(if ($ligar) { 'ligado' } else { 'desligado' }); reinicie o computador para terminar" }
            default {
                $dica = if ($ligar -and $nome -eq 'NetFx3') { ' (o .NET 3.5 precisa de internet para baixar)' } else { '' }
                New-ResultadoRecurso -Id $id -Status 'Erro' -Motivo "não deu para $verbo (DISM código $($r.Codigo))$dica"
            }
        }
    }
}

function New-ResultadoRecurso {
    param([string]$Id, [string]$Status, [string]$Motivo = '', [string[]]$Mudancas = @())
    [pscustomobject]@{ Id = $Id; Status = $Status; Liberado = [int64]0; Motivo = $Motivo; Mudancas = $Mudancas }
}

Export-ModuleMember -Function Test-Requisitos, Find-Alvos, Invoke-Acao
