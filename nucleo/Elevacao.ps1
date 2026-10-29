# Permissão de administrador. Por enquanto só detecta; a reexecução elevada de um lote vem com o módulo ajustes.

function Test-TmdAdministrador {
    [CmdletBinding()]
    param()
    $identidade = [Security.Principal.WindowsIdentity]::GetCurrent()
    (New-Object Security.Principal.WindowsPrincipal($identidade)).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}
