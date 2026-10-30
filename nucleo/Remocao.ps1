# ÚNICO lugar do Tamanduá que apaga arquivos (o teste de contrato garante).
# Apaga com .NET, item por item, sem nunca entrar em links: Remove-Item -Recurse no 5.1 segue junctions.

function Remove-TmdItem {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Caminho,
        # Pastas dentro das quais esta remoção é permitida; o alvo precisa estar dentro de uma delas.
        [Parameter(Mandatory)][string[]]$Raizes,
        [ValidateSet('Permanente', 'Lixeira')][string]$Destino = 'Permanente',
        [switch]$Simular,
        [string]$Modulo = '',
        [string]$Id = ''
    )

    $resultado = [pscustomobject]@{ Id = $Id; Caminho = $Caminho; Status = 'Ignorado'; Liberado = [int64]0; Motivo = '' }
    try {
        $protecao = @(Get-TmdListaProtecao)
    }
    catch {
        $resultado.Status = 'Erro'
        $resultado.Motivo = "$($_.Exception.Message); nada foi removido"
        return Complete-TmdRemocao $resultado $Modulo $Destino $Simular
    }

    $verificacao = Test-TmdCaminhoSeguro -Caminho $Caminho -Raizes $Raizes -Protecao $protecao
    $resultado.Caminho = $verificacao.Caminho
    if (-not $verificacao.Ok) {
        $resultado.Motivo = $verificacao.Motivo
        return Complete-TmdRemocao $resultado $Modulo $Destino $Simular
    }
    $alvo = $verificacao.Caminho
    $item = Get-Item -LiteralPath $alvo -Force -ErrorAction SilentlyContinue
    if (-not $item) {
        $resultado.Motivo = 'não existe mais'
        return Complete-TmdRemocao $resultado $Modulo $Destino $Simular
    }

    if ($Simular) {
        $resultado.Status = 'Simulado'
        $resultado.Liberado = (Measure-TmdTamanho -Caminho $alvo).Bytes
        return Complete-TmdRemocao $resultado $Modulo $Destino $Simular
    }

    try {
        if ($Destino -eq 'Lixeira') {
            $tamanho = (Measure-TmdTamanho -Caminho $alvo).Bytes
            Move-TmdParaLixeira -Caminho $alvo
            if (Test-Path -LiteralPath $alvo) { throw 'continua no lugar depois de enviar para a Lixeira' }
            $resultado.Status = 'Feito'
            $resultado.Liberado = $tamanho
        }
        elseif ($item -is [IO.FileInfo]) {
            $tamanho = $item.Length
            Remove-TmdArquivo -Arquivo $item
            $resultado.Status = 'Feito'
            $resultado.Liberado = $tamanho
        }
        else {
            $totais = New-TmdTotais
            Remove-TmdConteudo -Pasta $item -Totais $totais -Protecao $protecao
            Remove-TmdPastaVazia -Pasta $item -Totais $totais
            $resultado.Liberado = $totais.Bytes
            $resultado.Motivo = Get-TmdMotivoPulados $totais
            $resultado.Status = if (-not $resultado.Motivo) { 'Feito' } elseif ($totais.Removidos -gt 0) { 'Parcial' } else { 'Ignorado' }
        }
    }
    catch {
        $ex = Get-TmdExcecaoInterna $_.Exception
        $resultado.Status = if ($ex -is [IO.IOException]) { 'Ignorado' } else { 'Erro' }
        $resultado.Motivo = if ($ex -is [IO.IOException]) { "em uso: $($ex.Message)" } else { $ex.Message }
    }
    Complete-TmdRemocao $resultado $Modulo $Destino $Simular
}

function Complete-TmdRemocao {
    param($Resultado, [string]$Modulo, [string]$Destino, [bool]$Simular)
    Write-TmdOperacao -Modulo $Modulo -Id $Resultado.Id -Acao 'remover' -Caminho $Resultado.Caminho -Destino $Destino `
        -Status $Resultado.Status -Liberado $Resultado.Liberado -Motivo $Resultado.Motivo -Simulado $Simular
    $Resultado
}

function New-TmdTotais {
    [pscustomobject]@{ Bytes = [int64]0; Removidos = 0; EmUso = 0; SemAcesso = 0; Links = 0; Protegidos = 0; Outros = 0; PrimeiroErro = '' }
}

function Get-TmdExcecaoInterna {
    param($Excecao)
    while ($Excecao.InnerException) { $Excecao = $Excecao.InnerException }
    $Excecao
}

# Arquivo temporário do próprio Tamanduá (ex.: o JSON do "winget export"): só nomes "tamandua-*" direto na pasta temporária.
function New-TmdArquivoTemporario {
    [CmdletBinding()]
    param([string]$Extensao = '.tmp')
    Join-Path ([IO.Path]::GetTempPath()) "tamandua-$([guid]::NewGuid().ToString('N'))$Extensao"
}

function Remove-TmdArquivoTemporario {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Caminho)
    $completo = [IO.Path]::GetFullPath($Caminho)
    $temp = [IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\')
    if ((Split-Path -Parent $completo) -ne $temp -or (Split-Path -Leaf $completo) -notlike 'tamandua-*') {
        throw "não é um temporário do Tamanduá: $Caminho"
    }
    if (Test-Path -LiteralPath $completo -PathType Leaf) { [IO.File]::Delete($completo) }
}

function Test-TmdProtegidoPorPadrao {
    param([string]$Caminho, [string[]]$Protecao)
    foreach ($p in $Protecao) { if ($Caminho -like $p) { return $true } }
    $false
}

function Remove-TmdArquivo {
    param([Parameter(Mandatory)][IO.FileInfo]$Arquivo)
    try {
        [IO.File]::Delete($Arquivo.FullName)
    }
    catch {
        $ex = Get-TmdExcecaoInterna $_.Exception
        if (-not ($ex -is [UnauthorizedAccessException]) -or -not ($Arquivo.Attributes -band [IO.FileAttributes]::ReadOnly)) { throw }
        # Somente leitura: tira o atributo e tenta de novo.
        $Arquivo.Attributes = $Arquivo.Attributes -band (-bnot [IO.FileAttributes]::ReadOnly)
        [IO.File]::Delete($Arquivo.FullName)
    }
}

# Apaga o conteúdo de uma pasta. Links são pulados (nunca seguidos nem apagados); erros contam e seguem.
# A lista de proteção vale também para o que está DENTRO da pasta (ex.: uma chave .pem esquecida num cache).
function Remove-TmdConteudo {
    param([Parameter(Mandatory)][IO.DirectoryInfo]$Pasta, [Parameter(Mandatory)]$Totais, [string[]]$Protecao = @())

    try {
        $itens = @($Pasta.EnumerateFileSystemInfos())
    }
    catch {
        $Totais.SemAcesso++
        return
    }
    foreach ($item in $itens) {
        if ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) {
            $Totais.Links++
            continue
        }
        if ((Test-TmdNomeProtegido $item.FullName) -or (Test-TmdProtegidoPorPadrao -Caminho $item.FullName -Protecao $Protecao)) {
            $Totais.Protegidos++
            continue
        }
        if ($item -is [IO.DirectoryInfo]) {
            Remove-TmdConteudo -Pasta $item -Totais $Totais -Protecao $Protecao
            Remove-TmdPastaVazia -Pasta $item -Totais $Totais
            continue
        }
        $tamanho = $item.Length
        try {
            Remove-TmdArquivo -Arquivo $item
            $Totais.Bytes += $tamanho
            $Totais.Removidos++
        }
        catch {
            Add-TmdFalha -Totais $Totais -Excecao (Get-TmdExcecaoInterna $_.Exception)
        }
    }
}

# Só apaga a pasta se ficou vazia; se sobrou algo, o motivo já foi contado no conteúdo.
function Remove-TmdPastaVazia {
    param([Parameter(Mandatory)][IO.DirectoryInfo]$Pasta, [Parameter(Mandatory)]$Totais)
    $Pasta.Refresh()
    if (-not $Pasta.Exists) { return }
    if (@($Pasta.EnumerateFileSystemInfos()).Count -gt 0) { return }
    try {
        $Pasta.Delete($false)
    }
    catch {
        Add-TmdFalha -Totais $Totais -Excecao (Get-TmdExcecaoInterna $_.Exception)
    }
}

function Add-TmdFalha {
    param($Totais, $Excecao)
    if ($Excecao -is [UnauthorizedAccessException]) { $Totais.SemAcesso++ }
    elseif ($Excecao -is [IO.IOException]) { $Totais.EmUso++ }
    else { $Totais.Outros++ }
    if (-not $Totais.PrimeiroErro) { $Totais.PrimeiroErro = $Excecao.Message }
}

function Get-TmdMotivoPulados {
    param($Totais)
    $partes = @()
    if ($Totais.EmUso) { $partes += "$($Totais.EmUso) em uso" }
    if ($Totais.SemAcesso) { $partes += "$($Totais.SemAcesso) sem acesso" }
    if ($Totais.Links) { $partes += "$($Totais.Links) link(s) ignorado(s)" }
    if ($Totais.Protegidos) { $partes += "$($Totais.Protegidos) protegido(s) pela lista de proteção" }
    if ($Totais.Outros) { $partes += "$($Totais.Outros) com erro ($($Totais.PrimeiroErro))" }
    if ($partes.Count -eq 0) { return '' }
    "pulados: $($partes -join ', ')"
}

# Tamanho em bytes de um arquivo ou pasta, sem entrar em links e sem parar em pastas sem acesso.
function Measure-TmdTamanho {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Caminho)

    $total = [pscustomobject]@{ Bytes = [int64]0; Arquivos = 0; Inacessiveis = 0 }
    $item = Get-Item -LiteralPath $Caminho -Force -ErrorAction SilentlyContinue
    if (-not $item) { return $total }
    if ($item -is [IO.FileInfo]) {
        $total.Bytes = $item.Length
        $total.Arquivos = 1
        return $total
    }
    if ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) { return $total }

    # Em C#: um loop em PowerShell leva dezenas de segundos numa pasta com centenas de milhares de arquivos.
    Initialize-TmdTipos
    $medida = [Tamandua.Medidor]::Medir($item.FullName)
    $total.Bytes = $medida[0]
    $total.Arquivos = [int]$medida[1]
    $total.Inacessiveis = [int]$medida[2]
    $total
}

# Tipos em C# do núcleo, compilados uma vez por processo e só quando alguém precisa (compilar custa ~0,3 s,
# e a maioria das páginas não precisa). Medidor: soma recursiva sem entrar em links; pasta que não dá para
# listar conta em [2] e segue. Cpu: tempos do processador, para o uso de CPU sem o Win32_Processor (que leva 1 s).
# A interface aquece isso em segundo plano ao abrir; a trava evita dois runspaces compilando ao mesmo tempo.
function Initialize-TmdTipos {
    if ('Tamandua.Cpu' -as [type]) { return }
    $trava = [Threading.Mutex]::new($false, "Local\TamanduaTipos$PID")
    [void]$trava.WaitOne()
    try {
        if ('Tamandua.Cpu' -as [type]) { return }
        Add-TmdTipos
    }
    finally {
        $trava.ReleaseMutex()
        $trava.Dispose()
    }
}

function Add-TmdTipos {
    Add-Type -TypeDefinition @'
namespace Tamandua {
    public static class Cpu {
        [System.Runtime.InteropServices.DllImport("kernel32.dll")]
        private static extern bool GetSystemTimes(out long ocioso, out long nucleo, out long usuario);
        // [0] = ocioso, [1] = total (núcleo já inclui o ocioso)
        public static long[] Tempos() {
            long o, n, u;
            if (!GetSystemTimes(out o, out n, out u)) throw new System.ComponentModel.Win32Exception();
            return new long[] { o, n + u };
        }
    }
    public static class LixeiraApi {
        [System.Runtime.InteropServices.StructLayout(System.Runtime.InteropServices.LayoutKind.Sequential)]
        private struct Consulta { public int cbSize; public long i64Size; public long i64NumItems; }
        [System.Runtime.InteropServices.DllImport("shell32.dll", CharSet = System.Runtime.InteropServices.CharSet.Unicode)]
        private static extern int SHQueryRecycleBin(string raiz, ref Consulta info);
        [System.Runtime.InteropServices.DllImport("shell32.dll", CharSet = System.Runtime.InteropServices.CharSet.Unicode)]
        private static extern int SHEmptyRecycleBin(System.IntPtr janela, string raiz, uint opcoes);
        // [0] = bytes, [1] = itens, de todas as unidades
        public static long[] Medir() {
            var c = new Consulta();
            c.cbSize = System.Runtime.InteropServices.Marshal.SizeOf(typeof(Consulta));
            int r = SHQueryRecycleBin(null, ref c);
            if (r != 0) throw new System.ComponentModel.Win32Exception(r);
            return new long[] { c.i64Size, c.i64NumItems };
        }
        // Sem perguntar, sem barra de progresso, sem som.
        public static int Esvaziar() { return SHEmptyRecycleBin(System.IntPtr.Zero, null, 0x1 | 0x2 | 0x4); }
    }
    public static class Icones {
        [System.Runtime.InteropServices.DllImport("shell32.dll", CharSet = System.Runtime.InteropServices.CharSet.Unicode)]
        private static extern uint ExtractIconEx(string arquivo, int indice, System.IntPtr[] grandes, System.IntPtr[] pequenos, uint quantos);
        [System.Runtime.InteropServices.DllImport("user32.dll")]
        private static extern bool DestroyIcon(System.IntPtr icone);
        // Ícone grande (32x32) do arquivo (exe, dll ou ico) como PNG; null se não tiver.
        public static byte[] Png(string arquivo, int indice) {
            var grandes = new System.IntPtr[1];
            if (ExtractIconEx(arquivo, indice, grandes, null, 1) == 0 || grandes[0] == System.IntPtr.Zero) return null;
            try {
                using (var icone = System.Drawing.Icon.FromHandle(grandes[0]))
                using (var imagem = icone.ToBitmap())
                using (var saida = new System.IO.MemoryStream()) {
                    imagem.Save(saida, System.Drawing.Imaging.ImageFormat.Png);
                    return saida.ToArray();
                }
            }
            finally { DestroyIcon(grandes[0]); }
        }
    }
    public static class Texto {
        [System.Runtime.InteropServices.DllImport("shlwapi.dll", CharSet = System.Runtime.InteropServices.CharSet.Unicode)]
        private static extern int SHLoadIndirectString(string fonte, System.Text.StringBuilder saida, int tamanho, System.IntPtr reservado);
        // "@shell32.dll,-8506" e afins -> texto no idioma do Windows; se não der, devolve a entrada.
        public static string Indireto(string fonte) {
            if (string.IsNullOrEmpty(fonte) || fonte[0] != '@') return fonte;
            var sb = new System.Text.StringBuilder(1024);
            return SHLoadIndirectString(fonte, sb, sb.Capacity, System.IntPtr.Zero) == 0 ? sb.ToString() : fonte;
        }
    }
    public static class Medidor {
        // [0] = bytes, [1] = arquivos, [2] = pastas sem acesso
        public static long[] Medir(string caminho) {
            long[] t = new long[3];
            var pilha = new System.Collections.Generic.Stack<System.IO.DirectoryInfo>();
            pilha.Push(new System.IO.DirectoryInfo(caminho));
            while (pilha.Count > 0) {
                var pasta = pilha.Pop();
                System.IO.FileSystemInfo[] itens;
                try { itens = pasta.GetFileSystemInfos(); }
                catch { t[2]++; continue; }
                foreach (var i in itens) {
                    if ((i.Attributes & System.IO.FileAttributes.ReparsePoint) != 0) continue;
                    var sub = i as System.IO.DirectoryInfo;
                    if (sub != null) { pilha.Push(sub); continue; }
                    try { t[0] += ((System.IO.FileInfo)i).Length; t[1]++; } catch { }
                }
            }
            return t;
        }
    }
}
'@ -ReferencedAssemblies System.Drawing
}

# Nome legível de um texto do registro como "@shell32.dll,-8506" (no idioma do Windows).
function Get-TmdTextoIndireto {
    [CmdletBinding()]
    param([AllowEmptyString()][string]$Texto)
    if (-not $Texto -or -not $Texto.StartsWith('@')) { return $Texto }
    Initialize-TmdTipos
    [Tamandua.Texto]::Indireto($Texto)
}

$script:CacheIcones = @{}

# Ícone de "arquivo.exe", "arquivo.dll,3" ou '"C:\x\a.exe",0' (o formato do DisplayIcon) como PNG 32x32; $null se não der.
# Guardado por caminho: a página de programas pede os mesmos ícones toda vez que abre.
function Get-TmdIconePng {
    [CmdletBinding()]
    param([AllowEmptyString()][string]$Caminho)
    if (-not $Caminho) { return $null }
    # Vírgula só com ícone: ", $null" viraria uma lista com um item vazio.
    if ($script:CacheIcones.ContainsKey($Caminho)) { $g = $script:CacheIcones[$Caminho]; if ($null -eq $g) { return $null }; return , $g }
    $arquivo = $Caminho.Trim()
    $indice = 0
    if ($arquivo -match '^(.*?),\s*(-?\d+)$') { $arquivo = $Matches[1]; $indice = [int]$Matches[2] }
    $arquivo = [Environment]::ExpandEnvironmentVariables($arquivo.Trim().Trim('"'))
    $png = $null
    try {
        # PNG pronto (ícones que vêm com o projeto): só confere a assinatura e usa como está.
        if ($arquivo -like '*.png' -and [IO.File]::Exists($arquivo)) {
            $bytes = [IO.File]::ReadAllBytes($arquivo)
            if ($bytes.Length -gt 8 -and $bytes[0] -eq 0x89 -and $bytes[1] -eq 0x50 -and $bytes[2] -eq 0x4E -and $bytes[3] -eq 0x47) { $png = $bytes }
        }
        # Atalho (.lnk): o ícone é o que o atalho mostra (IconLocation) ou o do programa para onde ele aponta. Só lê.
        elseif ($arquivo -like '*.lnk' -and [IO.File]::Exists($arquivo)) {
            $atalho = (New-Object -ComObject WScript.Shell).CreateShortcut($arquivo)
            $local = [string]$atalho.IconLocation
            $alvo = if ($local -and $local -notmatch '^,\s*-?\d+$') { $local } else { [string]$atalho.TargetPath }
            if ($alvo -and $alvo -notlike '*.lnk') { $png = Get-TmdIconePng -Caminho $alvo }
        }
        elseif ([IO.File]::Exists($arquivo)) {
            Initialize-TmdTipos
            $png = [Tamandua.Icones]::Png($arquivo, $indice)
        }
    }
    catch { Write-Verbose "sem ícone em $Caminho`: $($_.Exception.Message)" }
    $script:CacheIcones[$Caminho] = $png
    if ($null -eq $png) { return $null }
    , $png
}

# O primeiro dos -Caminhos que tem ícone (ver Get-TmdCandidatosIcone).
function Get-TmdIconePngPrimeiro {
    [CmdletBinding()]
    param([AllowEmptyCollection()][string[]]$Caminhos = @())
    foreach ($c in $Caminhos) {
        $png = Get-TmdIconePng -Caminho $c
        if ($null -ne $png) { return , $png }
    }
    $null
}

# Onde achar o ícone de um programa instalado, na ordem: DisplayIcon; o .ico que o instalador MSI deixa em
# Windows\Installer\{código}; o .exe da pasta de instalação com nome parecido; o atalho do menu Iniciar; o desinstalador
# (que muitas vezes tem o ícone do programa). Só monta a lista (barato); extrair fica para Get-TmdIconePngPrimeiro.
function Get-TmdCandidatosIcone {
    [CmdletBinding()]
    param([string]$DisplayIcon, [string]$Chave, [string]$Nome, [string]$Pasta, [string]$Desinstalador)
    $lista = [System.Collections.Generic.List[string]]::new()
    if ($DisplayIcon) { $lista.Add($DisplayIcon) }
    try {
        if ($Chave -match '^\{[0-9A-Fa-f-]{36}\}$') {
            $msi = Join-Path $env:SystemRoot "Installer\$Chave"
            if ([IO.Directory]::Exists($msi)) {
                foreach ($f in [IO.Directory]::GetFiles($msi)) { if ($f -match '\.(ico|exe)$') { $lista.Add($f) } }
            }
        }
        $simples = ConvertTo-TmdNomeSimples $Nome
        $pastaReal = if ($Pasta) { [Environment]::ExpandEnvironmentVariables($Pasta.Trim().Trim('"')) } else { '' }
        if ($pastaReal -and [IO.Directory]::Exists($pastaReal)) {
            $exes = @([IO.Directory]::GetFiles($pastaReal, '*.exe') | Where-Object { [IO.Path]::GetFileName($_) -notmatch '^(unins|uninst|setup|install|update|crash|helper|elevate)' })
            # Primeiro o que tem o nome do programa ("KeePassXC.exe" para "KeePassXC"), depois os outros.
            foreach ($e in $exes) { $n = ConvertTo-TmdNomeSimples ([IO.Path]::GetFileNameWithoutExtension($e)); if ($n.Length -ge 3 -and $simples.StartsWith($n)) { $lista.Add($e) } }
            foreach ($e in $exes) { if (-not $lista.Contains($e)) { $lista.Add($e) } }
        }
        foreach ($l in Find-TmdAtalhoIniciar -Simples $simples) { $lista.Add($l) }
        if ($Desinstalador -and $Desinstalador -notmatch '(?i)msiexec|rundll32') {
            $exe = if ($Desinstalador -match '^\s*"([^"]+)"') { $Matches[1] } elseif ($Desinstalador -match '^\s*(.+?\.exe)') { $Matches[1] } else { '' }
            if ($exe) { $lista.Add($exe) }
        }
    }
    catch { Write-Verbose "candidatos de ícone para $Nome`: $($_.Exception.Message)" }
    # Sai item a item: quem chama embrulha com @( ).
    $lista | Select-Object -Unique
}

# Atalhos do menu Iniciar (de todos e do usuário) cujo nome bate com o do programa ("LibreOffice" para
# "LibreOffice 26.8.1.1"). A lista de atalhos é lida uma vez.
$script:AtalhosIniciar = $null
function Find-TmdAtalhoIniciar {
    param([string]$Simples)
    if (-not $Simples) { return }
    if ($null -eq $script:AtalhosIniciar) {
        $script:AtalhosIniciar = @(foreach ($p in [Environment]::GetFolderPath('CommonPrograms'), [Environment]::GetFolderPath('Programs')) {
                if ($p -and [IO.Directory]::Exists($p)) {
                    foreach ($l in [IO.Directory]::GetFiles($p, '*.lnk', [IO.SearchOption]::AllDirectories)) {
                        [pscustomobject]@{ Simples = ConvertTo-TmdNomeSimples ([IO.Path]::GetFileNameWithoutExtension($l)); Caminho = $l }
                    }
                }
            })
    }
    foreach ($a in $script:AtalhosIniciar) {
        if ($a.Simples -eq $Simples) { $a.Caminho }
    }
    foreach ($a in $script:AtalhosIniciar) {
        if ($a.Simples -ne $Simples -and $a.Simples.Length -ge 4 -and $a.Simples -notmatch '^(uninstall|desinstalar|readme|leiame|help|ajuda)' -and
            ($Simples.StartsWith($a.Simples) -or $a.Simples.StartsWith($Simples))) { $a.Caminho }
    }
}

# Programas instalados (chaves Uninstall de 64 e 32 bits e do usuário): nome simplificado -> candidatos de ícone.
function Get-TmdIconesInstalados {
    [CmdletBinding()]
    param()
    $mapa = @{}
    foreach ($f in @(@('LocalMachine', 'Registry64'), @('LocalMachine', 'Registry32'), @('CurrentUser', 'Registry64'))) {
        $base = [Microsoft.Win32.RegistryKey]::OpenBaseKey($f[0], $f[1])
        try {
            $raiz = $base.OpenSubKey('SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall', $false)
            if (-not $raiz) { continue }
            try {
                foreach ($n in $raiz.GetSubKeyNames()) {
                    $k = $raiz.OpenSubKey($n, $false)
                    if (-not $k) { continue }
                    try {
                        $nome = [string]$k.GetValue('DisplayName')
                        if ($nome) {
                            $mapa[(ConvertTo-TmdNomeSimples $nome)] = @(Get-TmdCandidatosIcone -DisplayIcon ([string]$k.GetValue('DisplayIcon')) -Chave $n -Nome $nome `
                                    -Pasta ([string]$k.GetValue('InstallLocation')) -Desinstalador ([string]$k.GetValue('UninstallString')))
                        }
                    }
                    finally { $k.Close() }
                }
            }
            finally { $raiz.Close() }
        }
        finally { $base.Close() }
    }
    $mapa
}

# "7-Zip 24.08 (x64)" -> "7zip2408x64": para comparar nomes de programa sem espaço, pontuação e maiúsculas.
# Find-Alvos do módulo para a janela. Em módulo com Visualizacao = 'Grade', cada alvo com Icone ganha
# IconePng: extrair aqui (em segundo plano) não trava a tela.
function Get-TmdAlvosParaTela {
    param([Parameter(Mandatory)]$Info)
    $grade = $Info.Manifesto -and $Info.Manifesto['Visualizacao'] -eq 'Grade'
    foreach ($a in & $Info.Modulo.ExportedFunctions['Find-Alvos']) {
        # Icone: um caminho ou a lista de candidatos (Get-TmdCandidatosIcone); vale o primeiro que tiver ícone.
        if ($grade -and $a.PSObject.Properties['Icone'] -and $a.Icone) {
            $a | Add-Member -NotePropertyName IconePng -NotePropertyValue (Get-TmdIconePngPrimeiro -Caminhos @($a.Icone)) -Force
        }
        $a
    }
}

function ConvertTo-TmdNomeSimples {
    param([string]$Nome)
    ($Nome.ToLowerInvariant() -replace '[^a-z0-9]', '')
}

# Uso do processador (0 a 100) num intervalo, como o Gerenciador de Tarefas mostra.
# Para não ficar parado esperando: $m = Start-TmdMedidaCpu; (lê outras coisas); Get-TmdUsoCpu -Desde $m
# (só espera o que faltar para completar -IntervaloMs).

function Start-TmdMedidaCpu {
    Initialize-TmdTipos
    [pscustomobject]@{ Tempos = [Tamandua.Cpu]::Tempos(); Relogio = [Diagnostics.Stopwatch]::StartNew() }
}

function Get-TmdUsoCpu {
    [CmdletBinding()]
    param([int]$IntervaloMs = 250, $Desde)
    if (-not $Desde) { $Desde = Start-TmdMedidaCpu }
    $falta = $IntervaloMs - [int]$Desde.Relogio.ElapsedMilliseconds
    if ($falta -gt 0) { Start-Sleep -Milliseconds $falta }
    $a = $Desde.Tempos
    $b = [Tamandua.Cpu]::Tempos()
    $total = $b[1] - $a[1]
    if ($total -le 0) { return 0 }
    [int][Math]::Round(100 * ($total - ($b[0] - $a[0])) / $total)
}

# Lixeira pela API do Explorer (SHFileOperation), sem nenhuma janela ou pergunta.
# Testes: TAMANDUA_LIXEIRA_TESTE (uma pasta dentro do TEMP) recebe os itens no lugar da Lixeira real.
function Move-TmdParaLixeira {
    param([Parameter(Mandatory)][string]$Caminho)

    $falsa = Get-TmdLixeiraFalsa
    if ($falsa) {
        [void][IO.Directory]::CreateDirectory($falsa)
        $destino = Join-Path $falsa ("{0}-{1}" -f [guid]::NewGuid().ToString('N').Substring(0, 8), (Split-Path -Leaf $Caminho))
        if (Test-Path -LiteralPath $Caminho -PathType Container) { [IO.Directory]::Move($Caminho, $destino) } else { [IO.File]::Move($Caminho, $destino) }
        return
    }

    if (-not ('Tamandua.Lixeira' -as [type])) {
        Add-Type -Namespace Tamandua -Name Lixeira -MemberDefinition @'
[StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
public struct OperacaoArquivo {
    public IntPtr hwnd; public uint wFunc; public string pFrom; public string pTo; public ushort fFlags;
    public bool fAnyOperationsAborted; public IntPtr hNameMappings; public string lpszProgressTitle;
}
[DllImport("shell32.dll", CharSet = CharSet.Unicode)]
private static extern int SHFileOperation(ref OperacaoArquivo op);
// FO_DELETE com FOF_ALLOWUNDO | FOF_NOCONFIRMATION | FOF_NOERRORUI | FOF_SILENT
public static int Enviar(string caminho) {
    var op = new OperacaoArquivo();
    op.wFunc = 3;
    op.pFrom = caminho + "\0\0";
    op.fFlags = 0x0040 | 0x0010 | 0x0400 | 0x0004;
    return SHFileOperation(ref op);
}
'@
    }
    $codigo = [Tamandua.Lixeira]::Enviar($Caminho)
    if ($codigo -ne 0) { throw "a Lixeira recusou (código $codigo)" }
}

# Lixeira falsa dos testes (TAMANDUA_LIXEIRA_TESTE), só se estiver dentro da pasta temporária; senão $null.
function Get-TmdLixeiraFalsa {
    $falsa = $env:TAMANDUA_LIXEIRA_TESTE
    if (-not $falsa) { return $null }
    $temp = [IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\')
    $falsa = [IO.Path]::GetFullPath($falsa).TrimEnd('\')
    if (-not $falsa.StartsWith($temp + '\', [StringComparison]::OrdinalIgnoreCase)) { throw 'TAMANDUA_LIXEIRA_TESTE precisa estar dentro da pasta temporária' }
    $falsa
}

# Quanto há na Lixeira (todas as unidades). Só leitura.
function Get-TmdLixeira {
    [CmdletBinding()]
    param()
    $falsa = Get-TmdLixeiraFalsa
    if ($falsa) {
        $itens = @(if (Test-Path -LiteralPath $falsa) { [IO.Directory]::GetFileSystemEntries($falsa) })
        $bytes = [int64]0
        foreach ($i in $itens) { $bytes += (Measure-TmdTamanho -Caminho $i).Bytes }
        return [pscustomobject]@{ Bytes = $bytes; Itens = [int64]$itens.Count }
    }
    Initialize-TmdTipos
    $m = [Tamandua.LixeiraApi]::Medir()
    [pscustomobject]@{ Bytes = [int64]$m[0]; Itens = [int64]$m[1] }
}

# Esvazia a Lixeira de vez (não tem volta). Devolve um Resultado e registra no log como as outras remoções.
function Clear-TmdLixeira {
    [CmdletBinding()]
    param([switch]$Simular, [string]$Modulo = '', [string]$Id = '')
    $antes = Get-TmdLixeira
    $resultado = [pscustomobject]@{ Id = $Id; Caminho = 'Lixeira'; Status = 'Simulado'; Liberado = $antes.Bytes; Motivo = '' }
    if (-not $Simular) {
        $resultado.Status = 'Feito'
        if ($antes.Itens -gt 0) {
            try {
                $falsa = Get-TmdLixeiraFalsa
                if ($falsa) {
                    foreach ($i in [IO.Directory]::GetFileSystemEntries($falsa)) { [void](Remove-TmdItem -Caminho $i -Raizes $falsa -Modulo $Modulo -Id $Id) }
                }
                else {
                    Initialize-TmdTipos
                    $codigo = [Tamandua.LixeiraApi]::Esvaziar()
                    if ($codigo -ne 0) { throw "o Windows recusou (código $codigo)" }
                }
            }
            catch { $resultado.Status = 'Erro'; $resultado.Motivo = (Get-TmdExcecaoInterna $_.Exception).Message }
            $depois = Get-TmdLixeira
            $resultado.Liberado = [Math]::Max([int64]0, $antes.Bytes - $depois.Bytes)
            if ($resultado.Status -eq 'Feito' -and $depois.Itens -gt 0) { $resultado.Status = 'Parcial'; $resultado.Motivo = "$($depois.Itens) item(ns) continuaram na Lixeira" }
        }
    }
    Write-TmdOperacao -Modulo $Modulo -Id $Id -Acao 'remover' -Caminho 'Lixeira' -Destino 'Permanente' -Status $resultado.Status `
        -Liberado $resultado.Liberado -Motivo $resultado.Motivo -Simulado ([bool]$Simular)
    $resultado
}
