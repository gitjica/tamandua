# O que ocupa espaço no disco. Só lê.
# Sem -Caminho: ponto de partida (unidades e atalhos, instantâneo). Com -Caminho: o conteúdo da pasta, do maior para o menor.
# Itens com Navegavel = $true podem ser abertos (duplo clique na interface, "tamandua analisar <pasta>" na CLI).

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Acima disso, o resto vira uma linha "outros N itens".
$script:LimiteItens = 40

function Test-Requisitos {
    @{ Ok = $true; Motivo = '' }
}

function Find-Alvos {
    param([string]$Caminho)
    if (-not $Caminho) { return Get-Inicio }
    Get-ConteudoPasta -Caminho $Caminho
}

function Get-Inicio {
    foreach ($d in [IO.DriveInfo]::GetDrives()) {
        if ($d.DriveType -ne 'Fixed' -or -not $d.IsReady -or $d.TotalSize -le 0) { continue }
        $usado = $d.TotalSize - $d.TotalFreeSpace
        $rotulo = if ($d.VolumeLabel) { " ($($d.VolumeLabel))" } else { '' }
        New-ItemAnalise -Id "unidade-$($d.Name.Substring(0, 1).ToLowerInvariant())" -Nome "Disco $($d.Name.TrimEnd('\'))$rotulo" `
            -Categoria 'Unidades' -Caminho $d.RootDirectory.FullName -Tamanho $usado `
            -Detalhe "$(Format-TmdTamanho $usado) usados de $(Format-TmdTamanho $d.TotalSize) · abrir mede tudo (pode demorar)" `
            -Valor ([int][Math]::Round(100 * $usado / $d.TotalSize)) -Navegavel
    }
    $perfil = [Environment]::GetFolderPath('UserProfile')
    $atalhos = @(
        @{ Id = 'atalho-perfil'; Nome = 'Sua pasta de usuário'; Caminho = $perfil }
        @{ Id = 'atalho-downloads'; Nome = 'Downloads'; Caminho = Join-Path $perfil 'Downloads' }
        @{ Id = 'atalho-local'; Nome = 'AppData\Local (dados e caches de programas)'; Caminho = [Environment]::GetFolderPath('LocalApplicationData') }
        @{ Id = 'atalho-temp'; Nome = 'Temporários'; Caminho = [IO.Path]::GetTempPath().TrimEnd('\') }
    )
    foreach ($a in $atalhos) {
        if (-not (Test-Path -LiteralPath $a.Caminho)) { continue }
        New-ItemAnalise -Id $a.Id -Nome $a.Nome -Categoria 'Atalhos' -Caminho $a.Caminho -Tamanho -1 -Detalhe $a.Caminho -Navegavel
    }
}

function Get-ConteudoPasta {
    param([Parameter(Mandatory)][string]$Caminho)

    $pasta = New-Object IO.DirectoryInfo ([IO.Path]::GetFullPath($Caminho))
    if (-not $pasta.Exists) { throw "pasta não encontrada: $Caminho" }
    try { $itens = @($pasta.GetFileSystemInfos()) }
    catch { throw "sem acesso a $($pasta.FullName)" }

    $medidas = @(foreach ($i in $itens) {
            $link = [bool]($i.Attributes -band [IO.FileAttributes]::ReparsePoint)
            if ($link) { [pscustomobject]@{ Item = $i; Bytes = [int64]0; Arquivos = 0; Inacessiveis = 0; Link = $true }; continue }
            if ($i -is [IO.DirectoryInfo]) {
                $m = Measure-TmdTamanho -Caminho $i.FullName
                [pscustomobject]@{ Item = $i; Bytes = [int64]$m.Bytes; Arquivos = $m.Arquivos; Inacessiveis = $m.Inacessiveis; Link = $false }
            }
            else { [pscustomobject]@{ Item = $i; Bytes = [int64]$i.Length; Arquivos = 1; Inacessiveis = 0; Link = $false } }
        })
    $total = [int64]0
    $semAcesso = 0
    foreach ($m in $medidas) { $total += $m.Bytes; $semAcesso += $m.Inacessiveis }

    if ($pasta.Parent) {
        New-ItemAnalise -Id 'acima' -Nome '.. (pasta acima)' -Categoria 'Navegação' -Caminho $pasta.Parent.FullName `
            -Tamanho -1 -Detalhe $pasta.Parent.FullName -Navegavel
    }
    $detalheTotal = "$(Format-TmdTamanho $total) em $($medidas.Count) item(ns)"
    $nivelTotal = 'Normal'
    if ($semAcesso -gt 0) {
        $detalheTotal += " · $semAcesso pasta(s) sem acesso: o total real pode ser maior"
        $nivelTotal = 'Atencao'
    }
    New-ItemAnalise -Id 'total' -Nome $pasta.FullName -Categoria 'Resumo' -Caminho $pasta.FullName -Tamanho $total -Detalhe $detalheTotal -Nivel $nivelTotal

    $ordenados = @($medidas | Sort-Object Bytes -Descending)
    $mostrar = @($ordenados | Select-Object -First $script:LimiteItens)
    foreach ($m in $mostrar) {
        $i = $m.Item
        $ehPasta = $i -is [IO.DirectoryInfo]
        $porcento = if ($total -gt 0) { [int][Math]::Round(100 * $m.Bytes / $total) } else { 0 }
        $detalhe = if ($m.Link) { 'link (o Tamanduá não entra em links)' }
        elseif ($ehPasta) {
            $d = "$(Format-TmdTamanho $m.Bytes) · $porcento% · $('{0:N0}' -f $m.Arquivos) arquivo(s)"
            if ($m.Inacessiveis -gt 0) { $d += " · $($m.Inacessiveis) sem acesso" }
            $d
        }
        else { "$(Format-TmdTamanho $m.Bytes) · $porcento% · modificado em $($i.LastWriteTime.ToString('dd/MM/yyyy'))" }
        $nome = if ($ehPasta) { "$($i.Name)\" } else { $i.Name }
        New-ItemAnalise -Id "item:$($i.Name.ToLowerInvariant())" -Nome $nome -Categoria 'Conteúdo, do maior para o menor' `
            -Caminho $i.FullName -Tamanho $m.Bytes -Detalhe $detalhe -Valor $(if ($m.Link) { $null } else { $porcento }) `
            -Navegavel:($ehPasta -and -not $m.Link)
    }
    $resto = @($ordenados | Select-Object -Skip $script:LimiteItens)
    if ($resto.Count -gt 0) {
        $bytes = [int64]0
        foreach ($m in $resto) { $bytes += $m.Bytes }
        New-ItemAnalise -Id 'outros' -Nome "outros $($resto.Count) item(ns)" -Categoria 'Conteúdo, do maior para o menor' `
            -Caminho '' -Tamanho $bytes -Detalhe "$(Format-TmdTamanho $bytes) somados"
    }
}

function New-ItemAnalise {
    param(
        [string]$Id, [string]$Nome, [string]$Categoria, [string]$Caminho, [int64]$Tamanho = -1, [string]$Detalhe = '',
        $Valor = $null, [string]$Nivel = 'Normal', [switch]$Navegavel
    )
    [pscustomobject]@{
        Id        = $Id
        Nome      = $Nome
        Categoria = $Categoria
        Caminho   = $Caminho
        Tamanho   = $Tamanho
        Estado    = 'NaoSeAplica'
        Detalhe   = $Detalhe
        Nivel     = $Nivel
        Valor     = $Valor
        Navegavel = $Navegavel.IsPresent
    }
}

Export-ModuleMember -Function Test-Requisitos, Find-Alvos
