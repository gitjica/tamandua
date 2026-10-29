# Módulo reparos. Nenhum programa do sistema roda de verdade: Invoke-TmdPrograma é trocado por Mock.
# A pasta de downloads do Windows Update é da sandbox.

BeforeAll {
    . (Join-Path $PSScriptRoot '..\..\Ajudantes.ps1')
    Import-Module (Join-Path $script:RaizProjeto 'nucleo\Tamandua.Nucleo.psm1') -Force -DisableNameChecking -Global
    Import-Module (Join-Path $script:RaizProjeto 'modulos\reparos\reparos.psm1') -Force -DisableNameChecking

    function Set-ProgramasFalsos {
        param([hashtable]$Codigos = @{})
        $global:TmdTesteCodigos = $Codigos
        $global:TmdTesteChamadas = [System.Collections.Generic.List[string]]::new()
        Mock Invoke-TmdPrograma -ModuleName reparos {
            $linha = "$Arquivo $Argumentos"
            $global:TmdTesteChamadas.Add($linha)
            $codigo = if ($global:TmdTesteCodigos.ContainsKey($linha)) { $global:TmdTesteCodigos[$linha] } else { 0 }
            [pscustomobject]@{ Codigo = $codigo; Saida = @() }
        }
    }
}

AfterAll {
    Remove-Variable -Name TmdTesteCodigos, TmdTesteChamadas -Scope Global -ErrorAction SilentlyContinue
}

Describe 'Find-Alvos' {
    It 'cinco reparos, nada marcado, todos pedem admin, com explicação' {
        $alvos = @(Find-Alvos)
        ($alvos | ForEach-Object Id) -join ',' | Should -Be 'chkdsk,sfc,dism,rede,windows-update'
        @($alvos | Where-Object Selecionado).Count | Should -Be 0
        @($alvos | Where-Object { -not $_.RequerAdmin }).Count | Should -Be 0
        ($alvos | Where-Object Id -eq 'rede').Risco | Should -Be 'Medio'
        ($alvos | Where-Object Id -eq 'rede').Mudancas[0] | Should -Match 'VPN'
    }
}

Describe 'Invoke-Acao' {
    BeforeEach { Set-ProgramasFalsos }

    It '<Id> roda "<Comando>"' -ForEach @(
        @{ Id = 'chkdsk'; Comando = 'chkdsk.exe C: /scan' }
        @{ Id = 'sfc'; Comando = 'sfc.exe /scannow' }
        @{ Id = 'dism'; Comando = 'DISM.exe /Online /Cleanup-Image /RestoreHealth' }
    ) {
        $r = Invoke-Acao -Alvos @([pscustomobject]@{ Id = $Id })
        $r.Status | Should -Be 'Feito'
        $global:TmdTesteChamadas | Should -Be @($Comando)
    }

    It 'rede: winsock e ip, e pede reinício' {
        $r = Invoke-Acao -Alvos @([pscustomobject]@{ Id = 'rede' })
        $r.Motivo | Should -Match 'reinicie'
        $global:TmdTesteChamadas -join '|' | Should -Be 'netsh.exe winsock reset|netsh.exe int ip reset'
    }

    It 'chkdsk com problema que precisa de reinício: parcial, explicando o que fazer' {
        Set-ProgramasFalsos -Codigos @{ 'chkdsk.exe C: /scan' = 3 }
        $r = Invoke-Acao -Alvos @([pscustomobject]@{ Id = 'chkdsk' })
        $r.Status | Should -Be 'Parcial'
        $r.Motivo | Should -Match 'chkdsk C: /f'
    }

    It 'SFC com falha: erro sugerindo o DISM' {
        Set-ProgramasFalsos -Codigos @{ 'sfc.exe /scannow' = 2 }
        (Invoke-Acao -Alvos @([pscustomobject]@{ Id = 'sfc' })).Motivo | Should -Match 'DISM'
    }

    It 'Windows Update: para os serviços, apaga os downloads pela metade e liga de novo' {
        $download = New-ArvoreFalsa -Pasta (Join-Path $TestDrive "SD-$([guid]::NewGuid().ToString('N'))\Download") -Arquivos @{ 'abc\pacote.cab' = ('x' * 1000); 'meio.psf' = ('y' * 24) }
        $r = Invoke-Acao -Alvos @([pscustomobject]@{ Id = 'windows-update' }) -PastaDownload $download
        $r.Status | Should -Be 'Feito'
        $r.Liberado | Should -Be 1024
        @(Get-ChildItem -LiteralPath $download -Force).Count | Should -Be 0
        Test-Path -LiteralPath $download | Should -BeTrue -Because 'a pasta Download em si fica'
        $global:TmdTesteChamadas -join '|' | Should -Be 'net.exe stop wuauserv|net.exe stop bits|net.exe start wuauserv|net.exe start bits'
    }

    It 'Windows Update: os serviços voltam mesmo se apagar falhar no meio' {
        $download = New-ArvoreFalsa -Pasta (Join-Path $TestDrive "SD-$([guid]::NewGuid().ToString('N'))\Download") -Arquivos @{ 'a.cab' = 'x' }
        Mock Remove-TmdItem -ModuleName reparos { throw 'disco sumiu' }
        { Invoke-Acao -Alvos @([pscustomobject]@{ Id = 'windows-update' }) -PastaDownload $download } | Should -Throw '*disco sumiu*'
        @($global:TmdTesteChamadas | Where-Object { $_ -like 'net.exe start*' }).Count | Should -Be 2
    }

    It '-Simular não roda nada; reparo desconhecido é erro' {
        (Invoke-Acao -Alvos @([pscustomobject]@{ Id = 'sfc' }) -Simular).Status | Should -Be 'Simulado'
        (Invoke-Acao -Alvos @([pscustomobject]@{ Id = 'formatar' })).Status | Should -Be 'Erro'
        $global:TmdTesteChamadas.Count | Should -Be 0
    }
}
