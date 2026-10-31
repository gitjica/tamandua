@{
    Nome           = 'limpar'
    Versao         = '0.2.0'
    Descricao      = 'Temporários, caches de navegadores, apps e jogos, logs e Lixeira'
    Arquivo        = 'limpar.psm1'
    Escreve        = $true
    # Só as categorias do sistema (Windows\Temp, Otimização de Entrega...) pedem admin, num único UAC por vez.
    RequerAdmin    = $true
    ContratoMinimo = 1
    Icone          = 'vassoura'
    RotuloAcao     = 'Limpar'
    # Passos mostrados no alto da página (dá para fechar).
    Dica = '1. Clique no que quer limpar (cada quadro diz quanto libera; o mais seguro já vem marcado).   2. Simular mostra o que sairia, sem apagar nada.   3. Limpar.'
}
