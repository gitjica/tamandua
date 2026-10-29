@{
    Nome              = 'programas'
    Versao            = '0.1.0'
    Descricao         = 'Instala e atualiza programas via winget'
    Arquivo           = 'programas.psm1'
    Escreve           = $true
    RequerAdmin       = $false
    ContratoMinimo    = 1
    Icone             = 'pacote'
    RotuloAcao        = 'Instalar ou atualizar'
    Resultado         = 'Mudancas'
    # Vai junto da pergunta de confirmação (CLI e interface).
    AvisoConfirmacao  = 'Ao confirmar, você aceita as licenças dos programas escolhidos. Alguns instaladores pedem permissão de administrador.'
}
