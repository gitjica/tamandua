@{
    Nome             = 'fonte'
    Versao           = '0.1.0'
    Descricao        = 'Troca a fonte do Windows (Segoe UI) por qualquer fonte instalada, com volta'
    Arquivo          = 'fonte.psm1'
    Escreve          = $true
    # Windows\Fonts e o registro das fontes ficam na máquina: um único UAC.
    RequerAdmin      = $true
    ContratoMinimo   = 1
    Icone            = 'fonte'
    RotuloAcao       = 'Aplicar'
    Resultado        = 'Mudancas'
    AvisoConfirmacao = 'Vale depois de reiniciar o Windows. Para voltar: Histórico > Desfazer, ou "Segoe UI original" nesta página.'
}
