@{
    Nome              = 'programas'
    Versao            = '0.1.0'
    Descricao         = 'Instala e atualiza programas via winget'
    Arquivo           = 'programas.psm1'
    Escreve           = $true
    RequerAdmin       = $false
    ContratoMinimo    = 1
    # A janela mostra em grade, com o ícone de cada programa (dá para trocar para lista).
    Visualizacao      = 'Grade'
    Icone             = 'pacote'
    RotuloAcao        = 'Instalar ou atualizar'
    Resultado         = 'Mudancas'
    # Vai junto da pergunta de confirmação (CLI e interface).
    AvisoConfirmacao  = 'Ao confirmar, você aceita as licenças dos programas escolhidos. Alguns instaladores pedem permissão de administrador.'
    # Texto das pastas na grade.
    NomeItens = 'programa|programas'
    # Passos mostrados no alto da página (dá para fechar).
    Dica = '1. Abra uma pasta e clique nos programas que quer (o selo verde diz o que já está instalado).   2. Instalar ou atualizar: tudo pelo winget, sem abrir instaladores.'
}
