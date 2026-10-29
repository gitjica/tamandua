BeforeAll {
    . (Join-Path $PSScriptRoot '..\Ajudantes.ps1')
    Import-Module (Join-Path $script:RaizProjeto 'nucleo\Tamandua.Nucleo.psm1') -Force -DisableNameChecking
}

Describe 'Format-TmdTamanho' {
    BeforeAll {
        $culturaOriginal = [Threading.Thread]::CurrentThread.CurrentCulture
        [Threading.Thread]::CurrentThread.CurrentCulture = 'pt-BR'
    }
    AfterAll {
        [Threading.Thread]::CurrentThread.CurrentCulture = $culturaOriginal
    }

    It '<Bytes> bytes vira "<Texto>"' -ForEach @(
        @{ Bytes = 0; Texto = '0 B' }
        @{ Bytes = 512; Texto = '512 B' }
        @{ Bytes = 1536; Texto = '1,5 KB' }
        @{ Bytes = 1048576; Texto = '1,0 MB' }
        @{ Bytes = 9771253760; Texto = '9,1 GB' }
        @{ Bytes = 2199023255552; Texto = '2,0 TB' }
        @{ Bytes = -1; Texto = 'desconhecido' }
    ) {
        Format-TmdTamanho -Bytes $Bytes | Should -Be $Texto
    }
}

Describe 'Write-TmdAlvos' {
    It 'aceita objetos sem as propriedades opcionais e lista vazia' {
        { Write-TmdAlvos -Alvos @([pscustomobject]@{ Nome = 'só nome' }) 6>$null } | Should -Not -Throw
        { Write-TmdAlvos -Alvos @() 6>$null } | Should -Not -Throw
    }

    It 'corta nome longo e deixa espaço antes do valor' {
        $alvo = [pscustomobject]@{ Nome = 'Intel(R) Wi-Fi 6E AX210 160MHz extra longo'; Categoria = 'Rede'; Detalhe = '192.168.1.11' }
        $pecas = @(Write-TmdAlvos -Alvos @($alvo) 6>&1 | ForEach-Object { [string]$_ })
        $coluna = $pecas | Where-Object { $_ -like '  Intel*' }
        $coluna | Should -Match '…\s+$'
        $coluna.Length | Should -Be 30
    }
}
