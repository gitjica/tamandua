# Instalar o winget onde ele falta. Nada é baixado nem instalado de verdade: download, assinatura e Add-AppxPackage
# são Mocks; os arquivos "baixados" são falsos, feitos aqui.

BeforeAll {
    . (Join-Path $PSScriptRoot '..\Ajudantes.ps1')
    Import-Module (Join-Path $script:RaizProjeto 'nucleo\Tamandua.Nucleo.psm1') -Force -DisableNameChecking -Global

    function Set-WingetAusente {
        $global:TmdTesteWinget = @{ Tem = $false; Instalado = $null }
        Mock Test-TmdWinget -ModuleName Tamandua.Nucleo { $global:TmdTesteWinget.Tem }
        Mock Get-TmdLancamentoWinget -ModuleName Tamandua.Nucleo {
            [pscustomobject]@{ Versao = 'v9.9'; Pacote = 'https://exemplo/pacote.msixbundle'; Dependencias = 'https://exemplo/deps.zip' }
        }
        # Pacote falso e um zip de dependências com as três arquiteturas.
        Mock Get-TmdDownloadWinget -ModuleName Tamandua.Nucleo {
            if ($Url -like '*.zip') {
                $origem = Join-Path ([IO.Path]::GetTempPath()) "tamandua-teste-$([guid]::NewGuid().ToString('N'))"
                foreach ($a in 'x64', 'x86', 'arm64') {
                    $p = Join-Path $origem $a; [void][IO.Directory]::CreateDirectory($p)
                    Set-Content -LiteralPath (Join-Path $p "Microsoft.VCLibs.140.00_14.0_$a.appx") -Value 'x'
                }
                Add-Type -AssemblyName System.IO.Compression.FileSystem
                [IO.Compression.ZipFile]::CreateFromDirectory($origem, $Destino)
                Remove-Item -LiteralPath $origem -Recurse -Force
            }
            else { Set-Content -LiteralPath $Destino -Value 'pacote' }
        }
        Mock Add-AppxPackage -ModuleName Tamandua.Nucleo { $global:TmdTesteWinget.Instalado = @{ Pacote = $Path; Deps = @($DependencyPath) }; $global:TmdTesteWinget.Tem = $true }
    }
}

AfterAll { Remove-Variable -Name TmdTesteWinget -Scope Global -ErrorAction SilentlyContinue }

Describe 'Install-TmdWinget' {
    BeforeEach { $env:TAMANDUA_DADOS = Join-Path $TestDrive ([guid]::NewGuid().ToString('N')) }

    It 'já tem winget: não baixa nada' {
        Set-WingetAusente
        $global:TmdTesteWinget.Tem = $true
        (Install-TmdWinget).Status | Should -Be 'Feito'
        Should -Invoke Get-TmdDownloadWinget -ModuleName Tamandua.Nucleo -Times 0 -Exactly
    }

    It 'assinatura da Microsoft válida: instala com as dependências da arquitetura do PC e apaga os temporários' {
        Set-WingetAusente
        Mock Get-AuthenticodeSignature -ModuleName Tamandua.Nucleo { [pscustomobject]@{ Status = 'Valid'; SignerCertificate = [pscustomobject]@{ Subject = 'CN=Microsoft Corporation, O=Microsoft Corporation, L=Redmond' } } }
        $r = Install-TmdWinget
        $r.Status | Should -Be 'Feito'
        $r.Motivo | Should -Match 'v9\.9'
        $arq = switch ($env:PROCESSOR_ARCHITECTURE) { 'ARM64' { 'arm64' } 'x86' { 'x86' } default { 'x64' } }
        $global:TmdTesteWinget.Instalado.Deps.Count | Should -Be 1
        $global:TmdTesteWinget.Instalado.Deps[0] | Should -Match "\\$arq\\"
        @(Get-ChildItem -LiteralPath ([IO.Path]::GetTempPath()) -Directory -Filter 'tamandua-winget-*').Count | Should -Be 0
        (@(Get-TmdHistorico -Ultimos 1)[0]).Caminho | Should -Be 'winget v9.9'
    }

    It 'assinatura que não é da Microsoft: não instala e diz por quê' {
        Set-WingetAusente
        Mock Get-AuthenticodeSignature -ModuleName Tamandua.Nucleo { [pscustomobject]@{ Status = 'Valid'; SignerCertificate = [pscustomobject]@{ Subject = 'CN=Alguém, O=Outra Empresa' } } }
        $r = Install-TmdWinget
        $r.Status | Should -Be 'Erro'
        $r.Motivo | Should -Match 'assinatura da Microsoft'
        Should -Invoke Add-AppxPackage -ModuleName Tamandua.Nucleo -Times 0 -Exactly
    }

    It 'sem internet: erro com o motivo, nada instalado' {
        Set-WingetAusente
        Mock Get-TmdLancamentoWinget -ModuleName Tamandua.Nucleo { throw 'Não é possível resolver o nome remoto' }
        $r = Install-TmdWinget
        $r.Status | Should -Be 'Erro'
        $r.Motivo | Should -Match 'resolver o nome remoto'
        Should -Invoke Add-AppxPackage -ModuleName Tamandua.Nucleo -Times 0 -Exactly
    }
}
