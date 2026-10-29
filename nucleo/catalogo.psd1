@{
    # Módulos que o Tamanduá conhece. É por esta lista que ele sabe avisar quando um está faltando.
    # A ordem aqui é a ordem em que aparecem na CLI e na interface.
    Modulos = @(
        @{ Nome = 'status';       Grupo = 'Sistema';    Descricao = 'Painel do sistema (CPU, memória, disco, rede)' }
        @{ Nome = 'analisar';     Grupo = 'Limpeza';    Descricao = 'Mostra o que ocupa espaço no disco' }
        @{ Nome = 'limpar';       Grupo = 'Limpeza';    Descricao = 'Remove caches, temporários e logs' }
        @{ Nome = 'purgar';       Grupo = 'Limpeza';    Descricao = 'Remove artefatos de projeto (node_modules, target...)' }
        @{ Nome = 'instaladores'; Grupo = 'Limpeza';    Descricao = 'Encontra instaladores esquecidos (.exe, .msi, .iso)' }
        @{ Nome = 'desinstalar';  Grupo = 'Programas';  Descricao = 'Desinstala programas e restos' }
        @{ Nome = 'programas';    Grupo = 'Programas';  Descricao = 'Instala e atualiza programas via winget' }
        @{ Nome = 'ajustes';      Grupo = 'Ajustes';    Descricao = 'Privacidade, desempenho e preferências (reversível)' }
        @{ Nome = 'recursos';     Grupo = 'Ajustes';    Descricao = 'Recursos opcionais do Windows (WSL, Hyper-V, .NET 3.5...)' }
        @{ Nome = 'atualizacoes'; Grupo = 'Ajustes';    Descricao = 'Política do Windows Update' }
        @{ Nome = 'otimizar';     Grupo = 'Manutenção'; Descricao = 'Tarefas de manutenção do Windows' }
        @{ Nome = 'reparos';      Grupo = 'Manutenção'; Descricao = 'SFC, DISM, reset de rede e do Windows Update' }
    )
}
