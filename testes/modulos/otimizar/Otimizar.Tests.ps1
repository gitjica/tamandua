# Módulo otimizar. Programas do sistema e o Explorador são simulados (Mock); o cache de ícones fica numa
# AppData\Local falsa da sandbox. Nada fecha o seu Explorador nem roda defrag/DISM de verdade.

BeforeAll {
    . (Join-Path $PSScriptRoot '..\..\Ajudantes.ps1')
    Import-Module (Join-Path $script:RaizProjeto 'nucleo\Tamandua.Nucleo.psm1') -Force -DisableNameChecking -Global
    Import-Module (Join-Path $script:RaizProjeto 'modulos\otimizar\otimizar.psm1') -Force -DisableNameChecking

    function Set-SistemaFalso {
        param([hashtable]$Codigos = @{})
        $global:TmdTesteCodigos = $Codigos
        $global:TmdTesteChamadas = [System.Collections.Generic.List[string]]::new()
        Mock Invoke-TmdPrograma -ModuleName otimizar {
            $linha = "$Arquivo $Argumentos"
            $global:TmdTesteChamadas.Add($linha)
            $c = if ($global:TmdTesteCodigos.ContainsKey($linha)) { $global:TmdTesteCodigos[$linha] } else { 0 }
            [pscustomobject]@{ Codigo = $c; Saida = @() }
        }
        Mock Start-Explorador -ModuleName otimizar { $global:TmdTesteChamadas.Add('abrir explorer') }
        Mock Start-Sleep -ModuleName otimizar { }
    }

    function New-LocalFalsa {
        New-ArvoreFalsa -Pasta (Join-Path $TestDrive "Local-$([guid]::NewGuid().ToString('N'))") -Arquivos @{
            'IconCache.db'                              = ('i' * 100)
            'Microsoft\Windows\Explorer\iconcache_32.db' = ('a' * 200)
            'Microsoft\Windows\Explorer\iconcache_idx.db' = ('b' * 50)
            'Microsoft\Windows\Explorer\thumbcache_96.db' = 'miniaturas ficam'
        }
    }
}

AfterAll {
    Remove-Variable -Name TmdTesteCodigos, TmdTesteChamadas -Scope Global -ErrorAction SilentlyContinue
}

Describe 'Find-Alvos' {
    It 'quatro tarefas, nada marcado, só disco pede admin, cache de ícones medido' {
        $local = New-LocalFalsa
        $alvos = @(Find-Alvos -PastaLocal $local)
        ($alvos | ForEach-Object Id) -join ',' | Should -Be 'dns,icones,otimizar-c,componentes'
        @($alvos | Where-Object Selecionado).Count | Should -Be 0
        ($alvos | Where-Object RequerAdmin | ForEach-Object Id) -join ',' | Should -Be 'otimizar-c,componentes'
        ($alvos | Where-Object Id -eq 'icones').Tamanho | Should -Be 350
    }
}

Describe 'Invoke-Acao' {
    BeforeEach { Set-SistemaFalso }

    It 'DNS: ipconfig /flushdns' {
        (Invoke-Acao -Alvos @([pscustomobject]@{ Id = 'dns' })).Status | Should -Be 'Feito'
        $global:TmdTesteChamadas | Should -Be @('ipconfig.exe /flushdns')
    }

    It 'ícones: fecha o Explorador, apaga só os iconcache e abre o Explorador de novo' {
        $local = New-LocalFalsa
        $r = Invoke-Acao -Alvos @([pscustomobject]@{ Id = 'icones' }) -PastaLocal $local
        $r.Status | Should -Be 'Feito'
        $r.Liberado | Should -Be 350
        Test-Path "$local\IconCache.db" | Should -BeFalse
        Test-Path "$local\Microsoft\Windows\Explorer\iconcache_32.db" | Should -BeFalse
        Test-Path "$local\Microsoft\Windows\Explorer\thumbcache_96.db" | Should -BeTrue
        $global:TmdTesteChamadas -join '|' | Should -Be 'taskkill.exe /f /im explorer.exe|abrir explorer'
    }

    It 'ícones: o Explorador volta mesmo se apagar falhar' {
        $local = New-LocalFalsa
        Mock Remove-TmdItem -ModuleName otimizar { throw 'falhou' }
        { Invoke-Acao -Alvos @([pscustomobject]@{ Id = 'icones' }) -PastaLocal $local } | Should -Throw
        $global:TmdTesteChamadas[-1] | Should -Be 'abrir explorer'
    }

    It 'ícones: arquivo ainda preso vira parcial, sugerindo reiniciar' {
        $local = New-LocalFalsa
        $trava = [IO.File]::Open("$local\IconCache.db", 'Open', 'Read', 'None')
        try { $r = Invoke-Acao -Alvos @([pscustomobject]@{ Id = 'icones' }) -PastaLocal $local }
        finally { $trava.Close() }
        $r.Status | Should -Be 'Parcial'
        $r.Motivo | Should -Match 'reiniciar'
    }

    It 'disco e componentes: defrag C: /O e DISM StartComponentCleanup (sem ResetBase)' {
        Invoke-Acao -Alvos @([pscustomobject]@{ Id = 'otimizar-c' }, [pscustomobject]@{ Id = 'componentes' }) | Out-Null
        $global:TmdTesteChamadas -join '|' | Should -Be 'defrag.exe C: /O|DISM.exe /Online /Cleanup-Image /StartComponentCleanup'
        $global:TmdTesteChamadas -join '|' | Should -Not -Match 'ResetBase'
    }

    It 'código diferente de zero vira erro' {
        Set-SistemaFalso -Codigos @{ 'defrag.exe C: /O' = 5 }
        (Invoke-Acao -Alvos @([pscustomobject]@{ Id = 'otimizar-c' })).Motivo | Should -Match 'código 5'
    }

    It '-Simular não roda nada; tarefa desconhecida é erro' {
        (Invoke-Acao -Alvos @([pscustomobject]@{ Id = 'icones' }) -Simular).Status | Should -Be 'Simulado'
        (Invoke-Acao -Alvos @([pscustomobject]@{ Id = 'turbo' })).Status | Should -Be 'Erro'
        $global:TmdTesteChamadas.Count | Should -Be 0
    }
}
