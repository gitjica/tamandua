@{
    Nome             = 'desinstalar'
    Versao           = '0.1.0'
    Descricao        = 'Desinstala programas e restos'
    Arquivo          = 'desinstalar.psm1'
    Escreve          = $true
    RequerAdmin      = $false
    ContratoMinimo   = 1
    # A janela mostra em grade, com o ícone de cada programa (dá para trocar para lista).
    Visualizacao     = 'Grade'
    Icone            = 'remover'
    RotuloAcao       = 'Desinstalar'
    Resultado        = 'Mudancas'
    AvisoConfirmacao = 'O desinstalador de cada programa vai abrir: responda a ele. Restos vão para a Lixeira.'
    # Texto das pastas na grade.
    NomeItens = 'programa|programas'
}
