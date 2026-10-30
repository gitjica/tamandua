# Leitura das páginas do FMHY (github.com/fmhy/edit, docs/*.md). Ferramenta de desenvolvimento: usada pelos geradores.
#
# Formato de uma linha:  * ⭐ **[Nome](link)** / [GitHub](l2), [Outro](l3) or [Mais](l4) - Descrição / [Fix](l5)
#   - Antes do primeiro " - " ficam as ENTRADAS, separadas por ", " ou " or "; o primeiro link de cada uma é o programa.
#   - Links depois de " / " são do mesmo programa (GitHub, Discord, Subreddit...), não são programas.
#   - ⭐ no começo vale só para a primeira entrada, e só se ela estiver em negrito.
#   - Títulos "# ►" e "## ▷" dão a seção.

function ConvertTo-FmhySimples([string]$Texto) {
    ($Texto.ToLowerInvariant() -replace '[^a-z0-9]', '')
}

function Get-FmhyHost([string]$Url) {
    try { (([uri]$Url).Host -replace '^www\.', '').ToLowerInvariant() } catch { '' }
}

# Formas de comparar um nome: inteiro, sem o "(...)" do fim e sem sufixos genéricos ("Brave Browser" = "Brave").
function Get-FmhyFormasNome([string]$Nome) {
    $base = $Nome -replace '\s*\(.*\)$', ''
    $sem = $base -replace '(?i)\s+(browser|desktop|app|client|media server|server|for windows|launcher)$', ''
    @($Nome, $base, $sem) | ForEach-Object { ConvertTo-FmhySimples $_ } | Where-Object { $_.Length -ge 2 } | Select-Object -Unique
}

# Índice nome simplificado -> entradas. Ficam de fora: unsafe.md e links codificados do FMHY (rentry FMHYB64), que
# apontam para versões crackeadas; o Tamanduá só instala o programa oficial.
function New-FmhyIndice {
    param([Parameter(Mandatory)][object[]]$Entradas)
    $indice = @{}
    foreach ($x in $Entradas) {
        if ($x.Inseguro -or $x.Url -match 'rentry\.(co|org)/FMHYB64') { continue }
        foreach ($f in Get-FmhyFormasNome $x.Nome) {
            if (-not $indice.ContainsKey($f)) { $indice[$f] = [System.Collections.Generic.List[object]]::new() }
            $indice[$f].Add($x)
        }
    }
    $indice
}

# Um programa no FMHY: Achou, Estrela e onde. A estrela só conta se o link estrelado for do mesmo site do programa
# (o "Plex" com ⭐ é o site de streaming, não o servidor) ou se o programa não tiver site.
function Find-FmhyPrograma {
    param([Parameter(Mandatory)][hashtable]$Indice, [string[]]$Nomes, [string]$Site)
    # Sem Select-Object -Unique: ele compara objetos pelo texto e jogava fora a entrada com estrela.
    $hits = @(foreach ($n in $Nomes) { foreach ($f in Get-FmhyFormasNome $n) { if ($Indice.ContainsKey($f)) { $Indice[$f] } } })
    $host1 = Get-FmhyHost $Site
    # Domínio principal ("download.krita.org" -> "krita.org").
    $base = { param($h) $p = @($h -split '\.'); if ($p.Count -ge 2) { $p[($p.Count - 2)..($p.Count - 1)] -join '.' } else { $h } }
    $estrelas = @($hits | Where-Object { $_.Estrela -and (-not $host1 -or (& $base (Get-FmhyHost $_.Url)) -eq (& $base $host1) -or (Get-FmhyHost $_.Url) -eq 'github.com') })
    [pscustomobject]@{
        Achou = $hits.Count -gt 0; Estrela = $estrelas.Count -gt 0
        Onde = (@($hits | ForEach-Object { if ($_.Sub) { "$($_.Pagina) / $($_.Sub)" } else { $_.Pagina } } | Select-Object -Unique) -join '; ')
    }
}

function Read-FmhyEntradas {
    param([Parameter(Mandatory)][string]$Pasta)
    $estrela = [string][char]0x2B50
    foreach ($f in Get-ChildItem -LiteralPath $Pasta -Filter '*.md') {
        $secao = ''; $sub = ''
        foreach ($linha in [IO.File]::ReadAllLines($f.FullName, [Text.Encoding]::UTF8)) {
            if ($linha -match '^#\s*\S*\s*(.+)$' -and $linha -notmatch '^##') { $secao = $Matches[1].Trim(); $sub = ''; continue }
            if ($linha -match '^##+\s*\S*\s*(.+)$') { $sub = $Matches[1].Trim(); continue }
            if ($linha -notmatch '^\s*\*\s') { continue }
            $corpo = $linha -replace '^\s*\*\s*', ''
            $comEstrela = $corpo.StartsWith($estrela)
            if ($comEstrela) { $corpo = $corpo.Substring($estrela.Length).TrimStart() }
            # Separador da descrição: " - " fora de colchetes/parênteses.
            $prof = 0; $fim = $corpo.Length
            for ($i = 0; $i -lt $corpo.Length - 2; $i++) {
                $ch = $corpo[$i]
                if ($ch -eq '[' -or $ch -eq '(') { $prof++ } elseif ($ch -eq ']' -or $ch -eq ')') { $prof-- }
                elseif ($prof -le 0 -and $corpo.Substring($i, 3) -eq ' - ') { $fim = $i; break }
            }
            $cabeca = $corpo.Substring(0, $fim)
            $descricao = if ($fim -lt $corpo.Length) { $corpo.Substring($fim + 3).Trim() } else { '' }
            $segmentos = [regex]::Split($cabeca, ',\s+(?![^\[]*\])|\s+or\s+(?![^\[]*\])')
            $primeira = $true
            foreach ($s in $segmentos) {
                # Só a parte antes do primeiro " / " é a entrada; o resto são links do mesmo programa.
                $principal = ($s -split '\s+/\s+', 2)[0]
                $m = [regex]::Match($principal, '(\*\*)?\[([^\]]+)\]\((https?://[^)\s]+)\)')
                if (-not $m.Success) { $primeira = $false; continue }
                $nome = ($m.Groups[2].Value -replace [char]0x2060, '').Trim()
                [pscustomobject]@{
                    Nome = $nome; Simples = ConvertTo-FmhySimples $nome; Url = $m.Groups[3].Value
                    Estrela = $comEstrela -and $primeira -and $m.Groups[1].Success
                    Pagina = $f.BaseName; Secao = $secao; Sub = $sub; Descricao = $descricao
                    Inseguro = $f.BaseName -eq 'unsafe'
                }
                $primeira = $false
            }
        }
    }
}
