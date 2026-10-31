@{
    Nome             = 'otimizar'
    Versao           = '0.1.0'
    Descricao        = 'Tarefas de manutenção do Windows'
    Arquivo          = 'otimizar.psm1'
    Escreve          = $true
    # Só os itens com RequerAdmin vão para o processo de administrador; os outros rodam como você.
    RequerAdmin      = $true
    ContratoMinimo   = 1
    Icone            = 'velocimetro'
    RotuloAcao       = 'Executar'
    Resultado        = 'Mudancas'
    AvisoConfirmacao = 'Itens com escudo pedem permissão de administrador (uma vez para todos).'
    # Passos mostrados no alto da página (dá para fechar).
    Dica = 'Clique nas tarefas e em Executar. São seguras e podem ser repetidas sempre que quiser.'
}
