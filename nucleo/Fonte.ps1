# Fonte do sistema: o FontKit (ler e gravar .ttf) e a única escrita em Windows\Fonts do Tamanduá. A troca em si é
# um ajuste de registro comum (Set-TmdAjuste: snapshot, .reg e desfazer pelo Histórico); apagar cópias velhas fica
# em Remocao.ps1 (Remove-TmdCopiaFonte), como toda remoção.

# Cópia da Segoe UI gerada para trocar a fonte: "<arquivo original>_<sufixo>.ttf". Só nomes assim entram ou saem da
# pasta de fontes por aqui; as fontes de verdade do Windows nunca são tocadas.
$script:PadraoCopiaSegoe = '^(segoeui|segoeuib|segoeuii|segoeuiz|segoeuil|seguili|segoeuisl|seguisli|seguisb|seguisbi|seguibl|seguibli|SegUIVar)_[A-Za-z0-9_-]+\.ttf$'

# Compilar o FontKit leva ~1 s: só na primeira vez que alguém precisa, uma vez por processo.
function Initialize-TmdFontKit {
    [CmdletBinding()]
    param()
    if (-not ('TtFont' -as [type])) { Add-Type -Path (Join-Path $PSScriptRoot 'FontKit.cs') }
    if (-not ('TmdDpiSistema' -as [type])) {
        Add-Type -TypeDefinition @'
using System; using System.Runtime.InteropServices;
public static class TmdDpiSistema {
    [DllImport("user32.dll")] static extern IntPtr SetThreadDpiAwarenessContext(IntPtr c);
    [DllImport("user32.dll")] static extern uint GetDpiForSystem();
    // Sem consciência de DPI o Windows responde 96 para qualquer escala.
    public static uint Get() { IntPtr old = SetThreadDpiAwarenessContext(new IntPtr(-4)); uint d = GetDpiForSystem(); SetThreadDpiAwarenessContext(old); return d; }
}
'@
    }
}

# DPI do sistema (96 = 100%, 120 = 125%...), para o tamanho do texto da interface em pixels.
function Get-TmdDpiSistema {
    [CmdletBinding()]
    param()
    Initialize-TmdFontKit
    [int][TmdDpiSistema]::Get()
}

function Test-TmdNomeCopiaFonte {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Nome)
    $Nome -match $script:PadraoCopiaSegoe
}

# Põe uma cópia gerada na pasta de fontes. Nunca sobrescreve (o Windows não deixa trocar fonte em uso, e uma
# instalação nova sempre tem sufixo novo).
function Install-TmdArquivoFonte {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Origem,
        [string]$Pasta = (Join-Path $env:WINDIR 'Fonts'),
        [string]$Modulo = 'fonte',
        [string]$Id = ''
    )
    $nome = [IO.Path]::GetFileName($Origem)
    if (-not (Test-TmdNomeCopiaFonte -Nome $nome)) { throw "nome de fonte não permitido: $nome" }
    $destino = Join-Path $Pasta $nome
    if ([IO.File]::Exists($destino)) { throw "já existe $destino" }
    try {
        [IO.File]::Copy($Origem, $destino, $false)
        Write-TmdOperacao -Modulo $Modulo -Id $Id -Acao 'copiar' -Caminho $destino -Status 'Feito'
    }
    catch {
        Write-TmdOperacao -Modulo $Modulo -Id $Id -Acao 'copiar' -Caminho $destino -Status 'Erro' -Motivo (Get-TmdExcecaoInterna $_.Exception).Message
        throw
    }
    $nome
}
