# Limpeza de temporários e relatórios de falha. Cada categoria vira um alvo.
# Quem apaga é o núcleo (Remove-TmdItem), sempre com a pasta da categoria como única raiz permitida.

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# As pastas vêm de variáveis de ambiente (TEMP/TMP, LOCALAPPDATA): os testes do programa inteiro trocam essas
# variáveis por pastas da sandbox. Nova categoria = nova entrada aqui + testes.
$script:Categorias = @(
    @{
        Id               = 'temp-usuario'
        Nome             = 'Temporários do usuário'
        Categoria        = 'Temporários'
        Pasta            = { [IO.Path]::GetTempPath() }
        IdadeMinimaHoras = 24
        Explicacao       = 'Arquivos temporários deixados por programas e instaladores. O que foi mexido nas últimas 24 horas fica, porque pode estar em uso.'
    }
    @{
        Id               = 'crashdumps'
        Nome             = 'Despejos de falha'
        Categoria        = 'Relatórios de falha'
        Pasta            = { Join-Path $env:LOCALAPPDATA 'CrashDumps' }
        IdadeMinimaHoras = 0
        Explicacao       = 'Cópias da memória de programas que travaram. Só servem para quem for investigar o travamento.'
    }
)

function Test-Requisitos {
    @{ Ok = $true; Motivo = '' }
}

# -Pastas troca a pasta de uma categoria (por Id). Usado pelos testes.
function Find-Alvos {
    param([hashtable]$Pastas = @{})

    foreach ($c in $script:Categorias) {
        $pasta = Resolve-PastaCategoria -Categoria $c -Pastas $Pastas
        $itens = Get-ItemElegivel -Pasta $pasta -IdadeMinimaHoras $c.IdadeMinimaHoras
        $bytes = [int64]0
        foreach ($i in $itens.Elegiveis) { $bytes += (Measure-TmdTamanho -Caminho $i.FullName).Bytes }

        $quantidade = $itens.Elegiveis.Count
        $detalhe = if (-not $itens.Existe) { 'pasta não existe' }
        elseif ($quantidade -eq 0) { 'nada para limpar' }
        else { "$(Format-TmdTamanho $bytes) em $(Format-Quantidade $quantidade)" }
        if ($itens.Recentes -gt 0) { $detalhe += " · $($itens.Recentes) recente(s) mantido(s)" }

        $mudancas = @("Apaga $(Format-Quantidade $quantidade) dentro de $pasta", $c.Explicacao)
        if ($itens.Links -gt 0) { $mudancas += "$($itens.Links) link(s) ignorado(s): o Tamanduá não segue links" }

        [pscustomobject]@{
            Id          = $c.Id
            Nome        = $c.Nome
            Categoria   = $c.Categoria
            Caminho     = $pasta
            Tamanho     = $bytes
            Estado      = 'NaoSeAplica'
            Detalhe     = $detalhe
            Nivel       = 'Normal'
            Valor       = $null
            Risco       = 'Baixo'
            Selecionado = $quantidade -gt 0
            Destino     = 'Permanente'
            RequerAdmin = $false
            Reversivel  = $false
            Mudancas    = $mudancas
        }
    }
}

# Não confia no Caminho dos alvos recebidos: a pasta é sempre a da categoria (ou a de -Pastas, nos testes).
function Invoke-Acao {
    param(
        [Parameter(Mandatory)][AllowEmptyCollection()][object[]]$Alvos,
        [switch]$Simular,
        [hashtable]$Pastas = @{}
    )

    foreach ($a in $Alvos) {
        $categoria = @($script:Categorias | Where-Object { $_.Id -eq $a.Id })
        if ($categoria.Count -eq 0) {
            [pscustomobject]@{ Id = $a.Id; Status = 'Erro'; Liberado = [int64]0; Itens = 0; Motivo = 'categoria desconhecida' }
            continue
        }
        $pasta = Resolve-PastaCategoria -Categoria $categoria[0] -Pastas $Pastas
        $itens = Get-ItemElegivel -Pasta $pasta -IdadeMinimaHoras $categoria[0].IdadeMinimaHoras
        $resultados = @(foreach ($i in $itens.Elegiveis) {
                Remove-TmdItem -Caminho $i.FullName -Raizes $pasta -Modulo 'limpar' -Id $a.Id -Simular:$Simular
            })
        Join-Resultado -Id $a.Id -Resultados $resultados -Simular $Simular
    }
}

function Resolve-PastaCategoria {
    param([Parameter(Mandatory)][hashtable]$Categoria, [hashtable]$Pastas)
    $pasta = if ($Pastas -and $Pastas.ContainsKey($Categoria.Id)) { $Pastas[$Categoria.Id] } else { & $Categoria.Pasta }
    [IO.Path]::GetFullPath($pasta).TrimEnd('\')
}

# Itens do primeiro nível da pasta que podem ser apagados: sem links e mais velhos que a idade mínima.
function Get-ItemElegivel {
    param([Parameter(Mandatory)][string]$Pasta, [int]$IdadeMinimaHoras)

    $saida = [pscustomobject]@{ Existe = $false; Elegiveis = @(); Recentes = 0; Links = 0 }
    $dir = New-Object IO.DirectoryInfo($Pasta)
    if (-not $dir.Exists) { return $saida }
    $saida.Existe = $true
    $limite = (Get-Date).AddHours(-$IdadeMinimaHoras)
    $elegiveis = [System.Collections.Generic.List[object]]::new()
    try {
        foreach ($i in $dir.EnumerateFileSystemInfos()) {
            if ($i.Attributes -band [IO.FileAttributes]::ReparsePoint) { $saida.Links++; continue }
            if ($IdadeMinimaHoras -gt 0 -and $i.LastWriteTime -gt $limite) { $saida.Recentes++; continue }
            $elegiveis.Add($i)
        }
    }
    catch {
        Write-Verbose "não foi possível listar $Pasta`: $($_.Exception.Message)"
    }
    $saida.Elegiveis = $elegiveis.ToArray()
    $saida
}

# Um resultado por categoria, somando os resultados de cada item.
function Join-Resultado {
    param([string]$Id, [object[]]$Resultados, [bool]$Simular)

    $liberado = [int64]0
    foreach ($r in $Resultados) { $liberado += $r.Liberado }
    $feitos = @($Resultados | Where-Object { $_.Status -in 'Feito', 'Simulado' -or $_.Motivo -eq 'não existe mais' })
    $parciais = @($Resultados | Where-Object { $_.Status -eq 'Parcial' })
    $erros = @($Resultados | Where-Object { $_.Status -eq 'Erro' })
    $pulados = $Resultados.Count - $feitos.Count

    $status = if ($Simular) { 'Simulado' }
    elseif ($pulados -eq 0) { 'Feito' }
    elseif ($feitos.Count + $parciais.Count -gt 0) { 'Parcial' }
    elseif ($erros.Count -gt 0) { 'Erro' }
    else { 'Ignorado' }

    $motivo = ''
    if ($pulados -gt 0) {
        $exemplo = @($Resultados | Where-Object { $_.Status -notin 'Feito', 'Simulado' -and $_.Motivo -ne 'não existe mais' })[0].Motivo
        $motivo = "$pulados pulado(s) (ex.: $exemplo)"
    }
    [pscustomobject]@{ Id = $Id; Status = $status; Liberado = $liberado; Itens = $Resultados.Count; Motivo = $motivo }
}

function Format-Quantidade {
    param([int]$Quantidade)
    if ($Quantidade -eq 1) { return '1 item' }
    '{0:N0} itens' -f $Quantidade
}

Export-ModuleMember -Function Test-Requisitos, Find-Alvos, Invoke-Acao
