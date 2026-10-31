@{
    Nome             = 'atualizacoes'
    Versao           = '0.1.0'
    Descricao        = 'Política do Windows Update'
    Arquivo          = 'atualizacoes.psm1'
    Escreve          = $true
    RequerAdmin      = $true
    ContratoMinimo   = 1
    Icone            = 'atualizar'
    RotuloAcao       = 'Aplicar'
    Resultado        = 'Mudancas'
    AvisoConfirmacao = 'Vai pedir permissão de administrador uma vez. Desligar o Windows Update de vez não é oferecido.'
    # Passos mostrados no alto da página (dá para fechar).
    Dica = 'Escolha como o Windows Update se comporta (ou use Marcar). Nada aqui desliga as atualizações de segurança.'
}
