# Artefatos de projeto que se recriam sozinhos (node_modules, target, bin/obj...), agrupados por projeto.
# Uma pasta só é artefato se o projeto ao lado tiver o arquivo que a explica (ex.: package.json para node_modules).
# Nunca: pasta com arquivos versionados no git, pasta com outro repositório git dentro, links.

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Nome da pasta -> arquivos que precisam existir ao lado (qualquer um) e como recriar.
$script:Regras = @{
    'node_modules' = @{ Marcadores = @('package.json'); Recriar = 'npm install / pnpm install / yarn' }
    '.next'        = @{ Marcadores = @('package.json'); Recriar = 'next build' }
    '.nuxt'        = @{ Marcadores = @('package.json'); Recriar = 'nuxt build' }
    '.svelte-kit'  = @{ Marcadores = @('package.json'); Recriar = 'vite build' }
    '.angular'     = @{ Marcadores = @('angular.json'); Recriar = 'ng build (cache)' }
    'dist'         = @{ Marcadores = @('package.json', 'pyproject.toml', 'setup.py'); Recriar = 'o build do projeto' }
    'build'        = @{ Marcadores = @('build.gradle', 'build.gradle.kts', 'settings.gradle', 'CMakeLists.txt', 'package.json'); Recriar = 'o build do projeto' }
    '.gradle'      = @{ Marcadores = @('build.gradle', 'build.gradle.kts', 'settings.gradle'); Recriar = 'gradle build' }
    'target'       = @{ Marcadores = @('Cargo.toml', 'pom.xml'); Recriar = 'cargo build / mvn package' }
    'bin'          = @{ Marcadores = @('*.csproj', '*.fsproj', '*.vbproj'); Recriar = 'dotnet build' }
    'obj'          = @{ Marcadores = @('*.csproj', '*.fsproj', '*.vbproj'); Recriar = 'dotnet build' }
    '__pycache__'  = @{ Marcadores = @('*.py'); Recriar = 'é recriado ao rodar o Python' }
    '.venv'        = @{ Marcadores = @('pyproject.toml', 'requirements.txt', 'setup.py', 'Pipfile'); Recriar = 'python -m venv .venv e reinstalar as dependências'; Dentro = 'pyvenv.cfg' }
    'venv'         = @{ Marcadores = @('pyproject.toml', 'requirements.txt', 'setup.py', 'Pipfile'); Recriar = 'python -m venv venv e reinstalar as dependências'; Dentro = 'pyvenv.cfg' }
}
# Pastas onde a busca não entra (além dos próprios artefatos e links).
$script:NaoEntrar = @('.git', '.hg', '.svn', 'AppData', '$RECYCLE.BIN', 'System Volume Information', 'Windows', 'Program Files', 'Program Files (x86)')
$script:ProfundidadeMaxima = 6
# Mexido nos últimos dias: projeto em uso, vem desmarcado.
$script:DiasRecente = 7

function Test-Requisitos {
    @{ Ok = $true; Motivo = '' }
}

# Onde costumam ficar projetos. Só entram as que existem.
function Get-RaizPadrao {
    $perfil = [Environment]::GetFolderPath('UserProfile')
    $candidatas = @([Environment]::GetFolderPath('MyDocuments'), [Environment]::GetFolderPath('Desktop')) +
    @('source', 'Projects', 'Projetos', 'dev', 'code', 'repos', 'git', 'GitHub', 'workspace', 'src' | ForEach-Object { Join-Path $perfil $_ })
    @($candidatas | Where-Object { $_ -and (Test-Path -LiteralPath $_ -PathType Container) } | Select-Object -Unique)
}

# Sem -Caminho: procura nas pastas comuns de projeto. Com -Caminho: só nela (ex.: tamandua purgar D:\dev).
function Find-Alvos {
    param([string]$Caminho)

    $raizes = if ($Caminho) { @([IO.Path]::GetFullPath($Caminho).TrimEnd('\')) } else { Get-RaizPadrao }
    $temGit = [bool](Get-Command git -ErrorAction SilentlyContinue)
    $agora = Get-Date
    $versionados = 0
    $vistos = @{}
    foreach ($raiz in $raizes) {
        foreach ($art in Find-Artefato -Raiz $raiz) {
            $chave = $art.FullName.ToLowerInvariant()
            if ($vistos.ContainsKey($chave)) { continue }
            $vistos[$chave] = $true

            $erro = Test-Artefato -Pasta $art.FullName -TemGit $temGit
            if ($erro -eq 'versionado') { $versionados++; continue }
            if ($erro -and $erro -ne 'sem-git') { continue }

            $regra = $script:Regras[$art.Name]
            $medida = Measure-TmdTamanho -Caminho $art.FullName
            $dias = [int][Math]::Floor(($agora - (Get-UltimaMudanca -Pasta $art)).TotalDays)
            $recente = $dias -lt $script:DiasRecente
            $risco = 'Baixo'
            $detalhe = "$(Format-TmdTamanho $medida.Bytes) · $('{0:N0}' -f $medida.Arquivos) arquivo(s) · mexido há $dias dia(s)"
            if ($recente) { $detalhe += ' · projeto em uso, veio desmarcado' }
            if ($erro -eq 'sem-git') {
                $risco = 'Medio'
                $detalhe += ' · git não encontrado: não deu para conferir arquivos versionados'
            }
            [pscustomobject]@{
                Id          = "art:$($art.FullName)"
                Nome        = $art.Name
                Categoria   = Format-Projeto -Projeto $art.Parent.FullName -Raizes $raizes
                Caminho     = $art.FullName
                Tamanho     = [int64]$medida.Bytes
                Estado      = 'NaoSeAplica'
                Detalhe     = $detalhe
                Nivel       = 'Normal'
                Valor       = $null
                Risco       = $risco
                Selecionado = $risco -eq 'Baixo' -and -not $recente -and $medida.Bytes -gt 0
                Destino     = 'Permanente'
                RequerAdmin = $false
                Reversivel  = $false
                Mudancas    = @("Apaga $($art.FullName)", "Para recriar: $($regra.Recriar)")
            }
        }
    }
    if ($versionados -gt 0) {
        [pscustomobject]@{
            Id = 'aviso-versionados'; Nome = "$versionados pasta(s) deixada(s) de fora"; Categoria = 'Aviso'; Caminho = ''
            Tamanho = [int64]0; Estado = 'NaoSeAplica'; Detalhe = 'têm arquivos versionados no git: não são só artefato de build'
            Nivel = 'Atencao'; Valor = $null; Risco = 'Baixo'; Selecionado = $false; Selecionavel = $false
            Destino = 'NaoSeAplica'; RequerAdmin = $false; Reversivel = $null; Mudancas = @()
        }
    }
}

# Reconfere tudo pelo caminho (que sai do Id) antes de apagar; não confia no resto do alvo.
function Invoke-Acao {
    param([Parameter(Mandatory)][AllowEmptyCollection()][object[]]$Alvos, [switch]$Simular)

    $temGit = [bool](Get-Command git -ErrorAction SilentlyContinue)
    foreach ($a in $Alvos) {
        $id = [string]$a.Id
        if ($id -notlike 'art:*') {
            [pscustomobject]@{ Id = $id; Status = 'Ignorado'; Liberado = [int64]0; Motivo = 'item inválido' }
            continue
        }
        $caminho = [IO.Path]::GetFullPath($id.Substring(4)).TrimEnd('\')
        $erro = Test-Artefato -Pasta $caminho -TemGit $temGit
        if ($erro -and -not ($erro -eq 'sem-git' -and $a.PSObject.Properties['Risco'] -and $a.Risco -eq 'Medio')) {
            $texto = switch ($erro) {
                'versionado' { 'tem arquivos versionados no git' }
                'sem-git' { 'git não encontrado: não deu para conferir arquivos versionados' }
                default { $erro }
            }
            [pscustomobject]@{ Id = $id; Status = 'Ignorado'; Liberado = [int64]0; Motivo = $texto }
            continue
        }
        Remove-TmdItem -Caminho $caminho -Raizes (Split-Path -Parent $caminho) -Simular:$Simular -Modulo 'purgar' -Id $id
    }
}

# $null = é artefato e pode apagar. 'versionado' / 'sem-git' / texto = motivo para não apagar.
function Test-Artefato {
    param([Parameter(Mandatory)][string]$Pasta, [bool]$TemGit)

    $dir = New-Object IO.DirectoryInfo $Pasta
    if (-not $dir.Exists) { return 'não existe mais' }
    if ($dir.Attributes -band [IO.FileAttributes]::ReparsePoint) { return 'é um link' }
    if (-not $script:Regras.ContainsKey($dir.Name)) { return 'não é uma pasta de artefato conhecida' }
    $regra = $script:Regras[$dir.Name]
    if (-not (Test-Marcador -Projeto $dir.Parent.FullName -Marcadores $regra.Marcadores)) { return "falta $($regra.Marcadores -join ' ou ') ao lado" }
    if ($regra.ContainsKey('Dentro') -and -not (Test-Path -LiteralPath (Join-Path $Pasta $regra.Dentro))) { return "não tem $($regra.Dentro)" }
    if (Test-GitAninhado -Pasta $dir) { return 'tem outro repositório git dentro' }
    if (-not $TemGit) { return 'sem-git' }
    if (Test-Versionado -Pasta $Pasta) { return 'versionado' }
    $null
}

function Test-Marcador {
    param([string]$Projeto, [string[]]$Marcadores)
    foreach ($m in $Marcadores) {
        try { if (@([IO.Directory]::EnumerateFiles($Projeto, $m) | Select-Object -First 1).Count -gt 0) { return $true } } catch { return $false }
    }
    $false
}

# Repositório git dentro do artefato (até 2 níveis): pode ser um pacote em desenvolvimento, não um download.
function Test-GitAninhado {
    param([Parameter(Mandatory)][IO.DirectoryInfo]$Pasta)
    $nivel1 = try { @($Pasta.GetDirectories()) } catch { @() }
    foreach ($d in $nivel1) {
        if ($d.Name -eq '.git') { return $true }
        if ($d.Attributes -band [IO.FileAttributes]::ReparsePoint) { continue }
        if (Test-Path -LiteralPath (Join-Path $d.FullName '.git')) { return $true }
    }
    $false
}

# Algum arquivo dentro da pasta está no git? (artefato não devia estar; se está, alguém quis guardar)
function Test-Versionado {
    param([Parameter(Mandatory)][string]$Pasta)
    $repo = Split-Path -Parent $Pasta
    while ($repo -and -not (Test-Path -LiteralPath (Join-Path $repo '.git'))) {
        $pai = Split-Path -Parent $repo
        if ($pai -eq $repo) { $repo = $null } else { $repo = $pai }
    }
    if (-not $repo) { return $false }
    $relativo = $Pasta.Substring($repo.Length).TrimStart('\')
    # No 5.1, stderr de programa externo com ErrorActionPreference = Stop vira exceção; aqui só interessa a saída.
    $ErrorActionPreference = 'Continue'
    $saida = @(& git -C $repo ls-files -- $relativo 2>$null | Select-Object -First 1)
    $saida.Count -gt 0
}

# Busca em largura, sem entrar em links, em pastas de sistema nem dentro dos próprios artefatos.
function Find-Artefato {
    param([Parameter(Mandatory)][string]$Raiz)

    $inicio = New-Object IO.DirectoryInfo $Raiz
    if (-not $inicio.Exists) { return }
    $fila = [System.Collections.Generic.Queue[object]]::new()
    $fila.Enqueue(@($inicio, 0))
    while ($fila.Count -gt 0) {
        $dir, $nivel = $fila.Dequeue()
        try { $subs = $dir.GetDirectories() } catch { continue }
        foreach ($s in $subs) {
            if ($s.Attributes -band [IO.FileAttributes]::ReparsePoint) { continue }
            if ($script:NaoEntrar -contains $s.Name) { continue }
            if ($script:Regras.ContainsKey($s.Name)) {
                $regra = $script:Regras[$s.Name]
                if (Test-Marcador -Projeto $dir.FullName -Marcadores $regra.Marcadores) { $s }
                continue
            }
            if ($nivel + 1 -lt $script:ProfundidadeMaxima) { $fila.Enqueue(@($s, ($nivel + 1))) }
        }
    }
}

# Data da última mudança: a mais nova entre a pasta e o que está no primeiro nível dela.
function Get-UltimaMudanca {
    param([Parameter(Mandatory)][IO.DirectoryInfo]$Pasta)
    $mais = $Pasta.LastWriteTime
    try { foreach ($i in $Pasta.GetFileSystemInfos()) { if ($i.LastWriteTime -gt $mais) { $mais = $i.LastWriteTime } } } catch { Write-Verbose $_.Exception.Message }
    $mais
}

# "Projetos\meu-app" em vez do caminho inteiro, quando o projeto está dentro de uma das raízes.
function Format-Projeto {
    param([string]$Projeto, [string[]]$Raizes)
    foreach ($r in $Raizes) {
        if ($Projeto.StartsWith($r + '\', [StringComparison]::OrdinalIgnoreCase)) { return "$(Split-Path -Leaf $r)\$($Projeto.Substring($r.Length + 1))" }
        if ($Projeto -eq $r) { return $Projeto }
    }
    $Projeto
}

Export-ModuleMember -Function Test-Requisitos, Find-Alvos, Invoke-Acao
