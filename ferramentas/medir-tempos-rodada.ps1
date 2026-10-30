# Uma rodada do medir-tempos.ps1: abre a janela, passa por cada módulo e grava as medidas (ms) em -Arquivo.
# -Esperar: antes de clicar, espera a leitura antecipada (segundo plano) terminar, como alguém que olha o Status
# por alguns segundos; grava quanto ela levou em "antecipar tudo".
param([Parameter(Mandatory)][string]$Raiz, [Parameter(Mandatory)][string]$Arquivo, [switch]$Esperar)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$inicio = (Get-Process -Id $PID).StartTime
Import-Module (Join-Path $Raiz 'interface\Interface.psm1') -Force -DisableNameChecking
$medidas = [ordered]@{}
$destino = $Arquivo
$esperarAntes = [bool]$Esperar
$interface = Get-Module Interface

$ao = {
    $tela = $args[0]
    $medidas['abrir'] = [int]((Get-Date) - $inicio).TotalMilliseconds
    $itens = @($tela.Controles.ListaModulos.ItemsSource | Where-Object { $_.Tipo -eq 'Modulo' -and $_.Estado -eq 'ok' })
    $fila = [System.Collections.Generic.Queue[object]]::new()
    foreach ($m in $itens | Where-Object Nome -ne 'status') { $fila.Enqueue(@{ Rotulo = $m.Nome; Item = $m }) }
    $fila.Enqueue(@{ Rotulo = 'status'; Item = @($itens | Where-Object Nome -eq 'status')[0] })
    foreach ($i in 1..2) { $fila.Enqueue(@{ Rotulo = 'status (atualizar)'; Atualizar = $true }) }
    # Segunda passada: volta em cada página (já lida antes).
    foreach ($m in $itens | Where-Object Nome -ne 'status') { $fila.Enqueue(@{ Rotulo = "$($m.Nome) (de volta)"; Item = $m }) }
    $estado = @{ Atual = $null; Relogio = $null; Esperando = $false; Antecipacao = [Diagnostics.Stopwatch]::StartNew(); EsperarAntes = $esperarAntes }
    $tique = New-Object Windows.Threading.DispatcherTimer
    $tique.Interval = [TimeSpan]::FromMilliseconds(20)
    $tique.Add_Tick({
            if ($estado.EsperarAntes) {
                $falta = & $interface { $null -ne $script:Estado.Antecipando -or ($script:Estado.Fila -and $script:Estado.Fila.Count -gt 0) }
                if ($falta) { return }
                $medidas['antecipar tudo'] = [int]$estado.Antecipacao.Elapsed.TotalMilliseconds
                $estado.EsperarAntes = $false
            }
            $ocupado = $tela.Controles.BarraTarefa.Visibility -eq 'Visible'
            if ($estado.Esperando) {
                if ($ocupado) { return }
                $ms = [int]$estado.Relogio.Elapsed.TotalMilliseconds
                $rotulo = $estado.Atual.Rotulo
                if ($medidas.Contains($rotulo)) { $medidas[$rotulo] = [int](($medidas[$rotulo] + $ms) / 2) } else { $medidas[$rotulo] = $ms }
                $estado.Esperando = $false
            }
            if ($ocupado) { return }
            if ($fila.Count -eq 0) {
                $tique.Stop()
                [IO.File]::WriteAllText($destino, ($medidas | ConvertTo-Json))
                $tela.Janela.Close()
                return
            }
            $estado.Atual = $fila.Dequeue()
            $estado.Relogio = [Diagnostics.Stopwatch]::StartNew()
            $estado.Esperando = $true
            if ($estado.Atual['Atualizar']) {
                $tela.Controles.BotaoAtualizar.RaiseEvent((New-Object Windows.RoutedEventArgs ([Windows.Controls.Primitives.ButtonBase]::ClickEvent)))
            }
            else { $tela.Controles.ListaModulos.SelectedItem = $estado.Atual.Item }
        }.GetNewClosure())
    $tique.Start()
}.GetNewClosure()

Start-TmdInterface -Raiz $Raiz -Tema claro -AoCarregar $ao -FecharAposSeg 300
