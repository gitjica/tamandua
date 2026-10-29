BeforeAll {
    . (Join-Path $PSScriptRoot '..\Ajudantes.ps1')
    $pastaInterface = Join-Path $script:RaizProjeto 'interface'
    Import-Module (Join-Path $pastaInterface 'Interface.psm1') -Force -DisableNameChecking

    # Abre a janela de verdade, espera a primeira página e devolve o que estava na tela. Fecha sozinha em 30 s se travar.
    function Invoke-InterfaceTeste {
        param([Parameter(Mandatory)][string]$Raiz, [string]$Tema = 'claro')
        $resultado = @{ Carregou = $false }
        $aoCarregar = {
            param($tela)
            $c = $tela.Controles
            $resultado.Carregou = $true
            $resultado.Titulo = $c.TituloPagina.Text
            $resultado.Modulos = @($c.ListaModulos.ItemsSource)
            $resultado.Linhas = @($c.ListaAlvos.ItemsSource)
            $resultado.Mensagem = if ($c.PainelMensagem.Visibility -eq 'Visible') { $c.TituloMensagem.Text } else { $null }
            $resultado.Status = $c.TextoStatus.Text
            $tela.Janela.Close()
        }.GetNewClosure()
        Start-TmdInterface -Raiz $Raiz -Tema $Tema -AoCarregar $aoCarregar -FecharAposSeg 30
        $resultado
    }
}

Describe 'Tema' {
    It 'claro e escuro definem exatamente as mesmas cores' {
        $chaves = foreach ($t in 'tema-claro.xaml', 'tema-escuro.xaml') {
            $xml = [xml](Get-Content -LiteralPath (Join-Path $pastaInterface $t) -Raw -Encoding UTF8)
            , @($xml.ResourceDictionary.SolidColorBrush | ForEach-Object { $_.Key } | Sort-Object)
        }
        $chaves[0].Count | Should -BeGreaterThan 10
        ($chaves[0] -join ',') | Should -Be ($chaves[1] -join ',')
    }

    It 'nenhuma cor fixa fora dos arquivos de tema' {
        $arquivos = Get-ChildItem -LiteralPath $pastaInterface -File |
            Where-Object { $_.Extension -in '.xaml', '.ps1', '.psm1' -and $_.Name -notlike 'tema-*' }
        $achados = foreach ($a in $arquivos) {
            Select-String -LiteralPath $a.FullName -Pattern '#[0-9A-Fa-f]{6}\b|#[0-9A-Fa-f]{8}\b|Color\s*=\s*"[A-Za-z]' |
                ForEach-Object { "$($a.Name):$($_.LineNumber): $($_.Line.Trim())" }
        }
        $achados | Should -BeNullOrEmpty -Because ($achados -join "`n")
    }

    It 'a janela carrega com todos os controles, e trocar o tema troca as cores' {
        InModuleScope Interface -Parameters @{ Raiz = $script:RaizProjeto } {
            param($Raiz)
            $tela = New-TmdJanela -Raiz $Raiz -Tema 'claro'
            $tela.Controles.Count | Should -Be $script:NomesControles.Count
            $tela.Janela.FindResource('Fundo').Color.ToString() | Should -Be '#FFF3EADD'
            Set-TmdTema -Tela $tela -Tema 'escuro'
            $tela.Janela.FindResource('Fundo').Color.ToString() | Should -Be '#FF1A1716'
            $tela.Tema | Should -Be 'escuro'
            $tela.Janela.Close()
        }
    }
}

Describe 'Conversão para a tela' {
    It 'barra lateral: um cabeçalho por grupo, ícone e marcador por estado' {
        $modulos = @(
            [pscustomobject]@{ Nome = 'status'; Titulo = 'Status'; Grupo = 'Sistema'; Estado = 'ok'; Motivo = '' }
            [pscustomobject]@{ Nome = 'limpar'; Titulo = 'Limpar'; Grupo = 'Limpeza'; Estado = 'faltando'; Motivo = 'pasta x' }
            [pscustomobject]@{ Nome = 'outro'; Titulo = 'Outro'; Grupo = 'Limpeza'; Estado = 'indisponivel'; Motivo = 'sem winget' }
        )
        $itens = InModuleScope Interface -Parameters @{ M = $modulos } { param($M) ConvertTo-ItemNavegacao -Modulos $M }
        ($itens | ForEach-Object Tipo) -join ',' | Should -Be 'Grupo,Modulo,Grupo,Modulo,Modulo'
        $itens[0].Rotulo | Should -Be 'Sistema'
        $itens[1].Marcador | Should -BeNullOrEmpty
        $itens[3].Marcador | Should -Not -BeNullOrEmpty
        $itens[4].Icone | Should -Not -BeNullOrEmpty -Because 'módulo sem ícone conhecido usa o padrão'
        $itens[4].Motivo | Should -Be 'sem winget'
    }

    It 'linhas: cabeçalho por categoria, barra só com Valor numérico, selo por estado' {
        $alvos = @(
            [pscustomobject]@{ Id = 'a'; Nome = 'CPU'; Categoria = 'Desempenho'; Estado = 'NaoSeAplica'; Detalhe = '18%'; Nivel = 'Normal'; Valor = 18 }
            [pscustomobject]@{ Id = 'b'; Nome = 'Telemetria'; Categoria = 'Privacidade'; Estado = 'Aplicado'; Detalhe = 'x' }
            [pscustomobject]@{ Id = 'c'; Nome = 'Só nome' }
        )
        $linhas = InModuleScope Interface -Parameters @{ A = $alvos } { param($A) ConvertTo-LinhaAlvo -Alvos $A }
        ($linhas | ForEach-Object Tipo) -join ',' | Should -Be 'Categoria,Alvo,Categoria,Alvo,Categoria,Alvo'
        $linhas[1].TemValor | Should -BeTrue
        $linhas[1].Valor | Should -Be 18
        $linhas[3].TemValor | Should -BeFalse
        $linhas[3].Selo | Should -Be 'aplicado'
        $linhas[3].TemSelo | Should -BeTrue
        $linhas[5].Nivel | Should -Be 'Normal'
        $linhas[5].Alvo.Id | Should -Be 'c'
    }

    It 'busca filtra por nome, detalhe ou categoria, sem diferenciar maiúsculas' {
        $alvos = @(
            [pscustomobject]@{ Id = 'a'; Nome = 'CPU'; Categoria = 'Desempenho'; Detalhe = '18%' }
            [pscustomobject]@{ Id = 'b'; Nome = 'Disco C:'; Categoria = 'Discos'; Detalhe = '200 GB livres' }
        )
        InModuleScope Interface -Parameters @{ A = $alvos } {
            param($A)
            @((ConvertTo-LinhaAlvo -Alvos $A -Busca 'cpu') | Where-Object Tipo -eq 'Alvo').Id | Should -Be 'a'
            @((ConvertTo-LinhaAlvo -Alvos $A -Busca 'LIVRES') | Where-Object Tipo -eq 'Alvo').Id | Should -Be 'b'
            @((ConvertTo-LinhaAlvo -Alvos $A -Busca 'desempenho') | Where-Object Tipo -eq 'Alvo').Id | Should -Be 'a'
            (ConvertTo-LinhaAlvo -Alvos $A -Busca 'nada disso').Count | Should -Be 0
        }
    }

    It 'mensagem para módulo <Estado>' -ForEach @(
        @{ Estado = 'faltando'; Titulo = 'Módulo faltando' }
        @{ Estado = 'quebrado'; Titulo = 'Módulo com defeito' }
        @{ Estado = 'indisponivel'; Titulo = 'Indisponível nesta máquina' }
    ) {
        $m = [pscustomobject]@{ Estado = $Estado; Motivo = 'pasta modulos\x não encontrada' }
        $msg = InModuleScope Interface -Parameters @{ M = $m } { param($M) Get-MensagemModulo -Modulo $M }
        $msg.Titulo | Should -Be $Titulo
        $msg.Texto | Should -Match '^Pasta modulos\\x não encontrada\. O resto do Tamanduá continua'
    }

    It 'módulo ok não tem mensagem' {
        InModuleScope Interface { Get-MensagemModulo -Modulo ([pscustomobject]@{ Estado = 'ok'; Motivo = '' }) } | Should -BeNullOrEmpty
    }

    It 'texto da barra de status' {
        InModuleScope Interface {
            Get-TextoStatusPagina -Quantidade 1 -Escreve $false -Quando ([datetime]'2026-10-29 14:03:22') |
                Should -Be '1 item · atualizado às 14:03:22 · módulo só de leitura'
            Get-TextoStatusPagina -Quantidade 5 -Escreve $true -Quando ([datetime]'2026-10-29 14:03:22') |
                Should -Match '^5 itens .* nada é alterado sem confirmação$'
        }
    }
}

Describe 'Tarefas em segundo plano' {
    BeforeAll {
        function Wait-Tarefas {
            $limite = [DateTime]::UtcNow.AddSeconds(20)
            while ((InModuleScope Interface { $script:Tarefas.Count }) -gt 0 -and [DateTime]::UtcNow -lt $limite) {
                Start-Sleep -Milliseconds 50
                InModuleScope Interface { Update-TmdTarefa }
            }
        }
    }

    It 'entrega o resultado' {
        $r = @{}
        $ao = { param($saida, $erro) $r.Saida = $saida; $r.Erro = $erro }.GetNewClosure()
        InModuleScope Interface -Parameters @{ Ao = $ao } { param($Ao) [void](Start-TmdTarefa -Script { param($X) $X * 2 } -Parametros @{ X = 21 } -AoTerminar $Ao) }
        Wait-Tarefas
        $r.Saida | Should -Be 42
        $r.Erro | Should -BeNullOrEmpty
    }

    It 'entrega o erro sem derrubar nada' {
        $r = @{}
        $ao = { $r.Erro = $args[1] }.GetNewClosure()
        InModuleScope Interface -Parameters @{ Ao = $ao } { param($Ao) [void](Start-TmdTarefa -Script { throw 'falhou lá' } -AoTerminar $Ao) }
        Wait-Tarefas
        $r.Erro | Should -Be 'falhou lá'
    }

    It 'tarefa cancelada não entrega nada' {
        $r = @{ Chamou = $false }
        $ao = { $r.Chamou = $true }.GetNewClosure()
        InModuleScope Interface -Parameters @{ Ao = $ao } {
            param($Ao)
            $t = Start-TmdTarefa -Script { Start-Sleep -Seconds 30 } -AoTerminar $Ao
            Stop-TmdTarefa -Tarefa $t
        }
        Wait-Tarefas
        $r.Chamou | Should -BeFalse
    }

    It 'carrega os módulos do projeto real como dados simples' {
        $r = @{}
        $ao = { param($saida, $erro) $r.Saida = $saida; $r.Erro = $erro }.GetNewClosure()
        InModuleScope Interface -Parameters @{ Ao = $ao; Raiz = $script:RaizProjeto } {
            param($Ao, $Raiz)
            [void](Start-TmdTarefa -Script $script:ScriptCarregarModulos -AoTerminar $Ao `
                    -Parametros @{ Nucleo = (Join-Path $Raiz 'nucleo\Tamandua.Nucleo.psm1'); Raiz = $Raiz })
        }
        Wait-Tarefas
        $r.Erro | Should -BeNullOrEmpty
        $r.Saida.Count | Should -Be 12
        ($r.Saida | Where-Object Nome -eq 'status').Estado | Should -Be 'ok'
        ($r.Saida | Where-Object Nome -eq 'atualizacoes').Titulo | Should -Be 'Atualizações'
    }
}

Describe 'Janela de verdade' {
    It 'abre no projeto real, mostra os módulos e carrega o status' {
        $r = Invoke-InterfaceTeste -Raiz $script:RaizProjeto
        $r.Carregou | Should -BeTrue
        @($r.Modulos | Where-Object Tipo -eq 'Modulo').Count | Should -Be 13 -Because '12 do catálogo + a página Histórico'
        @($r.Modulos | Where-Object Tipo -eq 'Modulo')[-1].Nome | Should -Be 'historico'
        $r.Titulo | Should -Be 'Status'
        $r.Mensagem | Should -BeNullOrEmpty
        @($r.Linhas | Where-Object { $_.Tipo -eq 'Alvo' -and $_.Id -eq 'saude' }).Count | Should -Be 1
        $r.Status | Should -Match 'módulo só de leitura'
    }

    It 'sem nenhum módulo: abre e explica que o módulo está faltando' {
        $raiz = New-ProjetoFalso -Pai $TestDrive -ComInterface
        $r = Invoke-InterfaceTeste -Raiz $raiz -Tema 'escuro'
        $r.Carregou | Should -BeTrue
        $r.Mensagem | Should -Be 'Módulo faltando'
    }

    It 'módulo que devolve um item só ou nenhum: mostra sem erro' {
        $raiz = New-ProjetoFalso -Pai $TestDrive -Catalogo 'um' -ComInterface
        New-ModuloFalso -Raiz $raiz -Nome 'um' -Codigo @'
function Test-Requisitos { @{ Ok = $true } }
function Find-Alvos { [pscustomobject]@{ Id = 'so'; Nome = 'Único'; Categoria = 'C'; Estado = 'NaoSeAplica'; Detalhe = 'd' } }
'@ | Out-Null
        $r = Invoke-InterfaceTeste -Raiz $raiz
        $r.Status | Should -Not -Match 'Erro'
        @($r.Linhas | Where-Object Tipo -eq 'Alvo').Count | Should -Be 1

        $vazio = New-ProjetoFalso -Pai $TestDrive -Catalogo 'vazio' -ComInterface
        New-ModuloFalso -Raiz $vazio -Nome 'vazio' | Out-Null
        $r = Invoke-InterfaceTeste -Raiz $vazio
        $r.Status | Should -Not -Match 'Erro'
        $r.Mensagem | Should -Be 'Nada a fazer aqui'
    }

    It 'módulo que falha ao buscar: a janela continua de pé e mostra o erro' {
        $raiz = New-ProjetoFalso -Pai $TestDrive -Catalogo 'ruim' -ComInterface
        New-ModuloFalso -Raiz $raiz -Nome 'ruim' -Codigo @'
function Test-Requisitos { @{ Ok = $true } }
function Find-Alvos { throw 'disco sumiu' }
'@ | Out-Null
        $r = Invoke-InterfaceTeste -Raiz $raiz
        $r.Carregou | Should -BeTrue
        $r.Mensagem | Should -Be 'O módulo falhou'
        $r.Status | Should -Match 'disco sumiu'
    }
}

Describe 'Seleção e resultado (funções puras)' {
    It 'módulo que escreve: linhas com caixa, marcadas conforme o alvo' {
        $alvos = @(
            [pscustomobject]@{ Id = 'a'; Nome = 'Temp'; Categoria = 'T'; Estado = 'NaoSeAplica'; Detalhe = 'x'; Tamanho = 2048; Selecionado = $true }
            [pscustomobject]@{ Id = 'b'; Nome = 'Dumps'; Categoria = 'T'; Estado = 'NaoSeAplica'; Detalhe = 'y'; Tamanho = 0; Selecionado = $false }
        )
        InModuleScope Interface -Parameters @{ A = $alvos } {
            param($A)
            $linhas = ConvertTo-LinhaAlvo -Alvos $A -Escreve
            @($linhas | Where-Object Tipo -eq 'Alvo' | ForEach-Object TemCaixa) | Should -Be @($true, $true)
            ($linhas | Where-Object Id -eq 'a').Selecionado | Should -BeTrue
            ($linhas | Where-Object Id -eq 'b').Selecionado | Should -BeFalse
            $r = Get-ResumoSelecao -Linhas $linhas
            $r.Quantidade | Should -Be 1
            $r.Bytes | Should -Be 2048
            $r.Texto | Should -Match '^1 selecionado · 2[,.]0 KB$'
            $r.Alvos[0].Id | Should -Be 'a'
            ((ConvertTo-LinhaAlvo -Alvos $A) | Where-Object Tipo -eq 'Alvo' | ForEach-Object TemCaixa) | Should -Not -Contain $true -Because 'módulo de leitura não tem caixa'
        }
    }

    It 'texto do resultado: simulação, sucesso, parcial e erro' {
        InModuleScope Interface {
            $sim = Get-TextoResultado -Resultados @([pscustomobject]@{ Status = 'Simulado'; Liberado = 1048576; Motivo = '' }) -Simulado $true
            $sim.Texto | Should -Match '^Simulação: liberaria 1[,.]0 MB\. Nada foi alterado\.$'
            (Get-TextoResultado -Resultados @([pscustomobject]@{ Status = 'Feito'; Liberado = 1024; Motivo = '' }) -Simulado $false).Cor | Should -Be 'Sucesso'
            $parcial = Get-TextoResultado -Resultados @([pscustomobject]@{ Status = 'Parcial'; Liberado = 10; Motivo = '2 pulado(s)' }) -Simulado $false
            $parcial.Cor | Should -Be 'Aviso'
            $parcial.Texto | Should -Match '2 pulado'
            (Get-TextoResultado -Resultados @([pscustomobject]@{ Status = 'Erro'; Liberado = 0; Motivo = 'x' }) -Simulado $false).Cor | Should -Be 'Perigo'
        }
    }
}

Describe 'Histórico (funções puras)' {
    It 'só ajuste reversível ganha caixa; agrupa por dia; desfazer não diz que é irreversível' {
        $ops = @(
            [pscustomobject]@{ Data = '2026-10-29T14:03:00'; Modulo = 'ajustes'; Id = 'priv-x'; Acao = 'ajustar'; Caminho = 'Desativar X'; Status = 'Feito'; Liberado = 0; Motivo = ''; Simulado = $false; Reversivel = $true }
            [pscustomobject]@{ Data = '2026-10-28T09:00:00'; Modulo = 'limpar'; Id = 'temp-usuario'; Acao = 'remover'; Caminho = 'C:\Temp\a'; Status = 'Parcial'; Liberado = 2048; Motivo = '1 em uso'; Simulado = $false; Reversivel = $false }
        )
        InModuleScope Interface -Parameters @{ O = $ops } {
            param($O)
            $alvos = @(ConvertTo-AlvoHistorico -Operacoes $O)
            $alvos[0].Nome | Should -Be 'Ajuste: Desativar X'
            $alvos[0].Categoria | Should -Be '29/10/2026'
            $alvos[0].IdAjuste | Should -Be 'priv-x'
            $alvos[1].Nivel | Should -Be 'Atencao'
            $alvos[1].Detalhe | Should -Match 'Parcial · limpar · 2[,.]0 KB · 09:00 · 1 em uso'
            $linhas = ConvertTo-LinhaAlvo -Alvos $alvos -Escreve
            @($linhas | Where-Object { $_.Tipo -eq 'Alvo' } | ForEach-Object TemCaixa) | Should -Be @($true, $false)
            $alvos[0].Selecionado = $true
            $resumo = Get-ResumoSelecao -Linhas (ConvertTo-LinhaAlvo -Alvos $alvos -Escreve)
            $resumo.Quantidade | Should -Be 1
            $resumo.Irreversiveis | Should -Be 0
            (Get-TextoResultado -Resultados @([pscustomobject]@{ Status = 'Feito'; Liberado = 0 }) -Acao 'desfazer').Texto | Should -Match '^Desfeitos: 1'
        }
    }
}

Describe 'Presets (funções puras)' {
    It 'lista os presets na ordem em que aparecem, com Nenhum no fim, e marca só os do preset' {
        $alvos = @(
            [pscustomobject]@{ Id = 'a'; Presets = @('Essencial', 'Privacidade'); Selecionado = $false }
            [pscustomobject]@{ Id = 'b'; Presets = @('Privacidade'); Selecionado = $true }
            [pscustomobject]@{ Id = 'c'; Presets = @(); Selecionado = $true }
        )
        InModuleScope Interface -Parameters @{ A = $alvos } {
            param($A)
            (Get-PresetAlvo -Alvos $A) -join ',' | Should -Be 'Essencial,Privacidade,Nenhum'
            Set-SelecaoPreset -Alvos $A -Preset 'Essencial' | Should -Be 1
            ($A | ForEach-Object Selecionado) -join ',' | Should -Be 'True,False,False'
            Set-SelecaoPreset -Alvos $A -Preset 'Nenhum' | Should -Be 0
            (Get-PresetAlvo -Alvos @([pscustomobject]@{ Id = 'x' })).Count | Should -Be 0
            $t = Get-TextoResultado -Resultados @([pscustomobject]@{ Id = 'a'; Status = 'Feito'; Liberado = 0; Motivo = '' }) -Acao 'ajustar'
            $t.Texto | Should -Be 'Aplicados: 1 ajuste(s). Dá para desfazer pelo Histórico.'
            $t.Cor | Should -Be 'Sucesso'
        }
    }
}

Describe 'Selo e resultado de módulos que não se desfazem pelo Histórico' {
    It 'selo próprio do módulo substitui o padrão; resultado sem "desfazer"' {
        $alvos = @([pscustomobject]@{ Id = 'vlc'; Nome = 'VLC'; Categoria = 'M'; Estado = 'Parcial'; Selo = 'atualizar para 3.1'; Detalhe = '' })
        InModuleScope Interface -Parameters @{ A = $alvos } {
            param($A)
            ((ConvertTo-LinhaAlvo -Alvos $A -Escreve) | Where-Object Tipo -eq 'Alvo').Selo | Should -Be 'atualizar para 3.1'
            $t = Get-TextoResultado -Resultados @([pscustomobject]@{ Id = 'vlc'; Status = 'Feito'; Liberado = 0 }) -Acao 'ajustar' -DaParaDesfazer $false
            $t.Texto | Should -Be 'Concluídos: 1 item(ns).'
        }
    }
}

Describe 'Ajustes pela janela de verdade' {
    It 'preset Essencial, confirmação dizendo que dá para desfazer, aplica e a página mostra "aplicado"' {
        $env:TAMANDUA_DADOS = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
        $raizReg = "HKCU:\Software\TamanduaTestes\janela-ajustes-$([guid]::NewGuid().ToString('N'))"
        $projeto = New-ProjetoFalso -Pai $TestDrive -Catalogo 'ajustes' -ComInterface -ModulosReais 'ajustes'
        $env:TAMANDUA_REGISTRO_TESTE = $raizReg
        $passos = @{ Etapa = 0 }
        try {
            $aoCarregar = {
                $tela = $args[0]
                $p = $passos
                $relogio = New-Object System.Windows.Threading.DispatcherTimer
                $relogio.Interval = [TimeSpan]::FromMilliseconds(200)
                $clicar = { param($b) $b.RaiseEvent((New-Object System.Windows.RoutedEventArgs([System.Windows.Controls.Primitives.ButtonBase]::ClickEvent))) }
                $relogio.Add_Tick({
                        $c = $tela.Controles
                        if ($c.BarraTarefa.Visibility -eq 'Visible') { return }
                        switch ($p.Etapa) {
                            0 {
                                $p.Presets = @($c.ListaPresets.ItemsSource) -join ','
                                $p.PresetsVisivel = [string]$c.PainelPresets.Visibility
                                $recipiente = $c.ListaPresets.ItemContainerGenerator.ContainerFromIndex(0)
                                & $clicar ([System.Windows.Media.VisualTreeHelper]::GetChild($recipiente, 0))
                            }
                            1 {
                                $p.Marcados = $c.TextoStatus.Text
                                # Marca mais um item clicando na caixa de verdade (fora do preset).
                                $linha = @($c.ListaAlvos.ItemsSource | Where-Object { $_.Id -eq 'priv-bing-iniciar' })[0]
                                $fila = [System.Collections.Generic.Queue[object]]::new()
                                $fila.Enqueue($c.ListaAlvos.ItemContainerGenerator.ContainerFromItem($linha))
                                $caixa = $null
                                while ($fila.Count -gt 0 -and -not $caixa) {
                                    $no = $fila.Dequeue()
                                    if ($no -is [System.Windows.Controls.CheckBox]) { $caixa = $no; break }
                                    for ($k = 0; $k -lt [System.Windows.Media.VisualTreeHelper]::GetChildrenCount($no); $k++) {
                                        $fila.Enqueue([System.Windows.Media.VisualTreeHelper]::GetChild($no, $k))
                                    }
                                }
                                $caixa.IsChecked = $true
                                & $clicar $caixa
                            }
                            2 { $p.MaisUm = $c.TextoStatus.Text; & $clicar $c.BotaoAplicar }
                            3 { $p.Confirmacao = $c.TextoStatus.Text; & $clicar $c.BotaoAplicar }
                            4 {
                                $p.Final = $c.TextoStatus.Text
                                $p.Aplicados = @($c.ListaAlvos.ItemsSource | Where-Object { $_.Estado -eq 'Aplicado' }).Count
                                $relogio.Stop()
                                $tela.Janela.Close()
                            }
                        }
                        $p.Etapa++
                    }.GetNewClosure())
                $relogio.Start()
            }.GetNewClosure()
            Start-TmdInterface -Raiz $projeto -Tema 'escuro' -AoCarregar $aoCarregar -FecharAposSeg 60
        }
        finally {
            Remove-Item Env:\TAMANDUA_REGISTRO_TESTE -ErrorAction SilentlyContinue
            if (Test-Path -LiteralPath $raizReg) { Remove-Item -LiteralPath $raizReg -Recurse -Force }
            $mae = 'HKCU:\Software\TamanduaTestes'
            if ((Test-Path -LiteralPath $mae) -and @(Get-ChildItem -LiteralPath $mae).Count -eq 0) { Remove-Item -LiteralPath $mae -Force }
        }
        $passos.Etapa | Should -Be 5
        $passos.PresetsVisivel | Should -Be 'Visible'
        $passos.Presets | Should -Be 'Essencial,Privacidade,Explorador,Nenhum'
        $passos.Marcados | Should -Match '^Preset Essencial: 6 marcado'
        $passos.MaisUm | Should -Match '^7 selecionados'
        $passos.Confirmacao | Should -Match '^Aplicar: 7 itens\. Dá para desfazer pelo Histórico\. Confirmar\?$'
        $passos.Final | Should -Match '^Aplicados: 7 ajuste'
        $passos.Aplicados | Should -Be 7
    }
}

Describe 'Navegação por pastas na janela' {
    It 'duplo clique abre a pasta do item, o subtítulo mostra o caminho e Atualizar continua nela' {
        $projeto = New-ProjetoFalso -Pai $TestDrive -Catalogo 'nav' -ComInterface
        # Módulo falso que "navega": devolve um item que abre a pasta X, e mostra a pasta recebida.
        New-ModuloFalso -Raiz $projeto -Nome 'nav' -Codigo @'
function Test-Requisitos { @{ Ok = $true } }
function Find-Alvos {
    param([string]$Caminho)
    if (-not $Caminho) {
        return [pscustomobject]@{ Id = 'ir'; Nome = 'Abrir X'; Categoria = 'Início'; Estado = 'NaoSeAplica'; Detalhe = ''; Caminho = 'C:\X'; Navegavel = $true }
    }
    [pscustomobject]@{ Id = 'dentro'; Nome = "Dentro de $Caminho"; Categoria = 'Pasta'; Estado = 'NaoSeAplica'; Detalhe = ''; Caminho = ''; Navegavel = $false }
}
'@ | Out-Null
        $passos = @{ Etapa = 0 }
        $aoCarregar = {
            $tela = $args[0]
            $p = $passos
            $relogio = New-Object System.Windows.Threading.DispatcherTimer
            $relogio.Interval = [TimeSpan]::FromMilliseconds(200)
            $relogio.Add_Tick({
                    $c = $tela.Controles
                    if ($c.BarraTarefa.Visibility -eq 'Visible') { return }
                    switch ($p.Etapa) {
                        0 {
                            $c.ListaAlvos.SelectedItem = @($c.ListaAlvos.ItemsSource | Where-Object { $_.Id -eq 'ir' })[0]
                            $duplo = New-Object System.Windows.Input.MouseButtonEventArgs([System.Windows.Input.Mouse]::PrimaryDevice, 0, [System.Windows.Input.MouseButton]::Left)
                            $duplo.RoutedEvent = [System.Windows.Controls.Control]::MouseDoubleClickEvent
                            $c.ListaAlvos.RaiseEvent($duplo)
                        }
                        1 {
                            $p.Subtitulo = $c.SubtituloPagina.Text
                            $p.Dentro = @($c.ListaAlvos.ItemsSource | Where-Object { $_.Tipo -eq 'Alvo' })[0].Nome
                            $c.BotaoAtualizar.RaiseEvent((New-Object System.Windows.RoutedEventArgs([System.Windows.Controls.Primitives.ButtonBase]::ClickEvent)))
                        }
                        2 {
                            $p.DepoisDeAtualizar = @($c.ListaAlvos.ItemsSource | Where-Object { $_.Tipo -eq 'Alvo' })[0].Nome
                            $relogio.Stop()
                            $tela.Janela.Close()
                        }
                    }
                    $p.Etapa++
                }.GetNewClosure())
            $relogio.Start()
        }.GetNewClosure()
        Start-TmdInterface -Raiz $projeto -Tema 'claro' -AoCarregar $aoCarregar -FecharAposSeg 60
        $passos.Etapa | Should -Be 3
        $passos.Subtitulo | Should -Match 'C:\\X$'
        $passos.Dentro | Should -Be 'Dentro de C:\X'
        $passos.DepoisDeAtualizar | Should -Be 'Dentro de C:\X'
    }
}

Describe 'Desfazer pela página Histórico' {
    It 'mostra o ajuste aplicado, desfaz com confirmação e o registro volta ao que era' {
        $env:TAMANDUA_DADOS = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
        $chave = "HKCU:\Software\TamanduaTestes\janela-$([guid]::NewGuid().ToString('N'))"
        Import-Module (Join-Path $script:RaizProjeto 'nucleo\Tamandua.Nucleo.psm1') -Force -DisableNameChecking -Global
        $ajuste = [pscustomobject]@{ id = 'janela-teste'; nome = 'Ajuste da janela'; requerAdmin = $false
            mudancas = @([pscustomobject]@{ tipo = 'Registro'; caminho = $chave; nome = 'Valor'; valor = 1; tipoValor = 'DWord' }) }
        (Set-TmdAjuste -Ajuste $ajuste).Status | Should -Be 'Feito'
        $projeto = New-ProjetoFalso -Pai $TestDrive -ComInterface
        $passos = @{ Etapa = 0 }
        try {
            $aoCarregar = {
                $tela = $args[0]
                $p = $passos
                $relogio = New-Object System.Windows.Threading.DispatcherTimer
                $relogio.Interval = [TimeSpan]::FromMilliseconds(200)
                $clicar = { param($b) $b.RaiseEvent((New-Object System.Windows.RoutedEventArgs([System.Windows.Controls.Primitives.ButtonBase]::ClickEvent))) }
                $relogio.Add_Tick({
                        $c = $tela.Controles
                        if ($c.BarraTarefa.Visibility -eq 'Visible') { return }
                        switch ($p.Etapa) {
                            0 { $c.ListaModulos.SelectedItem = @($c.ListaModulos.ItemsSource | Where-Object { $_.Nome -eq 'historico' })[0] }
                            1 {
                                $linha = @($c.ListaAlvos.ItemsSource | Where-Object { $_.TemCaixa })[0]
                                $p.Linha = $linha.Nome
                                $linha.Alvo.Selecionado = $true
                                & $clicar $c.BotaoAplicar
                            }
                            2 { $p.Confirmacao = $c.TextoStatus.Text; & $clicar $c.BotaoAplicar }
                            3 { $p.Final = $c.TextoStatus.Text; $relogio.Stop(); $tela.Janela.Close() }
                        }
                        $p.Etapa++
                    }.GetNewClosure())
                $relogio.Start()
            }.GetNewClosure()
            Start-TmdInterface -Raiz $projeto -Tema 'claro' -AoCarregar $aoCarregar -FecharAposSeg 60
        }
        finally {
            if (Test-Path -LiteralPath $chave) { Remove-Item -LiteralPath $chave -Recurse -Force }
        }
        $passos.Etapa | Should -Be 4
        $passos.Linha | Should -Be 'Ajuste: Ajuste da janela'
        $passos.Confirmacao | Should -Match '^Desfazer: 1 item\. Confirmar\?$'
        $passos.Final | Should -Match '^Desfeitos: 1'
        Test-TmdAjusteReversivel -Id 'janela-teste' | Should -BeFalse
    }
}

Describe 'Limpar pela janela de verdade' {
    It 'Simular não apaga; Limpar pede confirmação; Confirmar apaga o velho e mantém o recente' {
        $base = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
        $temp = New-ArvoreFalsa -Pasta (Join-Path $base 'Temp') -Arquivos @{ 'velho.tmp' = 'aaaa'; 'recente.tmp' = 'b' }
        New-ArvoreFalsa -Pasta (Join-Path $base 'Local\CrashDumps') -Arquivos @{ 'x.dmp' = 'cc' } | Out-Null
        Set-Idade "$temp\velho.tmp" 48
        $projeto = New-ProjetoFalso -Pai $TestDrive -Catalogo 'limpar' -ComInterface -ModulosReais 'limpar'

        # As tarefas da janela rodam neste processo e leem TEMP/LOCALAPPDATA daqui: aponta para a sandbox durante o teste.
        $originais = @{ TEMP = $env:TEMP; TMP = $env:TMP; LOCALAPPDATA = $env:LOCALAPPDATA }
        $env:TEMP = $temp; $env:TMP = $temp; $env:LOCALAPPDATA = Join-Path $base 'Local'
        $passos = @{ Etapa = 0 }
        try {
            $aoCarregar = {
                # GetNewClosure só captura variáveis locais: copia para locais o que o relógio vai usar.
                $tela = $args[0]
                $p = $passos
                $pastaTemp = $temp
                $relogio = New-Object System.Windows.Threading.DispatcherTimer
                $relogio.Interval = [TimeSpan]::FromMilliseconds(200)
                $clicar = { param($b) $b.RaiseEvent((New-Object System.Windows.RoutedEventArgs([System.Windows.Controls.Primitives.ButtonBase]::ClickEvent))) }
                $relogio.Add_Tick({
                        $c = $tela.Controles
                        if ($c.BarraTarefa.Visibility -eq 'Visible') { return }
                        switch ($p.Etapa) {
                            0 { & $clicar $c.BotaoSimular }
                            1 { $p.Simulacao = $c.TextoStatus.Text; $p.VelhoDepoisDeSimular = Test-Path "$pastaTemp\velho.tmp"; & $clicar $c.BotaoAplicar }
                            2 { $p.Confirmacao = $c.TextoStatus.Text; $p.RotuloConfirmar = $c.BotaoAplicar.Content; & $clicar $c.BotaoAplicar }
                            3 { $p.Final = $c.TextoStatus.Text; $relogio.Stop(); $tela.Janela.Close() }
                        }
                        $p.Etapa++
                    }.GetNewClosure())
                $relogio.Start()
            }.GetNewClosure()
            Start-TmdInterface -Raiz $projeto -Tema 'claro' -AoCarregar $aoCarregar -FecharAposSeg 60
        }
        finally {
            $env:TEMP = $originais.TEMP; $env:TMP = $originais.TMP; $env:LOCALAPPDATA = $originais.LOCALAPPDATA
        }

        $passos.Etapa | Should -Be 4 -Because 'a sequência inteira precisa ter rodado'
        $passos.Simulacao | Should -Match 'Simulação: liberaria'
        $passos.VelhoDepoisDeSimular | Should -BeTrue
        $passos.RotuloConfirmar | Should -Be 'Confirmar'
        $passos.Confirmacao | Should -Match 'Limpar: 2 itens .* Confirmar\?'
        $passos.Final | Should -Match '^Liberado'
        Test-Path "$temp\velho.tmp" | Should -BeFalse
        Test-Path "$temp\recente.tmp" | Should -BeTrue
        Test-Path (Join-Path $base 'Local\CrashDumps\x.dmp') | Should -BeFalse
    }
}
