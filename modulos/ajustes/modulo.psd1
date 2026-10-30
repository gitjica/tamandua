@{
    Nome           = 'ajustes'
    Versao         = '0.2.0'
    Descricao      = 'Os ajustes do WinUtil e mais: privacidade, desempenho e preferências (reversível)'
    Arquivo        = 'ajustes.psm1'
    Escreve        = $true
    # Os ajustes de sistema (HKLM, serviços, scripts) pedem admin num único UAC; os de HKCU rodam como o usuário.
    RequerAdmin    = $true
    ContratoMinimo = 1
    Icone          = 'ajustes'
    RotuloAcao     = 'Aplicar'
    # Resultado de Invoke-Acao fala de mudanças, não de espaço liberado.
    Resultado      = 'Mudancas'
    # Texto das pastas na grade.
    NomeItens = 'ajuste|ajustes'
}
