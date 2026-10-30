@{
    Nome             = 'fonte'
    Versao           = '0.2.0'
    Descricao        = 'Troca a fonte do Windows (Segoe UI) por qualquer fonte instalada, com volta'
    Arquivo          = 'fonte.psm1'
    Escreve          = $true
    # Windows\Fonts e o registro das fontes ficam na máquina: um único UAC.
    RequerAdmin      = $true
    ContratoMinimo   = 1
    Icone            = 'fonte'
    RotuloAcao       = 'Aplicar'
    Resultado        = 'Mudancas'
    Visualizacao     = 'Grade'
    AvisoConfirmacao = 'Vale depois de reiniciar o Windows. Para voltar: Segoe UI original nesta página, ou Histórico > Desfazer.'
    # Passos mostrados no alto da página.
    Dica             = '1. Abra uma pasta e clique na fonte que quer (cada quadro mostra como ela é).   2. Se quiser, em Tamanho do texto escolha outro tamanho ou Personalizado; sem escolher, fica no automático.   3. Aplicar e reiniciar o Windows.'
    # Um item de cada grupo (marcar outro troca); a barra de baixo mostra o que está escolhido em cada um.
    Grupos           = @(
        @{ Nome = 'fonte'; Rotulo = 'Fonte'; Vazio = 'escolha uma' }
        @{ Nome = 'tamanho'; Rotulo = 'Tamanho'; Vazio = 'automático' }
    )
    # Texto das pastas: "23 opções".
    NomeItens        = 'opção|opções'
}
