@{
    # Módulos que o Tamanduá conhece. É por esta lista que ele sabe avisar quando um está faltando.
    # A ordem aqui é a ordem em que aparecem na CLI e na interface.
    Modulos = @(
        @{ Nome = 'status';       Titulo = 'Status';        Grupo = 'Sistema';    Descricao = 'Painel do sistema (CPU, memória, disco, rede)' }
        @{ Nome = 'limpar';       Titulo = 'Limpar';        Grupo = 'Limpeza';    Descricao = 'Temporários, caches de navegadores, apps e jogos, logs e Lixeira' }
        @{ Nome = 'desinstalar';  Titulo = 'Desinstalar';   Grupo = 'Programas';  Descricao = 'Desinstala programas e restos' }
        @{ Nome = 'programas';    Titulo = 'Programas';     Grupo = 'Programas';  Descricao = 'Instala e atualiza programas via winget' }
        @{ Nome = 'ajustes';      Titulo = 'Ajustes';       Grupo = 'Ajustes';    Descricao = 'Todos os tweaks do WinUtil: privacidade, desempenho, apps e preferências' }
        @{ Nome = 'menu-contexto'; Titulo = 'Menu de contexto'; Grupo = 'Ajustes';    Descricao = 'Menu clássico no Windows 11 e sem os itens que você não usa' }
        @{ Nome = 'fonte';        Titulo = 'Fonte';         Grupo = 'Ajustes';    Descricao = 'Troca a fonte do Windows (Segoe UI) por qualquer fonte instalada, com volta' }
        @{ Nome = 'recursos';    Titulo = 'Recursos';      Grupo = 'Ajustes';    Descricao = 'Recursos opcionais do Windows (WSL, Hyper-V, .NET 3.5...)' }
        @{ Nome = 'atualizacoes'; Titulo = 'Atualizações';  Grupo = 'Ajustes';    Descricao = 'Política do Windows Update' }
        @{ Nome = 'otimizar';     Titulo = 'Otimizar';      Grupo = 'Manutenção'; Descricao = 'Tarefas de manutenção do Windows' }
        @{ Nome = 'reparos';      Titulo = 'Reparos';       Grupo = 'Manutenção'; Descricao = 'SFC, DISM, reset de rede e do Windows Update' }
    )
}
