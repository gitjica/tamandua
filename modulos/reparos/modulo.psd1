@{
    Nome             = 'reparos'
    Versao           = '0.1.0'
    Descricao        = 'SFC, DISM, reset de rede e do Windows Update'
    Arquivo          = 'reparos.psm1'
    Escreve          = $true
    # O núcleo pede o UAC uma vez e roda o lote num processo de administrador.
    RequerAdmin      = $true
    ContratoMinimo   = 1
    Icone            = 'chave'
    RotuloAcao       = 'Executar'
    Resultado        = 'Mudancas'
    AvisoConfirmacao = 'Vai pedir permissão de administrador uma vez. Alguns reparos levam vários minutos.'
    # Passos mostrados no alto da página (dá para fechar).
    Dica = 'Para quando algo estiver quebrado: clique no reparo e em Executar. Alguns levam vários minutos.'
}
