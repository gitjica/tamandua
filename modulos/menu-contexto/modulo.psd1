@{
    Nome           = 'menu-contexto'
    Versao         = '0.1.0'
    Descricao      = 'Menu do botão direito: clássico no Windows 11 e sem os itens que você não usa (reversível)'
    Arquivo        = 'menu-contexto.psm1'
    Escreve        = $true
    # Itens do Windows e de programas ficam em HKLM: um único UAC; menu clássico e "Enviar para" rodam como o usuário.
    RequerAdmin    = $true
    ContratoMinimo = 1
    Icone          = 'menu'
    RotuloAcao     = 'Aplicar'
    Resultado      = 'Mudancas'
    # Texto das pastas na grade.
    NomeItens = 'item|itens'
    # Passos mostrados no alto da página (dá para fechar).
    Dica = '1. Clique nos itens que quer tirar do botão direito (ou use Marcar).   2. Aplicar: o Explorador reinicia sozinho. Um item "aplicado", se marcado, volta para o menu.'
}
