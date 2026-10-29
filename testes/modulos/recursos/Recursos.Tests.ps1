# Módulo recursos. Estado dos recursos e DISM são simulados (Mock): nenhum teste liga ou desliga nada.
# Só um teste lê o estado real, sem mudar nada.

BeforeAll {
    . (Join-Path $PSScriptRoot '..\..\Ajudantes.ps1')
    Import-Module (Join-Path $script:RaizProjeto 'nucleo\Tamandua.Nucleo.psm1') -Force -DisableNameChecking -Global
    Import-Module (Join-Path $script:RaizProjeto 'modulos\recursos\recursos.psm1') -Force -DisableNameChecking

    function Set-WindowsFalso {
        param([hashtable]$Estados, [int]$Codigo = 0)
        $global:TmdTesteEstados = $Estados
        $global:TmdTesteCodigo = $Codigo
        $global:TmdTesteChamadas = [System.Collections.Generic.List[string]]::new()
        Mock Get-EstadoRecurso -ModuleName recursos { $global:TmdTesteEstados.Clone() }
        Mock Invoke-TmdPrograma -ModuleName recursos {
            $global:TmdTesteChamadas.Add("$Arquivo $Argumentos")
            [pscustomobject]@{ Codigo = $global:TmdTesteCodigo; Saida = @() }
        }
    }
}

AfterAll {
    Remove-Variable -Name TmdTesteEstados, TmdTesteCodigo, TmdTesteChamadas -Scope Global -ErrorAction SilentlyContinue
}

Describe 'Find-Alvos' {
    BeforeEach {
        Set-WindowsFalso -Estados @{ 'Microsoft-Windows-Subsystem-Linux' = 'ligado'; 'NetFx3' = 'desligado'; 'SMB1Protocol' = 'desligado' }
    }

    It 'estado de cada recurso; o que não existe nesta edição não pode ser marcado' {
        $alvos = @(Find-Alvos)
        ($alvos | Where-Object Id -eq 'wsl').Selo | Should -Be 'ligado'
        ($alvos | Where-Object Id -eq 'wsl').Estado | Should -Be 'Aplicado'
        ($alvos | Where-Object Id -eq 'dotnet35').Selo | Should -Be 'desligado'
        ($alvos | Where-Object Id -eq 'dotnet35').Mudancas[0] | Should -Match 'Enable-Feature /FeatureName:NetFx3'
        ($alvos | Where-Object Id -eq 'wsl').Mudancas[0] | Should -Match '^Desliga'
        $sandbox = $alvos | Where-Object Id -eq 'sandbox'
        $sandbox.Selo | Should -Be 'não existe nesta edição'
        $sandbox.Selecionavel | Should -BeFalse
        @($alvos | Where-Object Selecionado).Count | Should -Be 0
        ($alvos | Where-Object Id -eq 'smb1').Risco | Should -Be 'Alto'
    }

}

# Fora do Describe acima: lá o BeforeEach troca Get-EstadoRecurso por Mock.
Describe 'Leitura real' {
    It 'lê o estado real sem admin (só leitura)' {
        $real = InModuleScope recursos { Get-EstadoRecurso }
        $real.Count | Should -BeGreaterThan 10
        @($real.Values | Select-Object -Unique) | Should -Not -Contain $null
    }
}

Describe 'Invoke-Acao' {
    It 'liga o que está desligado e desliga o que está ligado, pelo estado lido agora' {
        Set-WindowsFalso -Estados @{ 'Microsoft-Windows-Subsystem-Linux' = 'ligado'; 'NetFx3' = 'desligado' }
        # O alvo diz "desligado" para o WSL, mas a máquina diz ligado: vale a máquina.
        $r = @(Invoke-Acao -Alvos @([pscustomobject]@{ Id = 'dotnet35' }, [pscustomobject]@{ Id = 'wsl'; Estado = 'NaoAplicado' }))
        @($r | ForEach-Object Status | Select-Object -Unique) | Should -Be 'Feito'
        $global:TmdTesteChamadas[0] | Should -Be 'dism.exe /Online /Enable-Feature /FeatureName:NetFx3 /All /NoRestart /Quiet'
        $global:TmdTesteChamadas[1] | Should -Be 'dism.exe /Online /Disable-Feature /FeatureName:Microsoft-Windows-Subsystem-Linux /NoRestart /Quiet'
    }

    It '3010 é sucesso pedindo reinício; outro código é erro (com dica para o .NET 3.5)' {
        Set-WindowsFalso -Estados @{ 'NetFx3' = 'desligado' } -Codigo 3010
        (Invoke-Acao -Alvos @([pscustomobject]@{ Id = 'dotnet35' })).Motivo | Should -Match 'reinicie'
        Set-WindowsFalso -Estados @{ 'NetFx3' = 'desligado' } -Codigo 87
        $r = Invoke-Acao -Alvos @([pscustomobject]@{ Id = 'dotnet35' })
        $r.Status | Should -Be 'Erro'
        $r.Motivo | Should -Match 'código 87.*internet'
    }

    It 'recurso que não existe nesta edição é ignorado; fora do catálogo é erro; -Simular não chama o DISM' {
        Set-WindowsFalso -Estados @{ 'NetFx3' = 'desligado' }
        (Invoke-Acao -Alvos @([pscustomobject]@{ Id = 'sandbox' })).Status | Should -Be 'Ignorado'
        (Invoke-Acao -Alvos @([pscustomobject]@{ Id = 'Microsoft-Windows-Defender' })).Status | Should -Be 'Erro'
        (Invoke-Acao -Alvos @([pscustomobject]@{ Id = 'dotnet35' }) -Simular).Mudancas[0] | Should -Match '^ligar: dism'
        $global:TmdTesteChamadas.Count | Should -Be 0
    }
}
