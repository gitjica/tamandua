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
}
