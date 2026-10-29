@{
    Severity     = @('Error', 'Warning')
    ExcludeRules = @(
        # A CLI usa cores; módulos são proibidos de usar Write-Host pelo teste de contrato.
        'PSAvoidUsingWriteHost'
        # A simulação é feita pelo -Simular do núcleo, não por ShouldProcess.
        'PSUseShouldProcessForStateChangingFunctions'
        # Substantivos em português ("Alvos", "Requisitos") não seguem a regra de plural do inglês.
        'PSUseSingularNouns'
    )
}
