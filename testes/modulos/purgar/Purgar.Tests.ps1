# Módulo purgar. Projetos sempre na sandbox (-Caminho); git real, mas só em repositórios criados na sandbox.

BeforeDiscovery {
    $temGit = [bool](Get-Command git -ErrorAction SilentlyContinue)
}

BeforeAll {
    . (Join-Path $PSScriptRoot '..\..\Ajudantes.ps1')
    Import-Module (Join-Path $script:RaizProjeto 'nucleo\Tamandua.Nucleo.psm1') -Force -DisableNameChecking -Global
    Import-Module (Join-Path $script:RaizProjeto 'modulos\purgar\purgar.psm1') -Force -DisableNameChecking

    function Invoke-Git([string]$Pasta) {
        $ErrorActionPreference = 'Continue'
        & git -C $Pasta @args 2>$null | Out-Null
    }

    # Três projetos: node (com node_modules e dist), .NET (bin/obj) e Rust (target), mais pastas que parecem artefato e não são.
    function New-Projetos {
        $base = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
        New-ArvoreFalsa -Pasta $base -Arquivos @{
            'web\package.json'                   = '{}'
            'web\node_modules\react\index.js'    = ('r' * 3000)
            'web\dist\app.js'                    = ('d' * 500)
            'api\Api.csproj'                     = '<Project/>'
            'api\bin\Debug\api.dll'              = ('b' * 2000)
            'api\obj\project.assets.json'        = ('o' * 700)
            'cli\Cargo.toml'                     = '[package]'
            'cli\target\debug\cli.exe'           = ('t' * 4000)
            'fotos\bin\minha-foto.jpg'           = 'sem projeto ao lado'
            'notas\node_modules\leia.txt'        = 'sem package.json'
        } | Out-Null
        foreach ($p in 'web\node_modules', 'web\dist', 'api\bin', 'api\obj', 'cli\target') {
            foreach ($i in @(Get-Item "$base\$p") + @(Get-ChildItem "$base\$p" -Recurse -Force)) { $i.LastWriteTime = (Get-Date).AddDays(-30) }
        }
        $base
    }
}

Describe 'Find-Alvos' {
    BeforeEach { $base = New-Projetos }

    It 'acha os artefatos com o arquivo do projeto ao lado, agrupados por projeto' {
        $alvos = @(Find-Alvos -Caminho $base | Where-Object { $_.Id -like 'art:*' })
        ($alvos | ForEach-Object { "$($_.Categoria)|$($_.Nome)" } | Sort-Object) -join ',' |
            Should -Be ((@('api|bin', 'api|obj', 'cli|target', 'web|dist', 'web|node_modules') | ForEach-Object { "$(Split-Path -Leaf $base)\$_" }) -join ',')
        ($alvos | Where-Object Nome -eq 'node_modules').Tamanho | Should -Be 3000
        ($alvos | Where-Object Nome -eq 'target').Mudancas -join ' ' | Should -Match 'cargo build'
    }

    It 'pasta com nome de artefato mas sem projeto ao lado fica de fora' {
        $ids = @(Find-Alvos -Caminho $base | ForEach-Object Id)
        $ids | Should -Not -Contain "art:$base\fotos\bin"
        $ids | Should -Not -Contain "art:$base\notas\node_modules"
    }

    It 'artefato mexido nos últimos 7 dias vem desmarcado' -Skip:(-not $temGit) {
        (Get-Item "$base\web\node_modules").LastWriteTime = Get-Date
        $alvos = @(Find-Alvos -Caminho $base)
        $nm = $alvos | Where-Object Nome -eq 'node_modules'
        $nm.Selecionado | Should -BeFalse
        $nm.Detalhe | Should -Match 'projeto em uso'
        ($alvos | Where-Object Nome -eq 'target').Selecionado | Should -BeTrue
    }

    It 'não entra em links nem em .git' {
        $fora = New-ArvoreFalsa -Pasta (Join-Path $TestDrive "fora-$([guid]::NewGuid().ToString('N'))") -Arquivos @{ 'x\package.json' = '{}'; 'x\node_modules\a.js' = 'a' }
        New-Item -ItemType Junction -Path "$base\atalho" -Target $fora | Out-Null
        @(Find-Alvos -Caminho $base | Where-Object { $_.Caminho -like "*atalho*" }).Count | Should -Be 0
    }

    It 'nada muda no disco' {
        $antes = Get-AssinaturaPasta $base
        Find-Alvos -Caminho $base | Out-Null
        Get-AssinaturaPasta $base | Should -Be $antes
    }
}

Describe 'Git' -Skip:(-not $temGit) {
    BeforeEach { $base = New-Projetos }

    It 'pasta com arquivo versionado no git fica de fora, com aviso' {
        Invoke-Git $base init -q
        Invoke-Git $base -c user.email=t@t -c user.name=t add -f 'web/dist/app.js'
        Invoke-Git $base -c user.email=t@t -c user.name=t commit -q -m x
        $alvos = @(Find-Alvos -Caminho $base)
        @($alvos | Where-Object { $_.Nome -eq 'dist' }).Count | Should -Be 0
        ($alvos | Where-Object Id -eq 'aviso-versionados').Nome | Should -Match '^1 pasta'
        @($alvos | Where-Object { $_.Nome -eq 'node_modules' }).Count | Should -Be 1 -Because 'o resto do repositório segue normal'
    }

    It 'artefato com outro repositório git dentro fica de fora' {
        New-Item -ItemType Directory -Path "$base\web\node_modules\meu-pacote\.git" -Force | Out-Null
        @(Find-Alvos -Caminho $base | Where-Object { $_.Nome -eq 'node_modules' }).Count | Should -Be 0
    }
}

Describe 'Invoke-Acao' {
    BeforeEach {
        $base = New-Projetos
        $alvos = @(Find-Alvos -Caminho $base | Where-Object { $_.Id -like 'art:*' })
    }

    It 'apaga os artefatos e deixa o projeto inteiro' -Skip:(-not $temGit) {
        $r = @(Invoke-Acao -Alvos $alvos)
        @($r | Where-Object Status -ne 'Feito').Count | Should -Be 0
        ($r | Measure-Object Liberado -Sum).Sum | Should -Be 10200
        Test-Path "$base\web\node_modules" | Should -BeFalse
        Test-Path "$base\api\bin" | Should -BeFalse
        Test-Path "$base\web\package.json" | Should -BeTrue
        Test-Path "$base\api\Api.csproj" | Should -BeTrue
        Test-Path "$base\fotos\bin\minha-foto.jpg" | Should -BeTrue
    }

    It '-Simular não apaga nada' {
        $antes = Get-AssinaturaPasta $base
        Invoke-Acao -Alvos $alvos -Simular | Out-Null
        Get-AssinaturaPasta $base | Should -Be $antes
    }

    It 'reconfere antes de apagar: alvo forjado ou projeto que perdeu o marcador é ignorado' {
        Remove-Item -LiteralPath "$base\cli\Cargo.toml"
        $forjados = @(
            [pscustomobject]@{ Id = "art:$base\fotos\bin" }
            [pscustomobject]@{ Id = "art:$base\web" }
            [pscustomobject]@{ Id = "art:$base\cli\target" }
            [pscustomobject]@{ Id = 'C:\Windows' }
        )
        $r = @(Invoke-Acao -Alvos $forjados)
        @($r | ForEach-Object Status | Select-Object -Unique) | Should -Be 'Ignorado'
        Test-Path "$base\fotos\bin\minha-foto.jpg" | Should -BeTrue
        Test-Path "$base\web\package.json" | Should -BeTrue
        Test-Path "$base\cli\target\debug\cli.exe" | Should -BeTrue
    }

    It 'arquivo protegido pela lista dentro do artefato fica (o resto vai)' -Skip:(-not $temGit) {
        New-ArvoreFalsa -Pasta "$base\cli\target" -Arquivos @{ 'deploy\chave.pem' = 'segredo' } | Out-Null
        $r = Invoke-Acao -Alvos @($alvos | Where-Object Nome -eq 'target')
        $r.Status | Should -Be 'Parcial'
        $r.Motivo | Should -Match 'protegido'
        Test-Path "$base\cli\target\deploy\chave.pem" | Should -BeTrue
        Test-Path "$base\cli\target\debug\cli.exe" | Should -BeFalse
    }
}

Describe 'Pela linha de comando' {
    It 'tamandua purgar PASTA -Simular lista por projeto e não apaga; -Sim apaga' -Skip:(-not $temGit) {
        $base = New-Projetos
        $projeto = New-ProjetoFalso -Pai $TestDrive -ModulosReais 'purgar'
        $s = Invoke-Tamandua -Raiz $projeto -Argumentos 'purgar', "`"$base`"", '-Simular'
        $s.Codigo | Should -Be 0
        $s.Saida | Should -Match '\[x\] node_modules'
        Test-Path "$base\web\node_modules" | Should -BeTrue
        $r = Invoke-Tamandua -Raiz $projeto -Argumentos 'purgar', "`"$base`"", '-Sim'
        $r.Codigo | Should -Be 0
        Test-Path "$base\web\node_modules" | Should -BeFalse
        Test-Path "$base\web\package.json" | Should -BeTrue
    }
}
