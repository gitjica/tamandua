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
            Remove-TmdConteudo -Pasta $item -Totais $totais
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
    [pscustomobject]@{ Bytes = [int64]0; Removidos = 0; EmUso = 0; SemAcesso = 0; Links = 0; Outros = 0; PrimeiroErro = '' }
}

function Get-TmdExcecaoInterna {
    param($Excecao)
    while ($Excecao.InnerException) { $Excecao = $Excecao.InnerException }
    $Excecao
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
function Remove-TmdConteudo {
    param([Parameter(Mandatory)][IO.DirectoryInfo]$Pasta, [Parameter(Mandatory)]$Totais)

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
        if ($item -is [IO.DirectoryInfo]) {
            Remove-TmdConteudo -Pasta $item -Totais $Totais
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

    $pilha = [System.Collections.Generic.Stack[IO.DirectoryInfo]]::new()
    $pilha.Push($item)
    while ($pilha.Count -gt 0) {
        $pasta = $pilha.Pop()
        try {
            foreach ($f in $pasta.EnumerateFileSystemInfos()) {
                if ($f.Attributes -band [IO.FileAttributes]::ReparsePoint) { continue }
                if ($f -is [IO.DirectoryInfo]) { $pilha.Push($f) }
                else {
                    $total.Bytes += $f.Length
                    $total.Arquivos++
                }
            }
        }
        catch {
            $total.Inacessiveis++
        }
    }
    $total
}

# Lixeira pela API do Explorer (SHFileOperation), sem nenhuma janela ou pergunta.
function Move-TmdParaLixeira {
    param([Parameter(Mandatory)][string]$Caminho)

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
