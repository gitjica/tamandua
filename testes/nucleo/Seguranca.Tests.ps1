# Validação de caminho (seção 7.1). Só valida: nenhum teste aqui apaga nada fora da sandbox.

BeforeAll {
    . (Join-Path $PSScriptRoot '..\Ajudantes.ps1')
    Import-Module (Join-Path $script:RaizProjeto 'nucleo\Tamandua.Nucleo.psm1') -Force -DisableNameChecking -Global
    $raiz = Join-Path $TestDrive 'Temp'
    New-ArvoreFalsa -Pasta $raiz -Arquivos @{ 'cache\a.tmp' = 'a'; 'b.tmp' = 'b' } | Out-Null
    function Test-Caminho([string]$C, [string[]]$R = @($raiz), [string[]]$P = @()) {
        Test-TmdCaminhoSeguro -Caminho $C -Raizes $R -Protecao $P
    }
}

Describe 'Dentro da pasta permitida' {
    It 'aceita arquivo e pasta dentro da raiz' {
        (Test-Caminho (Join-Path $raiz 'b.tmp')).Ok | Should -BeTrue
        (Test-Caminho (Join-Path $raiz 'cache')).Ok | Should -BeTrue
    }

    It 'aceita caminho que ainda não existe dentro da raiz' {
        (Test-Caminho (Join-Path $raiz 'novo\x.tmp')).Ok | Should -BeTrue
    }

    It 'recusa a própria raiz' {
        $r = Test-Caminho $raiz
        $r.Ok | Should -BeFalse
        $r.Motivo | Should -Match 'fora das pastas permitidas'
    }

    It 'recusa ..\ que escapa da raiz' {
        $r = Test-Caminho "$raiz\cache\..\..\fora.txt"
        $r.Ok | Should -BeFalse
        $r.Caminho | Should -Be (Join-Path $TestDrive 'fora.txt')
    }

    It 'recusa pasta vizinha com o mesmo começo de nome (Temp2 não é filha de Temp)' {
        (Test-Caminho (Join-Path $TestDrive 'Temp2\x.tmp')).Ok | Should -BeFalse
    }

    It 'recusa <Caso>' -ForEach @(
        @{ Caso = 'caminho vazio'; C = '' }
        @{ Caso = 'caminho relativo'; C = 'cache\a.tmp' }
        @{ Caso = 'curinga'; C = 'C:\Temp\*.tmp' }
        @{ Caso = 'caminho de rede'; C = '\\servidor\pasta\x' }
        @{ Caso = 'caminho de dispositivo'; C = '\\?\C:\Windows' }
        @{ Caso = 'raiz de unidade'; C = 'C:\' }
    ) {
        (Test-TmdCaminhoSeguro -Caminho $C -Raizes 'C:\' -Protecao @()).Ok | Should -BeFalse
    }
}

Describe 'Pastas protegidas do sistema' {
    It 'recusa <Nome> e qualquer pai dela, mesmo com raiz C:\' -ForEach @(
        @{ Nome = 'Windows'; C = [Environment]::GetFolderPath('Windows') }
        @{ Nome = 'System32'; C = [Environment]::GetFolderPath('System') }
        @{ Nome = 'Arquivos de Programas'; C = [Environment]::GetFolderPath('ProgramFiles') }
        @{ Nome = 'Arquivos de Programas (x86)'; C = [Environment]::GetFolderPath('ProgramFilesX86') }
        @{ Nome = 'ProgramData'; C = [Environment]::GetFolderPath('CommonApplicationData') }
        @{ Nome = 'Usuários'; C = Split-Path -Parent ([Environment]::GetFolderPath('UserProfile')) }
        @{ Nome = 'perfil do usuário'; C = [Environment]::GetFolderPath('UserProfile') }
        @{ Nome = 'AppData\Roaming'; C = [Environment]::GetFolderPath('ApplicationData') }
        @{ Nome = 'AppData\Local'; C = [Environment]::GetFolderPath('LocalApplicationData') }
        @{ Nome = 'Documentos'; C = [Environment]::GetFolderPath('MyDocuments') }
        @{ Nome = 'Área de Trabalho'; C = [Environment]::GetFolderPath('Desktop') }
        @{ Nome = 'Downloads'; C = Join-Path ([Environment]::GetFolderPath('UserProfile')) 'Downloads' }
        @{ Nome = 'Temp'; C = [IO.Path]::GetTempPath() }
    ) {
        $raizUnidade = [IO.Path]::GetPathRoot($C)
        $r = Test-TmdCaminhoSeguro -Caminho $C -Raizes $raizUnidade -Protecao @()
        $r.Ok | Should -BeFalse -Because $C
        $r.Motivo | Should -Match 'protegida'
    }

    It 'recusa qualquer coisa dentro de <Nome>' -ForEach @(
        @{ Nome = 'System32'; C = Join-Path ([Environment]::GetFolderPath('System')) 'drivers\etc\hosts' }
        @{ Nome = 'Arquivos de Programas'; C = Join-Path ([Environment]::GetFolderPath('ProgramFiles')) 'Algum\app.exe' }
        @{ Nome = 'Imagens'; C = Join-Path ([Environment]::GetFolderPath('MyPictures')) 'ferias\foto.jpg' }
        @{ Nome = 'pasta do próprio Tamanduá'; C = Join-Path (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) 'nucleo\Remocao.ps1' }
    ) {
        $r = Test-TmdCaminhoSeguro -Caminho $C -Raizes 'C:\' -Protecao @()
        $r.Ok | Should -BeFalse -Because $C
    }

    It 'aceita as exceções do Windows (Temp e cache do Windows Update)' {
        $windows = [Environment]::GetFolderPath('Windows')
        (Test-TmdCaminhoSeguro -Caminho "$windows\Temp\x.log" -Raizes "$windows\Temp" -Protecao @()).Ok | Should -BeTrue
        (Test-TmdCaminhoSeguro -Caminho "$windows\SoftwareDistribution\Download\abc" -Raizes $windows -Protecao @()).Ok | Should -BeTrue
    }

    It 'aceita conteúdo de Documentos e Downloads (projetos e instaladores)' {
        $docs = [Environment]::GetFolderPath('MyDocuments')
        $down = Join-Path ([Environment]::GetFolderPath('UserProfile')) 'Downloads'
        (Test-TmdCaminhoSeguro -Caminho "$docs\projeto\node_modules" -Raizes $docs -Protecao @()).Ok | Should -BeTrue
        (Test-TmdCaminhoSeguro -Caminho "$down\setup.exe" -Raizes $down -Protecao @()).Ok | Should -BeTrue
    }
}

Describe 'Links (junctions)' {
    BeforeAll {
        $fora = New-ArvoreFalsa -Pasta (Join-Path $TestDrive 'Importante') -Arquivos @{ 'contrato.docx' = 'não apague' }
        $link = Join-Path $raiz 'atalho'
        New-Item -ItemType Junction -Path $link -Target $fora | Out-Null
    }

    It 'recusa o próprio link' {
        $r = Test-Caminho $link
        $r.Ok | Should -BeFalse
        $r.Motivo | Should -Match 'link'
    }

    It 'recusa caminho que passa pelo link' {
        $r = Test-Caminho (Join-Path $link 'contrato.docx')
        $r.Ok | Should -BeFalse
        $r.Motivo | Should -Match 'link'
    }
}

Describe 'Lista de proteção' {
    It 'recusa caminho que bate com um padrão' {
        $r = Test-Caminho (Join-Path $raiz 'cache\a.tmp') -P '*\cache\*'
        $r.Ok | Should -BeFalse
        $r.Motivo | Should -Match 'lista de proteção'
    }

    It 'lê a lista padrão e a do usuário, ignorando comentários e expandindo variáveis' {
        $arquivo = Join-Path $env:TAMANDUA_CONFIG 'protegidos.txt'
        [void][IO.Directory]::CreateDirectory($env:TAMANDUA_CONFIG)
        Set-Content -LiteralPath $arquivo -Encoding UTF8 -Value '# comentário', '', '%USERPROFILE%\MeuProjeto\*'
        try {
            $lista = @(Get-TmdListaProtecao)
            $lista | Should -Contain "$env:USERPROFILE\MeuProjeto\*"
            $lista | Should -Contain '*\.ssh\*' -Because 'vem da lista padrão'
            $lista | Should -Not -Contain '# comentário'
            (Test-TmdCaminhoSeguro -Caminho "$env:USERPROFILE\MeuProjeto\x.tmp" -Raizes $env:USERPROFILE).Ok | Should -BeFalse
        }
        finally {
            Remove-Item -LiteralPath $arquivo -Force
        }
    }

    It 'a lista padrão protege dados de navegador e chaves' {
        $lista = @(Get-TmdListaProtecao)
        foreach ($c in "$raiz\Chrome\Default\Login Data", "$raiz\Chrome\Default\Cookies", "$raiz\perfil\.ssh\id_rsa", "$raiz\senhas.kdbx") {
            (Test-Caminho $c -P $lista).Ok | Should -BeFalse -Because $c
        }
        (Test-Caminho "$raiz\Chrome\Default\Cache\data_1" -P $lista).Ok | Should -BeTrue
    }

    It 'lista do usuário ilegível faz Get-TmdListaProtecao falhar' {
        $arquivo = Join-Path $env:TAMANDUA_CONFIG 'protegidos.txt'
        New-Item -ItemType Directory -Path $arquivo -Force | Out-Null
        try {
            { Get-TmdListaProtecao } | Should -Throw '*lista de proteção*'
        }
        finally {
            Remove-Item -LiteralPath $arquivo -Force
        }
    }
}
