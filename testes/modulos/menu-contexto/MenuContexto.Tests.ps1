# Módulo menu de contexto. As classes (o "HKCR") são falsas, dentro de HKCU:\Software\TamanduaTestes, e o motor escreve
# lá também (-RaizRegistro). O Explorador nunca é reiniciado e nenhuma chave ou arquivo de verdade é tocado.

BeforeAll {
    . (Join-Path $PSScriptRoot '..\..\Ajudantes.ps1')
    Import-Module (Join-Path $script:RaizProjeto 'nucleo\Tamandua.Nucleo.psm1') -Force -DisableNameChecking -Global
    Import-Module (Join-Path $script:RaizProjeto 'modulos\menu-contexto\menu-contexto.psm1') -Force -DisableNameChecking
    $script:ChaveTestes = "HKCU:\Software\TamanduaTestes\menu-$([guid]::NewGuid().ToString('N'))"

    function Set-Valor([string]$Caminho, [string]$Nome, [string]$Valor) {
        if (-not (Test-Path -LiteralPath $Caminho)) { New-Item -Path $Caminho -Force | Out-Null }
        New-ItemProperty -LiteralPath $Caminho -Name $Nome -Value $Valor -PropertyType String -Force | Out-Null
    }
    # Um menu falso: item do Windows (Compartilhar), extensão de programa, comando do Git em dois lugares, cmd do Windows.
    function New-MenuFalso {
        $raiz = "$script:ChaveTestes\$([guid]::NewGuid().ToString('N'))"
        $cl = "$raiz\HKLM\SOFTWARE\Classes"
        Set-Valor "$cl\CLSID\{e2bf9676-5f8f-435c-97eb-11607a5bedf7}\InprocServer32" '(default)' 'C:\Windows\System32\shell32.dll'
        Set-Valor "$cl\*\shellex\ContextMenuHandlers\FakeZip" '(default)' '{11111111-2222-3333-4444-555555555555}'
        Set-Valor "$cl\CLSID\{11111111-2222-3333-4444-555555555555}\InprocServer32" '(default)' 'C:\Program Files\FakeZip\fz.dll'
        Set-Valor "$cl\*\shellex\ContextMenuHandlers\Sharing" '(default)' '{f81e9010-6ea4-11ce-a7ff-00aa003ca9f6}'
        Set-Valor "$cl\CLSID\{f81e9010-6ea4-11ce-a7ff-00aa003ca9f6}\InprocServer32" '(default)' 'C:\Windows\System32\ntshrui.dll'
        foreach ($r in 'Directory', 'Directory\Background') {
            Set-Valor "$cl\$r\shell\git_shell" 'MUIVerb' 'Abrir Git Ba&sh aqui'
            Set-Valor "$cl\$r\shell\git_shell\command" '(default)' '"C:\Program Files\Git\git-bash.exe" "--cd=%1"'
            Set-Valor "$cl\$r\shell\cmd\command" '(default)' 'cmd.exe /s /k pushd "%V"'
        }
        Set-Valor "$cl\Folder\shell\opennewtab" 'MUIVerb' '@windows.storage.dll,-8519'
        $raiz
    }
    function Get-Valor([string]$Caminho, [string]$Nome) {
        $p = Get-ItemProperty -LiteralPath $Caminho -ErrorAction SilentlyContinue
        if ($p -and $p.PSObject.Properties[$Nome]) { $p.$Nome }
    }
}

AfterAll {
    if (Test-Path -LiteralPath $script:ChaveTestes) { Remove-Item -LiteralPath $script:ChaveTestes -Recurse -Force }
    $mae = 'HKCU:\Software\TamanduaTestes'
    if ((Test-Path -LiteralPath $mae) -and @(Get-ChildItem -LiteralPath $mae).Count -eq 0) { Remove-Item -LiteralPath $mae -Force }
}

Describe 'Menu de contexto' {
    BeforeEach {
        $env:TAMANDUA_DADOS = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
        $raiz = New-MenuFalso
        Mock Test-TmdAdministrador -ModuleName Tamandua.Nucleo { $true }
        Mock Restart-TmdExplorador -ModuleName menu-contexto { }
    }

    It 'acha os itens do Windows que existem aqui e os de programas; comando do Windows (cmd) não conta como programa' {
        $alvos = @(Find-Alvos -RaizRegistro $raiz)
        $ids = @($alvos | ForEach-Object Id)
        $ids | Should -Contain 'menu-compartilhar'
        $ids | Should -Contain 'menu-conceder-acesso'
        $ids | Should -Contain 'menu-abrir-nova-aba'
        $ids | Should -Contain 'menu-ext-11111111-2222-3333-4444-555555555555'
        $ids | Should -Contain 'menu-cmd-git-shell'
        $ids | Should -Not -Contain 'menu-cmd-cmd'
        $ids | Should -Not -Contain 'menu-transmitir' -Because 'o CLSID não está registrado nesta máquina falsa'
        $ids | Should -Not -Contain 'menu-classico' -Because 'menu clássico, "Novo" e "Enviar para" não rodam na área de testes'
        ($alvos | Where-Object Id -eq 'menu-cmd-git-shell').Nome | Should -Be 'Abrir Git Bash aqui'
        ($alvos | Where-Object Id -eq 'menu-cmd-git-shell').Categoria | Should -Be 'Itens de programas'
        @($alvos | ForEach-Object Estado | Select-Object -Unique) | Should -Be 'NaoAplicado'
        ($alvos | Where-Object Id -eq 'menu-compartilhar').Presets | Should -Contain 'Recomendado'
        ($alvos | Where-Object Id -eq 'menu-ext-11111111-2222-3333-4444-555555555555').Presets | Should -Be @('Limpo ao máximo')
    }

    It 'tira e devolve: extensão bloqueada pelo CLSID (64 e 32 bits) e comando escondido nos dois lugares' {
        $r = @(Invoke-Acao -RaizRegistro $raiz -Alvos @([pscustomobject]@{ Id = 'menu-ext-11111111-2222-3333-4444-555555555555' }, [pscustomobject]@{ Id = 'menu-cmd-git-shell' }))
        @($r | Where-Object Status -ne 'Feito').Count | Should -Be 0
        $bloq = "$raiz\HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Shell Extensions\Blocked"
        Get-Valor $bloq '{11111111-2222-3333-4444-555555555555}' | Should -Be ''
        Get-Valor "$raiz\HKLM\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Shell Extensions\Blocked" '{11111111-2222-3333-4444-555555555555}' | Should -Be ''
        foreach ($r2 in 'Directory', 'Directory\Background') { Get-Valor "$raiz\HKLM\SOFTWARE\Classes\$r2\shell\git_shell" 'ProgrammaticAccessOnly' | Should -Be '' }
        @(Find-Alvos -RaizRegistro $raiz | Where-Object { $_.Id -in 'menu-ext-11111111-2222-3333-4444-555555555555', 'menu-cmd-git-shell' } | ForEach-Object Estado | Select-Object -Unique) | Should -Be 'Aplicado'

        (Undo-TmdAjuste -Id 'menu-cmd-git-shell').Status | Should -Be 'Feito'
        (Undo-TmdAjuste -Id 'menu-ext-11111111-2222-3333-4444-555555555555').Status | Should -Be 'Feito'
        Get-Valor $bloq '{11111111-2222-3333-4444-555555555555}' | Should -BeNullOrEmpty
        (Get-ItemProperty -LiteralPath "$raiz\HKLM\SOFTWARE\Classes\Directory\shell\git_shell").PSObject.Properties.Name | Should -Not -Contain 'ProgrammaticAccessOnly'
        Should -Invoke Restart-TmdExplorador -ModuleName menu-contexto -Times 0 -Exactly -Because 'na área de testes o Explorador nunca é reiniciado'
    }

    It 'item já tirado (por outra ferramenta): vem com "marcar desfaz" e marcar devolve ao menu' {
        $bloq = "$raiz\HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Shell Extensions\Blocked"
        foreach ($b in $bloq, "$raiz\HKLM\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Shell Extensions\Blocked") { Set-Valor $b '{11111111-2222-3333-4444-555555555555}' '' }
        $alvo = @(Find-Alvos -RaizRegistro $raiz) | Where-Object Id -eq 'menu-ext-11111111-2222-3333-4444-555555555555'
        $alvo.Estado | Should -Be 'Aplicado'
        $alvo.Desfaz | Should -BeTrue
        $alvo.Selo | Should -Be 'aplicado · marcar desfaz'
        (Invoke-Acao -RaizRegistro $raiz -Alvos @($alvo)).Status | Should -Be 'Feito'
        Get-Valor $bloq '{11111111-2222-3333-4444-555555555555}' | Should -BeNullOrEmpty
        (@(Find-Alvos -RaizRegistro $raiz) | Where-Object Id -eq 'menu-ext-11111111-2222-3333-4444-555555555555').Estado | Should -Be 'NaoAplicado'
    }

    It 'simular não escreve; item que não existe nesta máquina vira erro' {
        $r = @(Invoke-Acao -RaizRegistro $raiz -Simular -Alvos @([pscustomobject]@{ Id = 'menu-compartilhar' }, [pscustomobject]@{ Id = 'menu-nao-existe' }))
        $r[0].Status | Should -Be 'Simulado'
        $r[1].Status | Should -Be 'Erro'
        Test-Path -LiteralPath "$raiz\HKLM\SOFTWARE\Microsoft" | Should -BeFalse
    }
}

Describe 'Ajudantes do núcleo para o menu' {
    BeforeEach { $env:TAMANDUA_DADOS = Join-Path $TestDrive ([guid]::NewGuid().ToString('N')) }

    It 'chave inteira sai com cópia e volta igual (ex.: o ShellNew do "Novo")' {
        $chave = "$script:ChaveTestes\copia-$([guid]::NewGuid().ToString('N'))\.bmp\ShellNew"
        Set-Valor $chave 'NullFile' ''
        Set-Valor "$chave\Sub" 'Item' 'abc'
        InModuleScope Tamandua.Nucleo -Parameters @{ C = $chave } {
            param($C)
            Test-TmdChaveExiste -Caminho $C | Should -BeTrue
            Remove-TmdChaveComCopia -Caminho $C -Id 'menu-novo-teste-1'
            Test-TmdChaveExiste -Caminho $C | Should -BeFalse
            Test-Path -LiteralPath (Get-TmdArquivoChaveGuardada -Id 'menu-novo-teste-1') | Should -BeTrue
            Restore-TmdChaveComCopia -Id 'menu-novo-teste-1'
            Test-TmdChaveExiste -Caminho $C | Should -BeTrue
            Test-Path -LiteralPath (Get-TmdArquivoChaveGuardada -Id 'menu-novo-teste-1') | Should -BeFalse
        }
        Get-Valor "$chave\Sub" 'Item' | Should -Be 'abc'
    }

    It 'arquivo oculto e de volta (o "Enviar para" não apaga nada)' {
        $f = Join-Path $TestDrive 'Destinatário de email.MAPIMail'
        Set-Content -LiteralPath $f -Value 'x'
        InModuleScope Tamandua.Nucleo -Parameters @{ F = $f } {
            param($F)
            Set-TmdArquivoOculto -Caminho $F -Oculto $true
            ([IO.File]::GetAttributes($F) -band [IO.FileAttributes]::Hidden) | Should -BeTrue
            Set-TmdArquivoOculto -Caminho $F -Oculto $false
            ([IO.File]::GetAttributes($F) -band [IO.FileAttributes]::Hidden) | Should -BeFalse
        }
        Test-Path -LiteralPath $f | Should -BeTrue
    }

    It 'texto indireto do Windows vira nome legível' {
        $t = Get-TmdTextoIndireto '@shell32.dll,-8506'
        $t | Should -Not -BeNullOrEmpty
        $t | Should -Not -Match '^@'
        Get-TmdTextoIndireto 'Abrir aqui' | Should -Be 'Abrir aqui'
    }
}
