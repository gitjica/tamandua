# Menu de contexto (botão direito). Liga o menu clássico no Windows 11 e tira itens, um por um:
# - itens do Windows e de programas que são extensões (COM): bloqueados pelo CLSID em "Shell Extensions\Blocked";
# - comandos sem extensão (ex.: "Abrir Git Bash aqui"): escondidos com o valor ProgrammaticAccessOnly na chave do comando;
# - itens do "Novo": a chave ShellNew sai, com cópia .reg guardada pelo núcleo para voltar;
# - "Enviar para": os atalhos ficam ocultos (nada é apagado).
# Tudo vira ajuste do motor do núcleo (snapshot, desfazer pelo Histórico). Os itens de programas são achados na hora.

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$script:Bloqueados = 'SOFTWARE\Microsoft\Windows\CurrentVersion\Shell Extensions\Blocked'
$script:Bloqueados32 = 'SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Shell Extensions\Blocked'
# Onde o Explorador procura itens do menu de arquivos, pastas, fundo da pasta e unidades.
$script:Raizes = [ordered]@{ '*' = 'arquivos'; 'AllFilesystemObjects' = 'arquivos e pastas'; 'Directory' = 'pastas'; 'Directory\Background' = 'fundo da pasta'; 'Folder' = 'pastas'; 'Drive' = 'unidades' }
$script:Imagens = '.bmp', '.dib', '.gif', '.jfif', '.jpe', '.jpeg', '.jpg', '.png', '.tif', '.tiff', '.wdp', '.heic', '.webp', '.3mf', '.fbx'

# Itens do Windows. Presets: Recomendado (o que quase ninguém usa) e Limpo (tudo).
$script:ItensWindows = @(
    @{ Id = 'menu-compartilhar'; Nome = 'Compartilhar'; Clsid = @('{e2bf9676-5f8f-435c-97eb-11607a5bedf7}'); Recomendado = $true
        Explicacao = 'O "Compartilhar" do Windows (e-mail, apps próximos).' }
    @{ Id = 'menu-conceder-acesso'; Nome = 'Conceder acesso a / Compartilhar com'; Clsid = @('{f81e9010-6ea4-11ce-a7ff-00aa003ca9f6}'); Recomendado = $true
        Explicacao = 'Compartilhar a pasta na rede pelo menu. Continua dando pelas Propriedades.' }
    @{ Id = 'menu-incluir-biblioteca'; Nome = 'Incluir na biblioteca'; Clsid = @('{3dad6c5d-2167-4cae-9914-f99e41c12cfa}'); Recomendado = $true
        Explicacao = 'Bibliotecas do Windows, quase ninguém usa.' }
    @{ Id = 'menu-versoes-anteriores'; Nome = 'Restaurar versões anteriores'; Clsid = @('{596AB062-B4D2-4215-9F74-E9109B0A8153}'); Recomendado = $true
        Explicacao = 'Só funciona com Histórico de Arquivos ou pontos de restauração com cópia de arquivos.' }
    @{ Id = 'menu-transmitir'; Nome = 'Transmitir para dispositivo'; Clsid = @('{7AD84985-87B4-4a16-BE58-8B72A5B390F7}'); Recomendado = $true
        Explicacao = 'Mandar vídeo/música para TV ou Chromecast pelo menu.' }
    @{ Id = 'menu-compatibilidade'; Nome = 'Solucionar problemas de compatibilidade'; Clsid = @('{1d27f844-3a1f-4410-85ac-14651078412d}'); Recomendado = $true
        Explicacao = 'O assistente continua nas Propriedades > Compatibilidade.' }
    @{ Id = 'menu-copilot'; Nome = 'Perguntar ao Copilot'; Clsid = @('{CB3B0003-8088-4EDE-8769-8B354AB2FF8C}'); Recomendado = $true
        Explicacao = 'Mandar o arquivo para o Copilot.' }
    @{ Id = 'menu-pastas-trabalho'; Nome = 'Pastas de Trabalho'; Clsid = @('{E61BF828-5E63-4287-BEF1-60B1A4FDE0E3}'); Recomendado = $true
        Explicacao = 'Sincronização de pastas de empresa (Work Folders). Em casa, não serve para nada.' }
    @{ Id = 'menu-arquivos-offline'; Nome = 'Arquivos offline (sempre disponível)'; Clsid = @('{474C98EE-CF3D-41f5-80E3-4AAB0AB04301}'); Recomendado = $true
        Explicacao = 'Cópia offline de pastas de rede de empresa.' }
    @{ Id = 'menu-fixar-iniciar'; Nome = 'Fixar no Iniciar'; Clsid = @('{470C0EBD-5D73-4d58-9CED-E91E22E23282}', '{a2a9545d-a0c2-42b4-9708-a0b2badd77c8}')
        Explicacao = 'Continua dando para fixar pelo próprio Iniciar.' }
    @{ Id = 'menu-fixar-barra'; Nome = 'Fixar na barra de tarefas'; Clsid = @('{90AA3A4E-1CBA-4233-B8BB-535773D48449}')
        Explicacao = 'Continua dando para fixar com o botão direito no ícone do programa aberto.' }
    @{ Id = 'menu-terminal'; Nome = 'Abrir no Terminal'; Clsid = @('{9F156763-7844-4DC4-B2B1-901F640F5155}')
        Explicacao = 'Abre o Terminal do Windows na pasta.' }
    @{ Id = 'menu-bloco-notas'; Nome = 'Editar no Bloco de Notas'; Clsid = @('{CA6CC9F1-867A-481E-951E-A28C5E4F01EA}')
        Explicacao = 'O "Editar no Bloco de Notas" do Windows 11.' }
    @{ Id = 'menu-copiar-caminho'; Nome = 'Copiar como caminho'; Clsid = @('{f3d06e7c-1e45-4a26-847e-f9fcdee59be0}')
        Explicacao = 'Copia o caminho completo do arquivo. Útil para quem programa.' }
    @{ Id = 'menu-criptografia'; Nome = 'Criptografar (EFS)'; Clsid = @('{A470F8CF-A1E8-4f65-8335-227475AA5C46}')
        Explicacao = 'Criptografia de arquivo do NTFS, só nas edições Pro e superiores.' }
    @{ Id = 'menu-extrair-tudo'; Nome = 'Extrair tudo (zip)'; Clsid = @('{b8cdcb65-b1bf-4b42-9428-1dfdb7ee92af}'); Risco = 'Medio'
        Explicacao = 'O extrator de zip do Windows. Tire só se usar outro (7-Zip, WinRAR).'
        Contratempo = 'Sem outro programa de compactação, não sobra jeito fácil de extrair um .zip pelo botão direito.' }
    @{ Id = 'menu-enviar-para'; Nome = 'Enviar para (o submenu inteiro)'; Clsid = @('{7BA4C740-9E81-11CF-99D3-00AA004AE837}'); Risco = 'Medio'
        Explicacao = 'Some com o "Enviar para" todo, inclusive "Pasta compactada" e pendrives.'
        Contratempo = 'Somem junto "Pasta compactada", "Área de trabalho (criar atalho)" e o envio direto para pendrive.' }
    @{ Id = 'menu-defender'; Nome = 'Verificar com o Microsoft Defender'; Clsid = @('{09A47860-11B0-4DA5-AFA5-26D86198A780}'); Risco = 'Medio'
        Explicacao = 'Só o item do menu: o Defender continua protegendo e verificando sozinho.'
        Contratempo = 'Para verificar um arquivo baixado à mão, é preciso abrir Segurança do Windows > Proteção contra vírus > Opções de verificação.' }
    @{ Id = 'menu-abrir-nova-aba'; Nome = 'Abrir em nova guia'; Verbo = @('Folder\shell\opennewtab')
        Explicacao = 'O "Abrir em nova guia" do Explorador do Windows 11 (clicar com a rodinha faz o mesmo).' }
    @{ Id = 'menu-bitlocker'; Nome = 'Itens do BitLocker nas unidades'; Verbo = @('Drive\shell\encrypt-bde', 'Drive\shell\encrypt-bde-elev', 'Drive\shell\manage-bde', 'Drive\shell\resume-bde', 'Drive\shell\resume-bde-elev'); Recomendado = $true
        Explicacao = '"Ativar o BitLocker" e afins no botão direito das unidades. O BitLocker continua no Painel de Controle.' }
    @{ Id = 'menu-paint3d'; Nome = 'Editar com Paint 3D'; Verbo = @(foreach ($e in $script:Imagens) { "SystemFileAssociations\$e\Shell\3D Edit" }); Recomendado = $true
        Explicacao = 'O Paint 3D foi descontinuado.' }
    @{ Id = 'menu-papel-parede'; Nome = 'Definir como plano de fundo'; Verbo = @(foreach ($e in $script:Imagens) { "SystemFileAssociations\$e\Shell\setdesktopwallpaper" })
        Explicacao = 'Nas imagens. Continua dando pelas Configurações > Personalização.' }
    @{ Id = 'menu-novo-bitmap'; Nome = 'Novo > Imagem de bitmap'; Novo = @('.bmp\ShellNew'); Recomendado = $true; Explicacao = 'Some do submenu "Novo".' }
    @{ Id = 'menu-novo-rtf'; Nome = 'Novo > Documento de Rich Text'; Novo = @('.rtf\ShellNew'); Recomendado = $true; Explicacao = 'Some do submenu "Novo".' }
    @{ Id = 'menu-novo-contato'; Nome = 'Novo > Contato'; Novo = @('.contact\ShellNew'); Recomendado = $true; Explicacao = 'Some do submenu "Novo".' }
    @{ Id = 'menu-novo-biblioteca'; Nome = 'Novo > Biblioteca'; Novo = @('.library-ms\ShellNew'); Recomendado = $true; Explicacao = 'Some do submenu "Novo".' }
    @{ Id = 'menu-novo-zip'; Nome = 'Novo > Pasta compactada'; Novo = @('.zip\CompressedFolder\ShellNew'); Explicacao = 'Some do submenu "Novo" (compactar arquivos continua pelo "Enviar para").' }
    @{ Id = 'menu-enviar-para-limpo'; Nome = 'Enviar para: sem e-mail, fax e afins'; EnviarPara = $true; Recomendado = $true
        Explicacao = 'Esconde esses atalhos do "Enviar para". Pendrives, área de trabalho e pasta compactada ficam.' }
)

function Test-Requisitos {
    @{ Ok = $true; Motivo = '' }
}

# Testes: TAMANDUA_REGISTRO_TESTE redireciona o registro (só em HKCU:\Software\TamanduaTestes): o módulo lê as
# classes de dentro dela e o motor escreve lá. Itens que mexem em chave inteira, arquivos ou no Explorador ficam de fora.
function Get-RaizRegistroPadrao {
    $r = $env:TAMANDUA_REGISTRO_TESTE
    if ($r -and $r -like 'HKCU:\Software\TamanduaTestes\*') { return $r }
    ''
}

# ---------- Leitura do registro (só leitura; na área de testes, dentro da chave de teste) ----------

function Open-Chave {
    param([ValidateSet('HKLM', 'HKCU')][string]$Hive, [string]$Sub, [string]$RaizRegistro)
    if ($RaizRegistro) {
        $base = [Microsoft.Win32.RegistryKey]::OpenBaseKey('CurrentUser', 'Registry64')
        $Sub = ($RaizRegistro -replace '^HKCU:\\', '') + "\$Hive\$Sub"
    }
    else { $base = [Microsoft.Win32.RegistryKey]::OpenBaseKey($(if ($Hive -eq 'HKLM') { 'LocalMachine' } else { 'CurrentUser' }), 'Registry64') }
    try { $base.OpenSubKey($Sub, $false) } finally { $base.Close() }
}

# Como o HKCR: classes do usuário por cima das da máquina. Devolve a chave e onde ela está de verdade.
function Get-ChaveClasse {
    param([string]$Sub, [string]$RaizRegistro)
    foreach ($h in @(@('HKCU', 'Software\Classes'), @('HKLM', 'SOFTWARE\Classes'))) {
        $k = Open-Chave -Hive $h[0] -Sub "$($h[1])\$Sub" -RaizRegistro $RaizRegistro
        if ($k) { return [pscustomobject]@{ Chave = $k; Caminho = "$($h[0]):\$($h[1])\$Sub" } }
    }
    $null
}

function Get-NomesSubchave {
    param([string]$Sub, [string]$RaizRegistro)
    $nomes = foreach ($h in @(@('HKCU', 'Software\Classes'), @('HKLM', 'SOFTWARE\Classes'))) {
        $k = Open-Chave -Hive $h[0] -Sub "$($h[1])\$Sub" -RaizRegistro $RaizRegistro
        if ($k) { try { $k.GetSubKeyNames() } finally { $k.Close() } }
    }
    @($nomes | Select-Object -Unique)
}

function Test-ClsidRegistrado {
    param([string]$Clsid, [string]$RaizRegistro)
    $c = Get-ChaveClasse -Sub "CLSID\$Clsid" -RaizRegistro $RaizRegistro
    if ($c) { $c.Chave.Close(); return $true }
    $false
}

# Programa de terceiros = arquivo fora da pasta do Windows (driver de vídeo em DriverStore conta como programa).
function Test-DeTerceiros {
    param([string]$Arquivo)
    # Sem pasta (ex.: "cmd.exe"): vem do PATH do sistema, é do Windows.
    if (-not $Arquivo -or -not $Arquivo.Contains('\')) { return $false }
    $windows = [Environment]::GetFolderPath('Windows').TrimEnd('\') + '\'
    -not $Arquivo.StartsWith($windows, [StringComparison]::OrdinalIgnoreCase) -or $Arquivo -match '\\DriverStore\\'
}

function Get-ArquivoDoComando {
    param([string]$Comando)
    $c = [Environment]::ExpandEnvironmentVariables($Comando.Trim())
    if ($c -match '^"([^"]+)"') { return $Matches[1] }
    if ($c -match '^(\S+\.(exe|dll|cmd|bat))') { return $Matches[1] }
    ''
}

function Get-NomeProduto {
    param([string]$Arquivo, [string]$Reserva)
    try {
        if ($Arquivo -and [IO.File]::Exists($Arquivo)) {
            $v = [Diagnostics.FileVersionInfo]::GetVersionInfo($Arquivo)
            foreach ($n in $v.ProductName, $v.FileDescription, $v.CompanyName) { if ($n -and $n.Trim()) { return $n.Trim() } }
        }
    }
    catch { Write-Verbose "sem nome de produto para $Arquivo" }
    $Reserva
}

# Itens de programas: extensões (agrupadas pelo CLSID) e comandos (agrupados pelo nome do comando).
function Get-ItemTerceiros {
    param([string]$RaizRegistro)
    $extensoes = [ordered]@{}
    $verbos = [ordered]@{}
    foreach ($r in $script:Raizes.Keys) {
        foreach ($n in Get-NomesSubchave -Sub "$r\shellex\ContextMenuHandlers" -RaizRegistro $RaizRegistro) {
            $h = Get-ChaveClasse -Sub "$r\shellex\ContextMenuHandlers\$n" -RaizRegistro $RaizRegistro
            if (-not $h) { continue }
            $clsid = try { [string]$h.Chave.GetValue('') } finally { $h.Chave.Close() }
            if (-not $clsid -and $n -match '^\{[0-9A-Fa-f-]{36}\}$') { $clsid = $n }
            if ($clsid -notmatch '^\{[0-9A-Fa-f-]{36}\}$') { continue }
            $s = Get-ChaveClasse -Sub "CLSID\$clsid\InprocServer32" -RaizRegistro $RaizRegistro
            $dll = if ($s) { try { [Environment]::ExpandEnvironmentVariables([string]$s.Chave.GetValue('')) } finally { $s.Chave.Close() } } else { '' }
            if (-not (Test-DeTerceiros $dll)) { continue }
            $k = $clsid.ToLowerInvariant()
            if (-not $extensoes.Contains($k)) { $extensoes[$k] = @{ Clsid = $clsid; Nome = (Get-NomeProduto $dll $n); Onde = [System.Collections.Generic.List[string]]::new(); Arquivo = $dll } }
            if ($extensoes[$k].Onde -notcontains $script:Raizes[$r]) { $extensoes[$k].Onde.Add($script:Raizes[$r]) }
        }
        foreach ($n in Get-NomesSubchave -Sub "$r\shell" -RaizRegistro $RaizRegistro) {
            $v = Get-ChaveClasse -Sub "$r\shell\$n" -RaizRegistro $RaizRegistro
            if (-not $v) { continue }
            try {
                $rotulo = [string]$v.Chave.GetValue('MUIVerb'); if (-not $rotulo) { $rotulo = [string]$v.Chave.GetValue('') }
                $cmd = $v.Chave.OpenSubKey('command'); $comando = if ($cmd) { try { [string]$cmd.GetValue('') } finally { $cmd.Close() } } else { '' }
            }
            finally { $v.Chave.Close() }
            $exe = Get-ArquivoDoComando $comando
            if (-not (Test-DeTerceiros $exe)) { continue }
            $k = $n.ToLowerInvariant()
            if (-not $verbos.Contains($k)) {
                $nome = (Get-TmdTextoIndireto $rotulo) -replace '&', ''
                if (-not $nome) { $nome = $n }
                $verbos[$k] = @{ Verbo = $n; Nome = $nome; Produto = (Get-NomeProduto $exe ''); Caminhos = [System.Collections.Generic.List[string]]::new(); Onde = [System.Collections.Generic.List[string]]::new() }
            }
            $verbos[$k].Caminhos.Add("$r\shell\$n")
            if ($verbos[$k].Onde -notcontains $script:Raizes[$r]) { $verbos[$k].Onde.Add($script:Raizes[$r]) }
        }
    }
    foreach ($e in $extensoes.Values) {
        @{ Id = 'menu-ext-' + ($e.Clsid.Trim('{}').ToLowerInvariant()); Nome = $e.Nome; Clsid = @($e.Clsid); Terceiro = $true
            Explicacao = "Itens que o programa põe no menu ($($e.Onde -join ', ')). Extensão: $($e.Arquivo)" }
    }
    foreach ($v in $verbos.Values) {
        $nome = if ($v.Produto -and $v.Nome -notlike "*$($v.Produto)*") { "$($v.Nome) ($($v.Produto))" } else { $v.Nome }
        @{ Id = 'menu-cmd-' + (($v.Verbo.ToLowerInvariant() -replace '[^a-z0-9]+', '-').Trim('-')); Nome = $nome; Verbo = @($v.Caminhos); Terceiro = $true
            Explicacao = "Comando do programa no menu ($($v.Onde -join ', '))." }
    }
}

# ---------- Itens -> ajustes do motor ----------

function Get-AjusteItem {
    param([Parameter(Mandatory)][hashtable]$Item, [string]$RaizRegistro)
    $mudancas = [System.Collections.Generic.List[object]]::new()
    $admin = $false
    if ($Item.ContainsKey('Clsid')) {
        foreach ($c in $Item.Clsid) {
            foreach ($b in $script:Bloqueados, $script:Bloqueados32) {
                $mudancas.Add([pscustomobject]@{ tipo = 'Registro'; caminho = "HKLM:\$b"; nome = $c; valor = ''; tipoValor = 'String'; padraoWindows = $null })
            }
        }
        $admin = $true
    }
    if ($Item.ContainsKey('Verbo')) {
        foreach ($sub in $Item.Verbo) {
            $v = Get-ChaveClasse -Sub $sub -RaizRegistro $RaizRegistro
            if (-not $v) { continue }
            $v.Chave.Close()
            $mudancas.Add([pscustomobject]@{ tipo = 'Registro'; caminho = $v.Caminho; nome = 'ProgrammaticAccessOnly'; valor = ''; tipoValor = 'String'; padraoWindows = $null })
            if ($v.Caminho -like 'HKLM:*') { $admin = $true }
        }
    }
    if ($Item.ContainsKey('Novo')) {
        $i = 0
        foreach ($sub in $Item.Novo) {
            $i++
            $caminho = "HKLM:\SOFTWARE\Classes\$sub"
            $guardado = "$($Item.Id)-$i"
            $mudancas.Add([pscustomobject]@{ tipo = 'Script'
                    aplicar = "Remove-TmdChaveComCopia -Caminho '$caminho' -Id '$guardado'"
                    desfazer = "Restore-TmdChaveComCopia -Id '$guardado'"
                    verificar = "-not (Test-TmdChaveExiste -Caminho '$caminho')" })
        }
        $admin = $true
    }
    if ($Item.ContainsKey('EnviarPara')) {
        $lista = "@(Get-ChildItem -LiteralPath (Join-Path `$env:APPDATA 'Microsoft\Windows\SendTo') -Force -File | Where-Object { `$_.Extension -in '.MAPIMail', '.mydocs' -or `$_.Name -match 'fax|bluetooth' })"
        $mudancas.Add([pscustomobject]@{ tipo = 'Script'
                aplicar = "foreach (`$f in $lista) { Set-TmdArquivoOculto -Caminho `$f.FullName -Oculto `$true }"
                desfazer = "foreach (`$f in $lista) { Set-TmdArquivoOculto -Caminho `$f.FullName -Oculto `$false }"
                verificar = "@($lista | Where-Object { -not (`$_.Attributes -band [IO.FileAttributes]::Hidden) }).Count -eq 0" })
    }
    if ($Item.ContainsKey('Classico')) {
        $chave = 'HKCU:\Software\Classes\CLSID\{86ca1aa0-34aa-4e8b-a509-50c905bae2a2}'
        $mudancas.Add([pscustomobject]@{ tipo = 'Script'
                aplicar = "Write-TmdRegistro -Caminho '$chave\InprocServer32' -Nome '' -Valor '' -TipoValor 'String'"
                desfazer = "Remove-Item -LiteralPath '$chave' -Recurse -Force -ErrorAction SilentlyContinue"
                verificar = "Test-Path -LiteralPath '$chave\InprocServer32'" })
    }
    [pscustomobject]@{ id = $Item.Id; nome = $Item.Nome; requerAdmin = $admin; mudancas = $mudancas.ToArray() }
}

# Todos os itens desta máquina (os do Windows que existem aqui + os de programas achados agora).
function Get-ItemMenu {
    param([string]$RaizRegistro)
    $itens = [System.Collections.Generic.List[hashtable]]::new()
    $build = [Environment]::OSVersion.Version.Build
    if (-not $RaizRegistro -and $build -ge 22000) {
        $itens.Add(@{ Id = 'menu-classico'; Nome = 'Menu clássico (do Windows 10)'; Classico = $true; Recomendado = $true; Categoria = 'Estilo do menu'
                Explicacao = 'O botão direito abre o menu completo, sem precisar de "Mostrar mais opções". É nele que os itens abaixo aparecem ou somem. Reinicia o Explorador.' })
    }
    foreach ($i in $script:ItensWindows) {
        $existe = if ($i.ContainsKey('Clsid')) { @($i.Clsid | Where-Object { Test-ClsidRegistrado $_ $RaizRegistro }).Count -gt 0 }
        elseif ($i.ContainsKey('Verbo')) { @($i.Verbo | Where-Object { $v = Get-ChaveClasse $_ $RaizRegistro; if ($v) { $v.Chave.Close(); $true } }).Count -gt 0 }
        elseif ($i.ContainsKey('Novo')) { -not $RaizRegistro -and @($i.Novo | Where-Object { $v = Get-ChaveClasse (($_ -split '\\')[0]) $RaizRegistro; if ($v) { $v.Chave.Close(); $true } }).Count -gt 0 }
        else { -not $RaizRegistro }
        if ($existe) { $c = $i.Clone(); $c.Categoria = 'Itens do Windows'; $itens.Add($c) }
    }
    foreach ($t in Get-ItemTerceiros -RaizRegistro $RaizRegistro) { $t.Categoria = 'Itens de programas'; $itens.Add($t) }
    $itens.ToArray()
}

# Recomendado: o que quase ninguém usa (e o menu clássico); Atencao: risco médio, com o contratempo do item;
# Opcional: o resto, inclusive os itens de programas (o item some do menu, o programa continua funcionando).
function Get-ClassificacaoItem {
    param([hashtable]$Item)
    $volta = 'Desfaça na página Menu de contexto: o item aparece como "aplicado"; marque e clique em Aplicar.'
    if ($Item.ContainsKey('Classico')) {
        return @{ Classificacao = 'Recomendado'; SeAcontecer = $volta
            Contratempo = 'Alguns itens que apps novos (da Microsoft Store) põem só no menu do Windows 11 não aparecem no clássico.' }
    }
    if ($Item.ContainsKey('Risco') -and $Item.Risco -ne 'Baixo') {
        return @{ Classificacao = 'Atencao'; Contratempo = [string]$Item.Contratempo; SeAcontecer = $volta }
    }
    if ($Item.ContainsKey('Recomendado')) { return @{ Classificacao = 'Recomendado'; Contratempo = ''; SeAcontecer = '' } }
    if ($Item.Categoria -eq 'Itens de programas') {
        return @{ Classificacao = 'Opcional'; Contratempo = 'O item some do menu, mas o programa continua instalado e funcionando.'; SeAcontecer = $volta }
    }
    @{ Classificacao = 'Opcional'; Contratempo = ''; SeAcontecer = '' }
}

function Find-Alvos {
    param([string]$RaizRegistro = (Get-RaizRegistroPadrao))
    foreach ($i in Get-ItemMenu -RaizRegistro $RaizRegistro) {
        $ajuste = Get-AjusteItem -Item $i -RaizRegistro $RaizRegistro
        $presets = @(if ($i.ContainsKey('Classico')) { 'Só o menu clássico' }; if ($i.ContainsKey('Recomendado') -or $i.ContainsKey('Classico')) { 'Recomendado' }; 'Limpo ao máximo')
        $estado = Get-TmdEstadoAjuste -Ajuste $ajuste -RaizRegistro $RaizRegistro
        # Já aplicado: marcar desfaz (o item volta ao menu; o clássico volta a ser o novo). Preset nunca marca estes.
        $desfaz = $estado -eq 'Aplicado'
        $c = Get-ClassificacaoItem -Item $i
        [pscustomobject]@{
            Id = $i.Id; Nome = $i.Nome; Categoria = $i.Categoria; Caminho = ''; Tamanho = [int64]0
            Estado = $estado; Desfaz = $desfaz; Selo = $(if ($desfaz) { 'aplicado' } else { '' })
            Detalhe = $i.Explicacao; Nivel = 'Normal'; Valor = $null; Risco = $(if ($i.ContainsKey('Risco')) { $i.Risco } else { 'Baixo' })
            Selecionado = $false; Destino = 'NaoSeAplica'; RequerAdmin = [bool]$ajuste.requerAdmin -and -not $RaizRegistro; Reversivel = $true
            Presets = $presets
            Classificacao = $c.Classificacao; Contratempo = $c.Contratempo; SeAcontecer = $c.SeAcontecer
            Mudancas = @(
                if ($desfaz) { Get-TmdTextoDesfaz -Id $i.Id }
                foreach ($m in $ajuste.mudancas) {
                    if ($m.tipo -eq 'Registro') { "$($m.caminho)\$($m.nome) = (vazio)" } else { "script: $($m.aplicar)" }
                })
        }
    }
}

# O alvo só diz QUAL item; o que mudar sai de uma varredura nova. No fim, reinicia o Explorador para valer já.
function Invoke-Acao {
    param(
        [Parameter(Mandatory)][AllowEmptyCollection()][object[]]$Alvos,
        [switch]$Simular,
        [string]$RaizRegistro = (Get-RaizRegistroPadrao)
    )
    $porId = @{}
    foreach ($i in Get-ItemMenu -RaizRegistro $RaizRegistro) { $porId[$i.Id] = $i }
    $mudou = $false
    foreach ($a in $Alvos) {
        $id = [string]$a.Id
        if (-not $porId.ContainsKey($id)) {
            [pscustomobject]@{ Id = $id; Status = 'Erro'; Liberado = [int64]0; Motivo = 'item não existe nesta máquina'; Mudancas = @() }
            continue
        }
        $ajuste = Get-AjusteItem -Item $porId[$id] -RaizRegistro $RaizRegistro
        $r = if ($a.PSObject.Properties['Desfaz'] -and $a.Desfaz -eq $true) {
            Undo-TmdAjuste -Id $id -Ajuste $ajuste -Simular:$Simular -RaizRegistro $RaizRegistro -Modulo 'menu-contexto'
        }
        else { Set-TmdAjuste -Ajuste $ajuste -Simular:$Simular -RaizRegistro $RaizRegistro -Modulo 'menu-contexto' }
        if ($r.Status -eq 'Feito' -and $r.Motivo -ne 'já estava aplicado') { $mudou = $true }
        $r
    }
    if ($mudou -and -not $Simular -and -not $RaizRegistro) { Restart-TmdExplorador }
}

Export-ModuleMember -Function Test-Requisitos, Find-Alvos, Invoke-Acao
