# Fonte do sistema: troca a Segoe UI por qualquer fonte instalada (o jeito do SyrianSegoe e do Set-SystemFont da pasta
# Fonte). Gera cópias da fonte escolhida com a tabela de nomes (e as métricas de linha) da Segoe UI; o núcleo põe as
# cópias em Windows\Fonts e um ajuste de registro aponta cada peso da Segoe UI para elas. Os arquivos da Segoe UI nunca
# mudam: voltar é só apontar o registro de novo (Histórico > Desfazer, ou "Segoe UI original" aqui).

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$script:ChaveFontes = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Fonts'

# Valor do registro -> arquivo original da Segoe UI, peso e itálico do lugar que a fonte escolhida ocupa.
$script:Vagas = [ordered]@{
    'Segoe UI (TrueType)'                  = @('segoeui', 400, $false)
    'Segoe UI Bold (TrueType)'             = @('segoeuib', 700, $false)
    'Segoe UI Italic (TrueType)'           = @('segoeuii', 400, $true)
    'Segoe UI Bold Italic (TrueType)'      = @('segoeuiz', 700, $true)
    'Segoe UI Light (TrueType)'            = @('segoeuil', 300, $false)
    'Segoe UI Light Italic (TrueType)'     = @('seguili', 300, $true)
    'Segoe UI Semilight (TrueType)'        = @('segoeuisl', 350, $false)
    'Segoe UI Semilight Italic (TrueType)' = @('seguisli', 350, $true)
    'Segoe UI Semibold (TrueType)'         = @('seguisb', 600, $false)
    'Segoe UI Semibold Italic (TrueType)'  = @('seguisbi', 600, $true)
    'Segoe UI Black (TrueType)'            = @('seguibl', 900, $false)
    'Segoe UI Black Italic (TrueType)'     = @('seguibli', 900, $true)
    # A do Windows 11 (barra de tarefas, Configurações, apps novos): todas as instâncias dela usam a Regular.
    'Segoe UI Variable (TrueType)'         = @('SegUIVar', 400, $false)
}

$script:Tamanhos = [ordered]@{
    'tam-auto' = 'Automático (mesmo tamanho aparente da Segoe UI)'
    'tam-90'   = '90%'
    'tam-95'   = '95%'
    'tam-100'  = '100% (o desenho original da fonte)'
    'tam-105'  = '105%'
    'tam-110'  = '110%'
}

# Palavras de estilo no fim do nome do registro ("Inter Semi Bold Italic (TrueType)" -> família "Inter").
$script:PalavrasEstilo = @('thin', 'hairline', 'extralight', 'ultralight', 'light', 'semilight', 'demilight', 'book', 'regular',
    'normal', 'medium', 'semibold', 'demibold', 'bold', 'extrabold', 'ultrabold', 'heavy', 'black', 'extrablack', 'ultrablack',
    'italic', 'oblique', 'extra', 'ultra', 'semi', 'demi')
# Ícones e símbolos (não têm letras) e a própria Segoe.
$script:FamiliasFora = '^(Segoe|Marlett|Wingdings|Webdings|Symbol|OpenSymbol|MT Extra|HoloLens|Bookshelf Symbol|Sans Serif Collection)'

function Test-Requisitos {
    if (-not [IO.File]::Exists((Join-Path (Get-PastaFontes) 'segoeui.ttf'))) {
        return @{ Ok = $false; Motivo = 'A Segoe UI original (segoeui.ttf) não está na pasta de fontes do Windows.' }
    }
    @{ Ok = $true; Motivo = '' }
}

# Testes: TAMANDUA_REGISTRO_TESTE redireciona o registro (só em HKCU:\Software\TamanduaTestes) e TAMANDUA_FONTES_TESTE
# troca a pasta de fontes.
function Get-RaizRegistroPadrao {
    $r = $env:TAMANDUA_REGISTRO_TESTE
    if ($r -and $r -like 'HKCU:\Software\TamanduaTestes\*') { return $r }
    ''
}

function Get-PastaFontes {
    if ($env:TAMANDUA_FONTES_TESTE) { return $env:TAMANDUA_FONTES_TESTE }
    Join-Path $env:WINDIR 'Fonts'
}

# ---------- Leitura (só leitura; na área de testes, dentro da chave de teste) ----------

function Open-ChaveFontes {
    param([ValidateSet('HKLM', 'HKCU')][string]$Hive, [string]$RaizRegistro)
    $sub = 'SOFTWARE\Microsoft\Windows NT\CurrentVersion\Fonts'
    if ($RaizRegistro) {
        $base = [Microsoft.Win32.RegistryKey]::OpenBaseKey('CurrentUser', 'Registry64')
        $sub = ($RaizRegistro -replace '^HKCU:\\', '') + "\$Hive\$sub"
    }
    else { $base = [Microsoft.Win32.RegistryKey]::OpenBaseKey($(if ($Hive -eq 'HKLM') { 'LocalMachine' } else { 'CurrentUser' }), 'Registry64') }
    try { $base.OpenSubKey($sub, $false) } finally { $base.Close() }
}

# Fontes registradas (da máquina e do usuário): nome no registro, valor e arquivo com caminho completo.
function Get-FontesRegistradas {
    param([string]$RaizRegistro, [string]$PastaFontes)
    foreach ($hive in 'HKLM', 'HKCU') {
        $k = Open-ChaveFontes -Hive $hive -RaizRegistro $RaizRegistro
        if (-not $k) { continue }
        try {
            foreach ($n in $k.GetValueNames()) {
                $v = [string]$k.GetValue($n, '')
                if (-not $v) { continue }
                $arquivo = if ([IO.Path]::IsPathRooted($v)) { $v } else { Join-Path $PastaFontes $v }
                [pscustomobject]@{ Nome = $n; Valor = $v; Arquivo = $arquivo; Hive = $hive }
            }
        }
        finally { $k.Close() }
    }
}

function Get-NomeFamilia {
    param([string]$NomeRegistro)
    $n = ($NomeRegistro -replace '\s*\((TrueType|OpenType)\)\s*$', '').Trim()
    $partes = [System.Collections.Generic.List[string]]::new()
    foreach ($p in ($n -split '\s+')) { if ($p) { $partes.Add($p) } }
    # "Rubik-BoldItalic": o estilo vem colado por hífen, em CamelCase.
    if ($partes.Count -gt 0 -and $partes[$partes.Count - 1] -match '^(.+)-([A-Za-z]+)$') {
        $base, $colado = $Matches[1], $Matches[2]
        $palavras = @([regex]::Split($colado, '(?<=[a-z])(?=[A-Z])'))
        if (@($palavras | Where-Object { $script:PalavrasEstilo -notcontains $_.ToLowerInvariant() }).Count -eq 0) {
            $partes[$partes.Count - 1] = $base
            foreach ($p in $palavras) { $partes.Add($p) }
        }
    }
    $estilo = [System.Collections.Generic.List[string]]::new()
    while ($partes.Count -gt 1 -and $script:PalavrasEstilo -contains $partes[$partes.Count - 1].ToLowerInvariant()) {
        $estilo.Insert(0, $partes[$partes.Count - 1])
        $partes.RemoveAt($partes.Count - 1)
    }
    [pscustomobject]@{ Familia = ($partes -join ' '); Estilo = $(if ($estilo.Count -gt 0) { $estilo -join ' ' } else { 'Regular' }) }
}

# Famílias instaladas (.ttf/.otf; coleções .ttc e fontes de bitmap ficam de fora), agrupadas pelo nome do registro.
# O peso de verdade de cada arquivo só é lido ao aplicar (ler todos os arquivos de fonte demoraria).
function Get-FamiliasInstaladas {
    param([string]$RaizRegistro = (Get-RaizRegistroPadrao), [string]$PastaFontes = (Get-PastaFontes))
    $familias = @{}
    foreach ($f in Get-FontesRegistradas -RaizRegistro $RaizRegistro -PastaFontes $PastaFontes) {
        if ([IO.Path]::GetExtension($f.Arquivo).ToLowerInvariant() -notin '.ttf', '.otf') { continue }
        if ($f.Nome -match '&' -or $f.Nome -like '@*') { continue }
        if (Test-TmdNomeCopiaFonte -Nome ([IO.Path]::GetFileName($f.Arquivo))) { continue }
        $nf = Get-NomeFamilia -NomeRegistro $f.Nome
        if (-not $nf.Familia -or $nf.Familia -match $script:FamiliasFora) { continue }
        $chave = ConvertTo-TmdNomeSimples $nf.Familia
        if (-not $chave -or -not [IO.File]::Exists($f.Arquivo)) { continue }
        if (-not $familias.ContainsKey($chave)) {
            $familias[$chave] = [pscustomobject]@{ Id = "fam-$chave"; Nome = $nf.Familia; Estilos = [System.Collections.Generic.List[string]]::new(); Arquivos = [System.Collections.Generic.List[string]]::new() }
        }
        $fam = $familias[$chave]
        if ($fam.Arquivos -notcontains $f.Arquivo) { $fam.Arquivos.Add($f.Arquivo); $fam.Estilos.Add($nf.Estilo) }
    }
    # Sem um estilo normal (reto e não negrito) não dá para ocupar a Regular. Ex.: a Cambria, cuja Regular fica numa coleção .ttc.
    $familias.Values | Where-Object { @($_.Estilos | Where-Object { $_ -notmatch 'Bold|Black|Heavy|Italic|Oblique' }).Count -gt 0 } | Sort-Object Nome
}

# Peso, largura e itálico de cada arquivo, lidos de dentro dele (OS/2 e head). Arquivo ilegível fica de fora.
function Get-EstilosArquivos {
    param([string[]]$Arquivos)
    foreach ($a in $Arquivos | Select-Object -Unique) {
        try { $s = [Sfnt]::Load($a) } catch { continue }
        if (-not $s.Has('OS/2') -or -not $s.Has('head') -or -not $s.Has('cmap')) { continue }
        $os2 = $s.Get('OS/2')
        $italico = ([Sfnt]::U16($os2, 62) -band 1) -ne 0 -or ([Sfnt]::U16($s.Get('head'), 44) -band 2) -ne 0
        [pscustomobject]@{ Arquivo = $a; Peso = [int][Sfnt]::U16($os2, 4); Largura = [int][Sfnt]::U16($os2, 6); Italico = $italico }
    }
}

# O arquivo da família que ocupa uma vaga: largura normal primeiro (nada de Condensed no lugar da Regular), depois o
# itálico certo (se a família tiver itálico) e o peso mais perto. Só Regular e Bold: Light e Semilight ficam com a
# Regular, Semibold e Black com a Bold.
function Select-ArquivoVaga {
    param([Parameter(Mandatory)][object[]]$Estilos, [int]$Peso, [bool]$Italico)
    $querItalico = $Italico -and @($Estilos | Where-Object Italico).Count -gt 0
    $candidatos = @($Estilos | Where-Object { $_.Italico -eq $querItalico })
    if ($candidatos.Count -eq 0) { $candidatos = @($Estilos) }
    $alvo = $Peso
    @($candidatos | Sort-Object @{ Expression = { [math]::Abs($_.Largura - 5) } }, @{ Expression = { [math]::Abs($_.Peso - $alvo) } }, Peso)[0]
}

# Altura média de "x" e "H" em fração do em; $null se a fonte não tiver essas letras.
function Get-AlturaLetras {
    param([Parameter(Mandatory)]$Fonte)
    $alturas = foreach ($c in 120, 72) {
        $g = $Fonte.CodepointGlyph($c)
        if ($g -lt 0) { return $null }
        $b = $Fonte.Bounds($g)
        if (-not $b) { return $null }
        $b[3]
    }
    ($alturas[0] + $alturas[1]) / 2 / $Fonte.Upm
}

# "Automático": metade do caminho entre o desenho original (100%) e a mesma altura de letra da Segoe UI. Igualar tudo
# encolhe demais fontes de letra grande (a OpenDyslexic iria a 94%; ajustada a olho, ficou em 97,6%; isto dá 97%).
function Get-TamanhoAutomatico {
    param([Parameter(Mandatory)][string]$Regular, [Parameter(Mandatory)][string]$Segoe)
    $a = Get-AlturaLetras ([TtFont]::Load($Regular))
    $s = Get-AlturaLetras ([TtFont]::Load($Segoe))
    if (-not $a -or -not $s) { return [double]100 }
    $t = 100 + (100 * $s / $a - 100) / 2
    [math]::Round([math]::Min(115, [math]::Max(85, $t)), 1)
}

# ---------- Gerar as cópias (mesmo cálculo do Set-SystemFont.ps1) ----------

# Medidas da família inteira, para todos os pesos terem a mesma linha: até onde as letras do português vão, o centro
# visual de um texto de interface (comparado ao da Segoe UI) e o tamanho do texto da interface em pixels.
function Get-MetricasLinha {
    param([Parameter(Mandatory)][string[]]$Origens, [Parameter(Mandatory)][string]$Regular, [Parameter(Mandatory)][string]$Segoe, [int]$TextoPx)
    $extensao = @(0, 0)
    $nucleo = @(0, 0)
    foreach ($p in $Origens | Select-Object -Unique) {
        $f = [TtFont]::Load($p)
        $e = $f.TextVerticalExtent(0x20, 0xFF)
        $extensao = @([math]::Min($extensao[0], $e[0]), [math]::Max($extensao[1], $e[1]))
        # Minúsculas (com acentos), maiúsculas sem acento e números: têm de caber na linha do DirectWrite.
        foreach ($ch in 'abcdefghijklmnopqrstuvwxyzàáâãäçèéêëìíîïñòóôõöùúûüýABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789'.ToCharArray()) {
            $g = $f.CodepointGlyph([int]$ch)
            if ($g -lt 0) { continue }
            $bb = $f.Bounds($g)
            if ($bb) { $nucleo = @([math]::Min($nucleo[0], $bb[1]), [math]::Max($nucleo[1], $bb[3])) }
        }
    }
    $amostra = 'Área de Trabalho Downloads Documentos Imagens Músicas Vídeos Configurações de exibição ' +
    'Personalizar Propriedades Copiar como caminho Classificar por Atualizar Novo Exibir Colar ' +
    'Recortar Excluir Renomear Restaurar Mover Tamanho Minimizar Maximizar Fechar Abrir com ' +
    'Enviar para Selecionar tudo Nova pasta Histórico Compartilhar Pesquisar Este Computador'
    $sg = [TtFont]::Load($Segoe)
    $sgOs2 = $sg.S.Get('OS/2')
    if ($TextoPx -le 0) { $TextoPx = [int][math]::Round(9 * (Get-TmdDpiSistema) / 72) }
    @{
        Extensao      = $extensao
        Nucleo        = $nucleo
        CentroVisual  = ([TtFont]::Load($Regular)).InkCentroidY($amostra)
        DesvioSegoeEm = (([Sfnt]::U16($sgOs2, 74) - [Sfnt]::U16($sgOs2, 76)) / 2 - $sg.InkCentroidY($amostra)) / $sg.Upm
        TextoPx       = $TextoPx
    }
}

function ConvertTo-UnidadesFonte {
    param([int]$Valor, [int]$De, [int]$Para)
    [int][math]::Round($Valor * $Para / $De)
}

# Uma cópia: o desenho de $Origem com os nomes, o peso/estilo e a altura de linha da $Segoe (um arquivo da Segoe UI).
function New-CopiaSegoe {
    param([string]$Origem, [string]$Segoe, [string]$Saida, [double]$Tamanho, [hashtable]$Metricas)
    $temporario = $null
    try {
        # .otf (contornos CFF) vira TrueType: o tamanho e a Segoe UI Variable dependem disso. O desenho não muda.
        if ([Sfnt]::Load($Origem).Has('CFF ')) {
            $temporario = New-TmdArquivoTemporario -Extensao '.ttf'
            [TtFont]::Load($Origem).Save($temporario)
            $Origem = $temporario
        }
        $src = [Sfnt]::Load($Origem)
        $seg = [Sfnt]::Load($Segoe)
        if ($seg.Name(0) -notmatch 'Microsoft') { throw "$Segoe não parece ser a Segoe UI original da Microsoft" }

        # Nomes: a tabela inteira da Segoe. O Windows passa a enxergar "Segoe UI <estilo>".
        $src.Tables['name'] = [byte[]]$seg.Get('name').Clone()
        $sHead = $src.Get('head')
        $gHead = $seg.Get('head')
        if ($Tamanho -ne 100) {
            # Mais unidades por em = o mesmo desenho ocupando uma fração menor do tamanho pedido, em todos os programas.
            $upm = [int][math]::Round([Sfnt]::U16($sHead, 18) * 100 / $Tamanho)
            if ($upm -lt 16 -or $upm -gt 16384) { throw "tamanho $Tamanho% dá unitsPerEm $upm, fora do limite" }
            [Sfnt]::W16($sHead, 18, $upm)
            # Larguras pré-calculadas por tamanho de pixel ficariam erradas.
            foreach ($t in 'hdmx', 'LTSH', 'VDMX') { [void]$src.Tables.Remove($t) }
        }
        $sUpm = [Sfnt]::U16($sHead, 18)
        $gUpm = [Sfnt]::U16($gHead, 18)
        [Sfnt]::W16($sHead, 44, [Sfnt]::U16($gHead, 44))   # macStyle (negrito/itálico)

        if ($src.Has('OS/2') -and $seg.Has('OS/2')) {
            $s = $src.Get('OS/2')
            $g = $seg.Get('OS/2')
            [Sfnt]::W16($s, 4, [Sfnt]::U16($g, 4))   # usWeightClass
            # fsSelection: estilo (itálico/negrito/regular) da Segoe; os outros bits ficam os da fonte.
            [Sfnt]::W16($s, 62, ([Sfnt]::U16($s, 62) -band (-bnot 0x61)) -bor ([Sfnt]::U16($g, 62) -band 0x61))
        }
        if ($src.Has('hhea') -and $seg.Has('hhea') -and $src.Has('OS/2')) {
            # Uma medida de linha só (win* = hhea, lineGap 0), com espaço para as letras do português, arredondada para
            # pixels inteiros no tamanho do texto da interface e com a tinta na mesma posição da caixa que a da Segoe UI.
            $gOs2 = $seg.Get('OS/2')
            $asc = [math]::Max((ConvertTo-UnidadesFonte ([Sfnt]::U16($gOs2, 74)) $gUpm $sUpm), $Metricas.Extensao[1])
            $desc = [math]::Max((ConvertTo-UnidadesFonte ([Sfnt]::U16($gOs2, 76)) $gUpm $sUpm), -$Metricas.Extensao[0])
            $k = $Metricas.TextoPx / $sUpm
            $ascPx = [math]::Ceiling($asc * $k - 1e-9)
            $minDescPx = [math]::Ceiling($desc * $k - 1e-9)
            $deslocamento = $Metricas.CentroVisual + $Metricas.DesvioSegoeEm * $sUpm
            $descPx = [math]::Max($minDescPx, [math]::Round($ascPx - 2 * $deslocamento * $k))
            $asc = [int][math]::Floor($ascPx / $k)
            $desc = [int][math]::Floor($descPx / $k)
            $os2 = $src.Get('OS/2')
            $hhea = $src.Get('hhea')
            [Sfnt]::W16($os2, 74, $asc); [Sfnt]::W16($os2, 76, $desc)
            [Sfnt]::W16($hhea, 4, $asc); [Sfnt]::W16($hhea, 6, -$desc); [Sfnt]::W16($hhea, 8, 0)
            # Métricas "typo" (DirectWrite/WinUI): a mesma altura de linha da Segoe UI, para os controles do Windows 11 não
            # mudarem de altura; dentro dela, a linha de base onde a tinta cai na mesma posição que a da Segoe.
            $typoTotal = [int][math]::Round(([Sfnt]::U16($gOs2, 74) + [Sfnt]::U16($gOs2, 76)) / $gUpm * $sUpm)
            $typoAsc = [int][math]::Round(($typoTotal + 2 * $deslocamento) / 2)
            $typoAsc = [math]::Min([math]::Max($typoAsc, $Metricas.Nucleo[1]), $typoTotal + $Metricas.Nucleo[0])
            $typoDesc = $typoTotal - $typoAsc
            if ($typoDesc -lt -$Metricas.Nucleo[0]) { $typoDesc = -$Metricas.Nucleo[0]; $typoAsc = [math]::Max($typoAsc, $Metricas.Nucleo[1]) }
            [Sfnt]::W16($os2, 68, $typoAsc); [Sfnt]::W16($os2, 70, -$typoDesc); [Sfnt]::W16($os2, 72, 0)
            [Sfnt]::W16($os2, 62, [Sfnt]::U16($os2, 62) -bor 0x80)
        }

        # Segoe UI Variable: o Windows 11 pede instâncias nomeadas (Display/Text/Small, pesos). Copia fvar/STAT/avar da
        # original e cria um gvar vazio: todas as instâncias usam a fonte escolhida.
        if ($seg.Has('fvar') -and -not $src.Has('fvar')) {
            foreach ($t in 'fvar', 'STAT', 'avar') { if ($seg.Has($t)) { $src.Tables[$t] = [byte[]]$seg.Get($t).Clone() } }
            $eixos = [Sfnt]::U16($seg.Get('fvar'), 8)
            $glifos = [Sfnt]::U16($src.Get('maxp'), 4)
            $gvar = New-Object byte[] (20 + ($glifos + 1) * 2)
            $dados = [uint32]$gvar.Length
            [Sfnt]::W16($gvar, 0, 1); [Sfnt]::W16($gvar, 4, $eixos)
            [Sfnt]::W32($gvar, 8, $dados); [Sfnt]::W16($gvar, 12, $glifos); [Sfnt]::W32($gvar, 16, $dados)
            $src.Tables['gvar'] = $gvar
        }
        # A assinatura digital fica inválida depois da edição.
        [void]$src.Tables.Remove('DSIG')
        $src.Save($Saida)
    }
    finally { if ($temporario) { Remove-TmdArquivoTemporario -Caminho $temporario } }
}

# ---------- Estado ----------

# O que o Tamanduá instalou por último (família, tamanho, sufixo dos arquivos), para a página mostrar o que está em uso.
function Get-ArquivoEstadoFonte { Join-Path (Get-TmdPastaDados) 'estado\fonte.json' }

function Read-EstadoFonte {
    $arquivo = Get-ArquivoEstadoFonte
    if (-not [IO.File]::Exists($arquivo)) { return $null }
    try {
        $e = [IO.File]::ReadAllText($arquivo) | ConvertFrom-Json
        if ($e.PSObject.Properties['Sufixo'] -and $e.Sufixo) { return $e }
    }
    catch { Write-Verbose "estado da fonte ilegível: $($_.Exception.Message)" }
    $null
}

function Save-EstadoFonte {
    param([Parameter(Mandatory)][hashtable]$Estado)
    $arquivo = Get-ArquivoEstadoFonte
    [void][IO.Directory]::CreateDirectory((Split-Path -Parent $arquivo))
    [IO.File]::WriteAllText($arquivo, ($Estado | ConvertTo-Json), [Text.UTF8Encoding]::new($false))
}

# Para onde o registro aponta a Segoe UI agora.
function Get-FonteAtual {
    param([string]$RaizRegistro)
    $valores = @{}
    $k = Open-ChaveFontes -Hive 'HKLM' -RaizRegistro $RaizRegistro
    if ($k) { try { foreach ($v in $script:Vagas.Keys) { $valores[$v] = [string]$k.GetValue($v, '') } } finally { $k.Close() } }
    $principal = [string]$valores['Segoe UI (TrueType)']
    $sufixo = if ($principal -match '^segoeui_(.+)\.ttf$') { $Matches[1] } else { '' }
    $trocadas = @($script:Vagas.Keys | Where-Object { $valores[$_] -and $valores[$_] -ine "$($script:Vagas[$_][0]).ttf" })
    [pscustomobject]@{ Sufixo = $sufixo; Original = $trocadas.Count -eq 0 }
}

# Cópias de trocas antigas que o registro não usa mais, e as pastas de trabalho de trocas antigas.
function Get-CopiasSobrando {
    param([string]$RaizRegistro, [string]$PastaFontes)
    $usados = @{}
    foreach ($f in Get-FontesRegistradas -RaizRegistro $RaizRegistro -PastaFontes $PastaFontes) { $usados[[IO.Path]::GetFileName($f.Valor).ToLowerInvariant()] = $true }
    $copias = @(Get-ChildItem -LiteralPath $PastaFontes -File -Filter '*_*.ttf' -ErrorAction SilentlyContinue |
            Where-Object { (Test-TmdNomeCopiaFonte -Nome $_.Name) -and -not $usados.ContainsKey($_.Name.ToLowerInvariant()) })
    $atual = (Get-FonteAtual -RaizRegistro $RaizRegistro).Sufixo
    $pastaTrabalho = Join-Path (Get-TmdPastaDados) 'fontes'
    $trabalho = @(Get-ChildItem -LiteralPath $pastaTrabalho -Directory -ErrorAction SilentlyContinue | Where-Object { $_.Name -ne $atual })
    $bytes = [int64]0
    foreach ($c in $copias) { $bytes += $c.Length }
    foreach ($t in $trabalho) { $bytes += (Measure-TmdTamanho -Caminho $t.FullName).Bytes }
    [pscustomobject]@{ Copias = $copias; Trabalho = $trabalho; PastaTrabalho = $pastaTrabalho; Bytes = $bytes }
}

# ---------- Contrato ----------

function New-AlvoFonte {
    param([string]$Id, [string]$Nome, [string]$Categoria, [string]$Estado = 'NaoAplicado', [string]$Selo = '', [string]$Detalhe = '',
        [string]$Risco = 'Medio', [bool]$Selecionavel = $true, [int64]$Tamanho = 0, [string]$Destino = 'NaoSeAplica', [bool]$RequerAdmin = $true,
        [object]$Reversivel = $true, [string[]]$Mudancas = @())
    [pscustomobject]@{
        Id = $Id; Nome = $Nome; Categoria = $Categoria; Caminho = ''; Tamanho = $Tamanho; Estado = $Estado; Selo = $Selo; Detalhe = $Detalhe
        Nivel = 'Normal'; Valor = $null; Risco = $Risco; Selecionado = $false; Selecionavel = $Selecionavel; Destino = $Destino
        RequerAdmin = $RequerAdmin; Reversivel = $Reversivel; Mudancas = $Mudancas
    }
}

function Find-Alvos {
    param([string]$RaizRegistro = (Get-RaizRegistroPadrao), [string]$PastaFontes = (Get-PastaFontes))
    $admin = -not $RaizRegistro
    $atual = Get-FonteAtual -RaizRegistro $RaizRegistro
    $estado = Read-EstadoFonte
    $nossa = $null -ne $estado -and $atual.Sufixo -and $estado.Sufixo -eq $atual.Sufixo
    $nomeAtual = if ($atual.Original) { 'Segoe UI (a do Windows)' } elseif ($nossa) { "$($estado.Familia) a $($estado.Porcentagem)%" } else { "personalizada, de fora do Tamanduá ($($atual.Sufixo))" }

    New-AlvoFonte -Id 'segoe-original' -Nome 'Segoe UI original (a do Windows)' -Categoria 'Segoe UI' -Risco 'Baixo' -RequerAdmin $admin `
        -Estado $(if ($atual.Original) { 'Aplicado' } else { 'NaoAplicado' }) -Selecionavel (-not $atual.Original) `
        -Selo $(if ($atual.Original) { 'em uso' } else { "agora: $nomeAtual" }) `
        -Detalhe "Volta para a fonte de fábrica do Windows. Fonte em uso agora: $nomeAtual." `
        -Mudancas @('Aponta os pesos da Segoe UI no registro de volta para os arquivos originais (segoeui.ttf...).', 'Vale depois de reiniciar o Windows.')

    $sobra = Get-CopiasSobrando -RaizRegistro $RaizRegistro -PastaFontes $PastaFontes
    $qtd = $sobra.Copias.Count + $sobra.Trabalho.Count
    New-AlvoFonte -Id 'limpar-copias' -Nome 'Apagar cópias de trocas antigas' -Categoria 'Segoe UI' -Risco 'Baixo' -RequerAdmin $admin `
        -Estado 'NaoSeAplica' -Selecionavel ($qtd -gt 0) -Tamanho $sobra.Bytes -Destino 'Permanente' -Reversivel $false `
        -Selo $(if ($qtd -gt 0) { "$($sobra.Copias.Count) cópia(s)" } else { 'nada sobrando' }) `
        -Detalhe 'Cada troca deixa cópias da fonte em Windows\Fonts. Apaga só as que o registro não usa mais.' `
        -Mudancas @(
            if ($qtd -eq 0) { 'Nenhuma cópia sobrando.' }
            foreach ($c in $sobra.Copias) { "apaga $($c.FullName)" }
            foreach ($t in $sobra.Trabalho) { "apaga $($t.FullName)" }
            'Cópia ainda carregada pelo Windows (de uma troca desfeita agora) é apagada no próximo reinício.'
        )

    foreach ($id in $script:Tamanhos.Keys) {
        $usado = $nossa -and $estado.Tamanho -eq $id
        New-AlvoFonte -Id $id -Nome $script:Tamanhos[$id] -Categoria 'Tamanho do texto' -Risco 'Baixo' -RequerAdmin $admin `
            -Estado $(if ($usado) { 'Aplicado' } else { 'NaoAplicado' }) -Selo $(if ($usado) { 'em uso' } else { '' }) `
            -Detalhe 'Marque junto com uma fonte. Sozinho, gera de novo a fonte em uso com este tamanho. Sem marcar nenhum: automático.' `
            -Mudancas @('Muda o tamanho do desenho das letras em todos os programas, sem mexer na escala do Windows.')
    }

    foreach ($f in Get-FamiliasInstaladas -RaizRegistro $RaizRegistro -PastaFontes $PastaFontes) {
        $emUso = $nossa -and $estado.Id -eq $f.Id
        New-AlvoFonte -Id $f.Id -Nome $f.Nome -Categoria 'Fontes instaladas' -Estado $(if ($emUso) { 'Aplicado' } else { 'NaoAplicado' }) `
            -Selo $(if ($emUso) { "em uso · $($estado.Porcentagem)%" } else { '' }) -RequerAdmin $admin `
            -Detalhe (($f.Estilos | Select-Object -Unique) -join ', ') `
            -Mudancas @(
                'Marque esta fonte (e, se quiser, um tamanho; sem tamanho, é o automático) e aplique.'
                "Gera cópias de $($f.Nome) com o nome da Segoe UI (os pesos que faltarem usam o mais parecido) e põe em Windows\Fonts."
                'Aponta os pesos da Segoe UI no registro para essas cópias (antes, guarda como estava e um .reg da chave).'
                'Vale depois de reiniciar o Windows: barra de tarefas, Configurações, Explorador, apps e a tela de entrada.'
                'Os arquivos da Segoe UI não mudam. Para voltar: Histórico > Desfazer, ou "Segoe UI original" nesta página.'
            )
    }

}

function New-ResultadoFonte {
    param([string]$Id, [string]$Status, [string]$Motivo = '', [string[]]$Mudancas = @(), [int64]$Liberado = 0)
    [pscustomobject]@{ Id = $Id; Status = $Status; Liberado = $Liberado; Motivo = $Motivo; Mudancas = $Mudancas }
}

# Gera, instala e aponta o registro. Sem fonte marcada (só um tamanho): gera de novo a fonte que o Tamanduá pôs.
function Set-FonteSistema {
    param([string]$IdFamilia, [string]$IdTamanho, [bool]$Simular, [string]$RaizRegistro, [string]$PastaFontes)
    $estado = Read-EstadoFonte
    $idResultado = if ($IdFamilia) { $IdFamilia } else { $IdTamanho }
    if (-not $IdFamilia) {
        if (-not $estado) { return New-ResultadoFonte -Id $idResultado -Status 'Erro' -Motivo 'marque também a fonte (o tamanho sozinho só vale para a fonte que o Tamanduá pôs)' }
        $IdFamilia = $estado.Id
    }
    $familia = @(Get-FamiliasInstaladas -RaizRegistro $RaizRegistro -PastaFontes $PastaFontes | Where-Object Id -eq $IdFamilia)
    if ($familia.Count -eq 0) { return New-ResultadoFonte -Id $idResultado -Status 'Erro' -Motivo 'essa fonte não está mais instalada' }
    $familia = $familia[0]
    $segoe = Join-Path $PastaFontes 'segoeui.ttf'
    if (-not [IO.File]::Exists($segoe)) { return New-ResultadoFonte -Id $idResultado -Status 'Erro' -Motivo 'segoeui.ttf não está na pasta de fontes' }

    Initialize-TmdFontKit
    $estilos = @(Get-EstilosArquivos -Arquivos $familia.Arquivos)
    if ($estilos.Count -eq 0) { return New-ResultadoFonte -Id $idResultado -Status 'Erro' -Motivo "não deu para ler os arquivos de $($familia.Nome)" }
    $normal = Select-ArquivoVaga -Estilos $estilos -Peso 400 -Italico $false
    if ($normal.Italico -or $normal.Peso -ge 600) { return New-ResultadoFonte -Id $idResultado -Status 'Erro' -Motivo "$($familia.Nome) não tem um estilo normal (só negrito ou itálico)" }
    $regular = $normal.Arquivo
    if (-not $IdTamanho) { $IdTamanho = 'tam-auto' }
    $porcentagem = if ($IdTamanho -eq 'tam-auto') { Get-TamanhoAutomatico -Regular $regular -Segoe $segoe } else { [double]($IdTamanho -replace '^tam-', '') }

    $plano = @(foreach ($vaga in $script:Vagas.Keys) {
            $original, $peso, $italico = $script:Vagas[$vaga]
            $arquivoSegoe = Join-Path $PastaFontes "$original.ttf"
            if (-not [IO.File]::Exists($arquivoSegoe)) { continue }
            [pscustomobject]@{ Vaga = $vaga; Original = $original; Segoe = $arquivoSegoe; Origem = (Select-ArquivoVaga -Estilos $estilos -Peso $peso -Italico $italico).Arquivo }
        })
    $descricoes = @("$($familia.Nome) a $porcentagem%") + @($plano | ForEach-Object { "$($_.Vaga) ← $([IO.Path]::GetFileName($_.Origem))" }) + 'Vale depois de reiniciar o Windows.'
    if ($Simular) { return New-ResultadoFonte -Id $idResultado -Status 'Simulado' -Mudancas $descricoes }

    # Sufixo novo a cada troca: o Windows não deixa sobrescrever uma fonte carregada.
    $sufixo = 'tmd' + (Get-Date -Format 'yyMMddHHmmss')
    $saida = Join-Path (Join-Path (Get-TmdPastaDados) 'fontes') $sufixo
    [void][IO.Directory]::CreateDirectory($saida)
    $metricas = Get-MetricasLinha -Origens @($plano | ForEach-Object Origem) -Regular $regular -Segoe $segoe
    foreach ($p in $plano) {
        $p | Add-Member -NotePropertyName Gerado -NotePropertyValue (Join-Path $saida "$($p.Original)_$sufixo.ttf")
        New-CopiaSegoe -Origem $p.Origem -Segoe $p.Segoe -Saida $p.Gerado -Tamanho $porcentagem -Metricas $metricas
    }
    try { foreach ($p in $plano) { [void](Install-TmdArquivoFonte -Origem $p.Gerado -Pasta $PastaFontes -Id $idResultado) } }
    catch {
        return New-ResultadoFonte -Id $idResultado -Status 'Erro' -Mudancas $descricoes `
            -Motivo "não deu para copiar para a pasta de fontes ($((Get-TmdExcecaoInterna $_.Exception).Message)); o registro não mudou"
    }

    $ajuste = [pscustomobject]@{
        id = 'fonte-sistema'; nome = "Fonte do sistema: $($familia.Nome)"; requerAdmin = $true
        mudancas = @(foreach ($p in $plano) {
                [pscustomobject]@{ tipo = 'Registro'; caminho = $script:ChaveFontes; nome = $p.Vaga; valor = "$($p.Original)_$sufixo.ttf"; tipoValor = 'String'; padraoWindows = "$($p.Original).ttf" }
            })
    }
    $r = Set-TmdAjuste -Ajuste $ajuste -RaizRegistro $RaizRegistro -Modulo 'fonte'
    if ($r.Status -eq 'Feito') {
        Save-EstadoFonte -Estado @{ Id = $familia.Id; Familia = $familia.Nome; Tamanho = $IdTamanho; Porcentagem = $porcentagem; Sufixo = $sufixo; Data = (Get-Date).ToString('o') }
        $r.Motivo = "$($familia.Nome) a $porcentagem%: reinicie o Windows para ver"
    }
    New-ResultadoFonte -Id $idResultado -Status $r.Status -Motivo $r.Motivo -Mudancas $descricoes
}

function Restore-SegoeOriginal {
    param([bool]$Simular, [string]$RaizRegistro, [string]$PastaFontes)
    $ajuste = [pscustomobject]@{
        id = 'fonte-original'; nome = 'Fonte do sistema: Segoe UI original'; requerAdmin = $true
        mudancas = @(foreach ($vaga in $script:Vagas.Keys) {
                $original = $script:Vagas[$vaga][0]
                if (-not [IO.File]::Exists((Join-Path $PastaFontes "$original.ttf"))) { continue }
                [pscustomobject]@{ tipo = 'Registro'; caminho = $script:ChaveFontes; nome = $vaga; valor = "$original.ttf"; tipoValor = 'String'; padraoWindows = "$original.ttf" }
            })
    }
    $r = Set-TmdAjuste -Ajuste $ajuste -Simular:$Simular -RaizRegistro $RaizRegistro -Modulo 'fonte'
    if ($r.Status -eq 'Feito' -and -not $Simular) {
        Save-EstadoFonte -Estado @{ Sufixo = '' }
        if ($r.Motivo -ne 'já estava aplicado') { $r.Motivo = 'Segoe UI de volta: reinicie o Windows para ver' }
    }
    New-ResultadoFonte -Id 'segoe-original' -Status $r.Status -Motivo $r.Motivo -Mudancas $r.Mudancas
}

function Clear-CopiasSobrando {
    param([bool]$Simular, [string]$RaizRegistro, [string]$PastaFontes)
    $sobra = Get-CopiasSobrando -RaizRegistro $RaizRegistro -PastaFontes $PastaFontes
    $resultados = @(
        foreach ($c in $sobra.Copias) { Remove-TmdCopiaFonte -Caminho $c.FullName -Simular:$Simular -Id 'limpar-copias' }
        foreach ($t in $sobra.Trabalho) { Remove-TmdItem -Caminho $t.FullName -Raizes $sobra.PastaTrabalho -Simular:$Simular -Modulo 'fonte' -Id 'limpar-copias' }
    )
    $liberado = [int64]0
    foreach ($r in $resultados) { $liberado += [int64]$r.Liberado }
    $feitos = @($resultados | Where-Object { $_.Status -in 'Feito', 'Simulado' })
    $noBoot = @($resultados | Where-Object { $_.Motivo -like '*reiniciar*' })
    $pulados = @($resultados | Where-Object { $_.Status -notin 'Feito', 'Simulado' -and $_.Motivo -ne 'não existe mais' })
    $status = if ($Simular) { 'Simulado' } elseif ($pulados.Count -eq 0) { 'Feito' } elseif ($feitos.Count -gt 0) { 'Parcial' } else { 'Erro' }
    $motivo = @(
        "$($feitos.Count) apagada(s)"
        if ($noBoot.Count -gt 0) { "$($noBoot.Count) só ao reiniciar (ainda carregadas)" }
        if ($pulados.Count -gt 0) { "$($pulados.Count) pulada(s): $($pulados[0].Motivo)" }
    ) -join '; '
    New-ResultadoFonte -Id 'limpar-copias' -Status $status -Motivo $motivo -Liberado $liberado -Mudancas @($resultados | ForEach-Object { "apaga $($_.Caminho)" })
}

function Invoke-Acao {
    param(
        [Parameter(Mandatory)][AllowEmptyCollection()][object[]]$Alvos,
        [switch]$Simular,
        [string]$RaizRegistro = (Get-RaizRegistroPadrao),
        [string]$PastaFontes = (Get-PastaFontes)
    )
    $ids = @($Alvos | ForEach-Object { [string]$_.Id })
    $familias = @($ids | Where-Object { $_ -like 'fam-*' })
    $tamanhos = @($ids | Where-Object { $_ -like 'tam-*' })
    $erro = if ($familias.Count -gt 1) { 'marque só uma fonte' }
    elseif ($tamanhos.Count -gt 1) { 'marque só um tamanho' }
    elseif ($ids -contains 'segoe-original' -and ($familias.Count + $tamanhos.Count) -gt 0) { 'marque a Segoe UI original ou uma fonte, não os dois' }
    if ($erro) {
        foreach ($id in $ids) { New-ResultadoFonte -Id $id -Status 'Erro' -Motivo "$erro (nada mudou)" }
        return
    }
    if ($familias.Count + $tamanhos.Count -gt 0) {
        $r = Set-FonteSistema -IdFamilia $(if ($familias.Count) { $familias[0] } else { '' }) -IdTamanho $(if ($tamanhos.Count) { $tamanhos[0] } else { '' }) `
            -Simular ([bool]$Simular) -RaizRegistro $RaizRegistro -PastaFontes $PastaFontes
        $r
        # Fonte e tamanho marcados juntos: um resultado para cada, com o mesmo desfecho.
        if ($familias.Count -and $tamanhos.Count) { New-ResultadoFonte -Id $tamanhos[0] -Status $r.Status -Motivo $r.Motivo }
    }
    if ($ids -contains 'segoe-original') { Restore-SegoeOriginal -Simular ([bool]$Simular) -RaizRegistro $RaizRegistro -PastaFontes $PastaFontes }
    # Por último: uma troca feita agora deixa as cópias anteriores sem uso.
    if ($ids -contains 'limpar-copias') { Clear-CopiasSobrando -Simular ([bool]$Simular) -RaizRegistro $RaizRegistro -PastaFontes $PastaFontes }
}

Export-ModuleMember -Function Test-Requisitos, Find-Alvos, Invoke-Acao
