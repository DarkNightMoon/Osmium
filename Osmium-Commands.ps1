# OSMIUM command dispatcher and on-demand system information.
. (Join-Path $PSScriptRoot "Osmium-Fetch.ps1")
. (Join-Path $PSScriptRoot "Osmium-AI.ps1")
. (Join-Path $PSScriptRoot "Osmium-AI-Server.ps1")
. (Join-Path $PSScriptRoot "Osmium-Updater.ps1")
function global:prompt {
    $path = (Get-Location).Path
    $p = "$([char]27)[38;2;190;140;255m"
    $r = "$([char]27)[0m"
    Write-Host ("OSMIUM " + $path + " > ") -NoNewline -ForegroundColor Magenta
    return " "
}

function Get-OsmiumSystemSnapshot {
    $cpu = "N/A"; $ramUsed = 0.0; $ramTotal = 0.0
    $gpu = "N/A"; $gpuTemp = "N/A"; $vramUsed = "N/A"; $vramTotal = "N/A"
    try {
        $c = Get-CimInstance Win32_PerfFormattedData_PerfOS_Processor -Filter "Name='_Total'"
        if ($null -ne $c.PercentProcessorTime) { $cpu = [int]$c.PercentProcessorTime }
    } catch {}
    try {
        $os = Get-CimInstance Win32_OperatingSystem
        $ramUsed = [math]::Round(($os.TotalVisibleMemorySize - $os.FreePhysicalMemory)/1MB,1)
        $ramTotal = [math]::Round($os.TotalVisibleMemorySize/1MB,1)
    } catch {}
    try {
        $nvsmi = Get-Command nvidia-smi.exe -ErrorAction Stop
        $g = & $nvsmi.Source --query-gpu=utilization.gpu,temperature.gpu,memory.used,memory.total --format=csv,noheader,nounits 2>$null | Select-Object -First 1
        $a = $g -split ',\s*'
        if ($a.Count -ge 4) {
            $gpu = [int]$a[0]; $gpuTemp = [int]$a[1]
            $vramUsed = [int]$a[2]; $vramTotal = [int]$a[3]
        }
    } catch {}
    $netDown = 0.0; $netUp = 0.0
    try {
        $names = @(Get-NetAdapter | Where-Object Status -eq "Up" | Select-Object -ExpandProperty Name)
        if ($names.Count) {
            $stats = Get-NetAdapterStatistics -Name $names
            $rx = [double](($stats | Measure-Object ReceivedBytes -Sum).Sum)
            $tx = [double](($stats | Measure-Object SentBytes -Sum).Sum)
            if ($script:OsmiumNetPrevious) {
                $netDown = [math]::Max(0,($rx-$script:OsmiumNetPrevious.Rx))
                $netUp = [math]::Max(0,($tx-$script:OsmiumNetPrevious.Tx))
            }
            $script:OsmiumNetPrevious = [pscustomobject]@{Rx=$rx;Tx=$tx}
        }
    } catch {}
    [pscustomobject]@{
        CPU=$cpu; RAMUsed=$ramUsed; RAMTotal=$ramTotal
        GPU=$gpu; GPUTemp=$gpuTemp; VRAMUsed=$vramUsed; VRAMTotal=$vramTotal
        DownKB=[math]::Round($netDown/1KB,1); UpKB=[math]::Round($netUp/1KB,1)
    }
}

function Show-OsmiumSystem {
    $script:OsmiumNetPrevious = $null
    $esc = [char]27
    $purple = "$esc[38;2;190;140;255m"; $white = "$esc[38;2;255;255;255m"
    $green = "$esc[38;2;100;230;160m"; $reset = "$esc[0m"
    $last = [datetime]::MinValue
    while ($true) {
        $m = Get-OsmiumSystemSnapshot
        Clear-Host
        Write-Host ($purple + "╔══════════════════════════════════════════════════════════════╗" + $reset)
        Write-Host ($purple + "║" + $white + "                 OSMIUM // LIVE SYSTEM MONITOR                " + $purple + "║" + $reset)
        Write-Host ($purple + "╚══════════════════════════════════════════════════════════════╝" + $reset)
        Write-Host ""
        Write-Host (" UPDATED  {0}" -f (Get-Date -Format "yyyy-MM-dd HH:mm:ss")) -ForegroundColor DarkGray
        Write-Host ""
        Write-Host (" CPU       {0,3}%" -f $m.CPU) -ForegroundColor White
        Write-Host (" GPU       {0,3}%" -f $m.GPU) -ForegroundColor White
        Write-Host (" GPU TEMP  {0,3} C" -f $m.GPUTemp) -ForegroundColor White
        Write-Host (" VRAM      {0} / {1} MB" -f $m.VRAMUsed,$m.VRAMTotal) -ForegroundColor White
        Write-Host (" RAM       {0:N1} / {1:N1} GB" -f $m.RAMUsed,$m.RAMTotal) -ForegroundColor White
        Write-Host ""
        Write-Host " NETWORK" -ForegroundColor Magenta
        if ($last -eq [datetime]::MinValue) {
            Write-Host " DOWNLOAD  sampling..." -ForegroundColor White
            Write-Host " UPLOAD    sampling..." -ForegroundColor White
        } else {
            Write-Host (" DOWNLOAD  {0:N1} KB/s" -f $m.DownKB) -ForegroundColor White
            Write-Host (" UPLOAD    {0:N1} KB/s" -f $m.UpKB) -ForegroundColor White
        }
        Write-Host ""
        Write-Host " PATH" -ForegroundColor Magenta
        Write-Host (" " + (Get-Location).Path) -ForegroundColor White
        Write-Host ""
        Write-Host " Ctrl+C  Exit monitor and return to OSMIUM prompt" -ForegroundColor Magenta
        $last = Get-Date
        Start-Sleep -Seconds 1
    }
}



function global:osmium {
    param([Parameter(ValueFromRemainingArguments=$true)][string[]]$Arguments)
    $arg = if ($Arguments.Count) { $Arguments[0].ToLowerInvariant() } else { "-h" }
    switch ($arg) {
        "-h" {
            Write-Host ""
            Write-Host " OSMIUM // COMMAND INDEX" -ForegroundColor Magenta
            Write-Host " ----------------------------------------" -ForegroundColor DarkMagenta
            Write-Host " osmium -h       Display this help menu" -ForegroundColor White
            Write-Host " osmium -sys     Open live system monitor" -ForegroundColor White
            Write-Host " osmium -update  Update OSMIUM from GitHub" -ForegroundColor White
            Write-Host " osmium -fetch   Display system information" -ForegroundColor White
            Write-Host " osmium -ai      Ask local OSMIUM AI" -ForegroundColor White
            Write-Host " osmium -ai-status Check local AI connection" -ForegroundColor White
            Write-Host " osmium -ai-start  Start local AI server" -ForegroundColor White
            Write-Host " osmium -ai-stop   Stop local AI server" -ForegroundColor White
            Write-Host " exit            Close the PowerShell session" -ForegroundColor White
            Write-Host ""
            Write-Host " More commands will be added here." -ForegroundColor DarkGray
        }
        "-help" {
            osmium -h
        }
        "-sys" {
            try { Show-OsmiumSystem }
            catch [System.Management.Automation.PipelineStoppedException] {}
            catch { Write-Host $_ -ForegroundColor Red }
            finally { Write-Host "`nOSMIUM monitor stopped." -ForegroundColor Magenta }
        }
        "-fetch" {
            Show-OsmiumFetch
        }
        "-ai" {
            $request = if ($Arguments.Count -gt 1) { ($Arguments | Select-Object -Skip 1) -join " " } else { Read-Host "Enter your question" }
            if ([string]::IsNullOrWhiteSpace($request)) {
                Write-Host "AI request cannot be empty." -ForegroundColor Yellow
            } else {
                Invoke-OsmiumAI -Request $request
            }
        }
        "-ai-status" {
            Test-OsmiumAIConnection
        }
        "-ai-start" {
            Start-OsmiumAIServer
        }
        "-ai-stop" {
            Stop-OsmiumAIServer
        }
        "-update" {
            Invoke-OsmiumUpdate
        }
        default {
            Write-Host "Unknown OSMIUM command: $arg" -ForegroundColor Red
            Write-Host "Type 'osmium -h' to see available commands." -ForegroundColor DarkGray
        }
    }
}







