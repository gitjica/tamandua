# Elevação por lote. O UAC nunca é pedido de verdade: Start-TmdProcessoElevado é trocado por um processo comum
# que roda o mesmo "tamandua.ps1 __elevado", então o caminho todo (pedido -> processo -> resposta) é testado.

BeforeAll {
    . (Join-Path $PSScriptRoot '..\Ajudantes.ps1')
    Import-Module (Join-Path $script:RaizProjeto 'nucleo\Tamandua.Nucleo.psm1') -Force -DisableNameChecking -Global

    function New-ProjetoComAdmin {
        $raiz = New-ProjetoFalso -Pai $TestDrive -Catalogo 'precisa', 'comum'
        $codigo = @'
function Test-Requisitos { @{ Ok = $true } }
function Find-Alvos { [pscustomobject]@{ Id = 'a'; Nome = 'A'; Categoria = 'C'; Estado = 'NaoSeAplica'; Detalhe = ''; Caminho = ''; Tamanho = [int64]0; Risco = 'Baixo'; Selecionado = $true; Destino = 'NaoSeAplica'; RequerAdmin = $true; Reversivel = $false; Mudancas = @() } }
function Invoke-Acao {
    param([object[]]$Alvos, [switch]$Simular)
    foreach ($a in $Alvos) { [pscustomobject]@{ Id = $a.Id; Status = $(if ($Simular) { 'Simulado' } else { 'Feito' }); Liberado = [int64]0; Motivo = "processo $PID"; Mudancas = @() } }
}
'@
        New-ModuloFalso -Raiz $raiz -Nome 'precisa' -Manifesto @{ Escreve = $true; RequerAdmin = $true } -Codigo $codigo | Out-Null
        New-ModuloFalso -Raiz $raiz -Nome 'comum' -Manifesto @{ Escreve = $true } -Codigo $codigo | Out-Null
        $raiz
    }
}

Describe 'Invoke-TmdAcaoModulo' {
    BeforeEach {
        $raiz = New-ProjetoComAdmin
        Mock Test-TmdAdministrador -ModuleName Tamandua.Nucleo { $false }
    }

    It 'módulo sem RequerAdmin roda aqui mesmo' {
        Mock Start-TmdProcessoElevado -ModuleName Tamandua.Nucleo { throw 'não devia pedir admin' }
        $info = Get-TmdModulo -Raiz $raiz -Nome 'comum'
        $r = @(Invoke-TmdAcaoModulo -Info $info -Alvos @([pscustomobject]@{ Id = 'a' }) -Raiz $raiz)
        $r[0].Motivo | Should -Be "processo $PID"
    }

    It 'módulo com RequerAdmin: um processo à parte roda o lote e devolve os resultados; temporários somem' {
        Mock Start-TmdProcessoElevado -ModuleName Tamandua.Nucleo {
            $global:TmdTestePedido = $Pedido
            $argumentos = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', "`"$Script`"", '__elevado', "`"$Pedido`"")
            (Start-Process -FilePath 'powershell.exe' -ArgumentList $argumentos -WindowStyle Hidden -Wait -PassThru).ExitCode
        }
        $info = Get-TmdModulo -Raiz $raiz -Nome 'precisa'
        $r = @(Invoke-TmdAcaoModulo -Info $info -Alvos @([pscustomobject]@{ Id = 'a'; RequerAdmin = $true }, [pscustomobject]@{ Id = 'b'; RequerAdmin = $true }) -Raiz $raiz)
        $r.Count | Should -Be 2
        ($r | ForEach-Object Id) -join ',' | Should -Be 'a,b'
        $r[0].Status | Should -Be 'Feito'
        $r[0].Motivo | Should -Match '^processo \d+$'
        $r[0].Motivo | Should -Not -Be "processo $PID" -Because 'rodou em outro processo'
        Should -Invoke Start-TmdProcessoElevado -ModuleName Tamandua.Nucleo -Times 1 -Exactly
        Test-Path -LiteralPath $global:TmdTestePedido | Should -BeFalse
    }

    It 'só os itens que pedem admin vão para o processo elevado; a ordem dos resultados é a dos alvos' {
        Mock Start-TmdProcessoElevado -ModuleName Tamandua.Nucleo {
            $argumentos = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', "`"$Script`"", '__elevado', "`"$Pedido`"")
            (Start-Process -FilePath 'powershell.exe' -ArgumentList $argumentos -WindowStyle Hidden -Wait -PassThru).ExitCode
        }
        $info = Get-TmdModulo -Raiz $raiz -Nome 'precisa'
        $r = @(Invoke-TmdAcaoModulo -Info $info -Raiz $raiz -Alvos @(
                [pscustomobject]@{ Id = 'usuario1'; RequerAdmin = $false }
                [pscustomobject]@{ Id = 'admin'; RequerAdmin = $true }
                [pscustomobject]@{ Id = 'usuario2' }
            ))
        ($r | ForEach-Object Id) -join ',' | Should -Be 'usuario1,admin,usuario2'
        ($r | Where-Object Id -eq 'usuario1').Motivo | Should -Be "processo $PID"
        ($r | Where-Object Id -eq 'usuario2').Motivo | Should -Be "processo $PID"
        ($r | Where-Object Id -eq 'admin').Motivo | Should -Not -Be "processo $PID"
        Should -Invoke Start-TmdProcessoElevado -ModuleName Tamandua.Nucleo -Times 1 -Exactly
    }

    It 'simular nunca pede admin' {
        Mock Start-TmdProcessoElevado -ModuleName Tamandua.Nucleo { throw 'não devia pedir admin' }
        $info = Get-TmdModulo -Raiz $raiz -Nome 'precisa'
        (Invoke-TmdAcaoModulo -Info $info -Alvos @([pscustomobject]@{ Id = 'a' }) -Simular -Raiz $raiz).Status | Should -Be 'Simulado'
    }

    It 'UAC negado: tudo ignorado, com o motivo, sem exceção' {
        Mock Start-TmdProcessoElevado -ModuleName Tamandua.Nucleo { throw 'A operação foi cancelada pelo usuário' }
        $info = Get-TmdModulo -Raiz $raiz -Nome 'precisa'
        $r = @(Invoke-TmdAcaoModulo -Info $info -Alvos @([pscustomobject]@{ Id = 'a'; RequerAdmin = $true }) -Raiz $raiz)
        $r[0].Status | Should -Be 'Ignorado'
        $r[0].Motivo | Should -Match 'permissão de administrador negada'
    }

    It 'já sendo administrador, não abre outro processo' {
        Mock Test-TmdAdministrador -ModuleName Tamandua.Nucleo { $true }
        Mock Start-TmdProcessoElevado -ModuleName Tamandua.Nucleo { throw 'não devia pedir admin' }
        $info = Get-TmdModulo -Raiz $raiz -Nome 'precisa'
        (Invoke-TmdAcaoModulo -Info $info -Alvos @([pscustomobject]@{ Id = 'a' }) -Raiz $raiz).Motivo | Should -Be "processo $PID"
    }
}

Describe 'Comando interno __elevado' {
    It 'recusa pedido que não é um temporário do Tamanduá' {
        $raiz = New-ProjetoComAdmin
        $falso = Join-Path $TestDrive 'pedido.json'
        Set-Content -LiteralPath $falso -Value '{"Modulo":"precisa","Alvos":[],"Resposta":"C:\\Windows\\x.json"}'
        $r = Invoke-Tamandua -Raiz $raiz -Argumentos '__elevado', "`"$falso`""
        $r.Codigo | Should -Be 1
        $r.Erro | Should -Match 'pedido inválido'
    }

    It 'recusa resposta fora da pasta temporária' {
        $raiz = New-ProjetoComAdmin
        $pedido = New-TmdArquivoTemporario -Extensao '.json'
        Set-Content -LiteralPath $pedido -Value '{"Modulo":"precisa","Alvos":[{"Id":"a"}],"Resposta":"C:\\Users\\Public\\tamandua-x.json"}'
        try {
            $r = Invoke-Tamandua -Raiz $raiz -Argumentos '__elevado', "`"$pedido`""
            $r.Codigo | Should -Be 1
            Test-Path 'C:\Users\Public\tamandua-x.json' | Should -BeFalse
        }
        finally { Remove-TmdArquivoTemporario -Caminho $pedido }
    }
}

Describe 'Invoke-TmdPrograma' {
    It 'devolve código e saída, e registra no log' {
        $env:TAMANDUA_DADOS = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
        $r = Invoke-TmdPrograma -Arquivo 'cmd.exe' -Argumentos '/c echo ola & exit 3' -Modulo 'teste' -Id 'x'
        $r.Codigo | Should -Be 3
        $r.Saida | Should -Contain 'ola '
        $h = @(Get-TmdHistorico -Ultimos 1)[0]
        $h.Acao | Should -Be 'executar'
        $h.Status | Should -Be 'Erro'
        $h.Motivo | Should -Be 'código 3'
    }
}
