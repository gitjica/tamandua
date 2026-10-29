# Módulo analisar: só lê. Conteúdo de pasta sempre numa árvore da sandbox; o início (unidades) lê o sistema real.

BeforeAll {
    . (Join-Path $PSScriptRoot '..\..\Ajudantes.ps1')
    Import-Module (Join-Path $script:RaizProjeto 'nucleo\Tamandua.Nucleo.psm1') -Force -DisableNameChecking -Global
    Import-Module (Join-Path $script:RaizProjeto 'modulos\analisar\analisar.psm1') -Force -DisableNameChecking

    function New-ArvoreAnalise {
        $base = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
        New-ArvoreFalsa -Pasta $base -Arquivos @{
            'grande\a.bin'        = ('a' * 6000)
            'grande\sub\b.bin'    = ('b' * 2000)
            'media\c.bin'         = ('c' * 1500)
            'solto.txt'           = ('d' * 500)
        } | Out-Null
        $base
    }
}

Describe 'Conteúdo de uma pasta' {
    BeforeEach { $base = New-ArvoreAnalise }

    It 'lista do maior para o menor, com resumo, porcentagem e "pasta acima"' {
        $alvos = @(Find-Alvos -Caminho $base)
        $alvos[0].Id | Should -Be 'acima'
        $alvos[0].Navegavel | Should -BeTrue
        $total = $alvos | Where-Object Id -eq 'total'
        $total.Tamanho | Should -Be 10000
        $conteudo = @($alvos | Where-Object { $_.Id -like 'item:*' })
        ($conteudo | ForEach-Object Nome) -join ',' | Should -Be 'grande\,media\,solto.txt'
        $conteudo[0].Tamanho | Should -Be 8000
        $conteudo[0].Valor | Should -Be 80
        $conteudo[0].Navegavel | Should -BeTrue
        $conteudo[0].Detalhe | Should -Match '80% · 2 arquivo'
        $conteudo[2].Navegavel | Should -BeFalse -Because 'arquivo não abre como pasta'
    }

    It 'link: aparece, não é medido nem navegável, e o destino não entra no total' {
        $fora = New-ArvoreFalsa -Pasta (Join-Path $TestDrive "fora-$([guid]::NewGuid().ToString('N'))") -Arquivos @{ 'enorme.bin' = ('x' * 50000) }
        New-Item -ItemType Junction -Path "$base\atalho" -Target $fora | Out-Null
        $alvos = @(Find-Alvos -Caminho $base)
        ($alvos | Where-Object Id -eq 'total').Tamanho | Should -Be 10000
        $link = $alvos | Where-Object Id -eq 'item:atalho'
        $link.Detalhe | Should -Match 'link'
        $link.Navegavel | Should -BeFalse
        $link.Valor | Should -BeNullOrEmpty
    }

    It 'pasta sem acesso: avisa que o total pode ser maior' {
        $trancada = Join-Path $base 'trancada'
        New-ArvoreFalsa -Pasta $trancada -Arquivos @{ 'segredo.bin' = ('s' * 100) } | Out-Null
        $acl = Get-Acl -LiteralPath $trancada
        $regra = New-Object Security.AccessControl.FileSystemAccessRule([Security.Principal.WindowsIdentity]::GetCurrent().Name, 'ListDirectory', 'Deny')
        $acl.AddAccessRule($regra)
        Set-Acl -LiteralPath $trancada -AclObject $acl
        try {
            $alvos = @(Find-Alvos -Caminho $base)
        }
        finally {
            $acl.RemoveAccessRule($regra) | Out-Null
            Set-Acl -LiteralPath $trancada -AclObject $acl
        }
        $total = $alvos | Where-Object Id -eq 'total'
        $total.Detalhe | Should -Match '1 pasta\(s\) sem acesso'
        $total.Nivel | Should -Be 'Atencao'
        ($alvos | Where-Object Id -eq 'item:trancada').Detalhe | Should -Match '1 sem acesso'
    }

    It 'mais de 40 itens: o resto vira "outros N itens"' {
        foreach ($i in 1..45) { [IO.File]::WriteAllText((Join-Path $base "f$i.txt"), 'x') }
        $alvos = @(Find-Alvos -Caminho $base)
        @($alvos | Where-Object { $_.Id -like 'item:*' }).Count | Should -Be 40
        # 3 itens da árvore + 45 arquivos = 48; mostra 40, sobram 8.
        ($alvos | Where-Object Id -eq 'outros').Nome | Should -Be 'outros 8 item(ns)'
    }

    It 'ids únicos e nada muda no disco' {
        $antes = Get-AssinaturaPasta $base
        $alvos = @(Find-Alvos -Caminho $base)
        @($alvos.Id | Select-Object -Unique).Count | Should -Be $alvos.Count
        Get-AssinaturaPasta $base | Should -Be $antes
    }

    It 'pasta que não existe é erro' {
        { Find-Alvos -Caminho (Join-Path $base 'nao-existe') } | Should -Throw '*não encontrada*'
    }
}

Describe 'Início' {
    It 'mostra as unidades com uso e atalhos navegáveis, sem medir nada pesado' {
        $tempo = Measure-Command { $alvos = @(Find-Alvos) }
        $tempo.TotalSeconds | Should -BeLessThan 5
        $c = $alvos | Where-Object Id -eq 'unidade-c'
        $c | Should -Not -BeNullOrEmpty
        $c.Navegavel | Should -BeTrue
        $c.Valor | Should -BeGreaterThan 0
        ($alvos | Where-Object Id -eq 'atalho-perfil').Caminho | Should -Be ([Environment]::GetFolderPath('UserProfile'))
    }
}

Describe 'Medição rápida' {
    It 'mede milhares de arquivos em pouco tempo' {
        $pasta = Join-Path $TestDrive 'muitos'
        foreach ($d in 1..20) {
            $sub = [IO.Directory]::CreateDirectory((Join-Path $pasta "d$d")).FullName
            foreach ($f in 1..150) { [IO.File]::WriteAllText((Join-Path $sub "$f.txt"), 'abc') }
        }
        $tempo = Measure-Command { $m = Measure-TmdTamanho -Caminho $pasta }
        $m.Arquivos | Should -Be 3000
        $m.Bytes | Should -Be 9000
        $tempo.TotalSeconds | Should -BeLessThan 3
    }
}

Describe 'Pela linha de comando' {
    # Sem "<...>" no nome do teste: o Pester trata isso como variável a expandir.
    It 'tamandua analisar PASTA mostra o conteúdo; argumento a mais ou em módulo que não navega é erro' {
        $base = New-ArvoreAnalise
        $projeto = New-ProjetoFalso -Pai $TestDrive -ModulosReais 'analisar', 'status'
        $r = Invoke-Tamandua -Raiz $projeto -Argumentos 'analisar', "`"$base`""
        $r.Codigo | Should -Be 0
        $r.Saida | Should -Match 'grande\\\s+7[,.]8 KB · 80%'
        (Invoke-Tamandua -Raiz $projeto -Argumentos 'analisar', "`"$base`"", 'extra').Codigo | Should -Be 1
        (Invoke-Tamandua -Raiz $projeto -Argumentos 'status', "`"$base`"").Codigo | Should -Be 1
        (Invoke-Tamandua -Raiz $projeto -Argumentos 'analisar', "`"$base\nao-existe`"").Saida | Should -Match 'não encontrada'
    }
}
