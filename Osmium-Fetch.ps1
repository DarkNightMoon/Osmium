# OSMIUM // SYSTEM FETCH
# Standalone system summary. No external modules required.

function Show-OsmiumFetch {
    $purple = "Magenta"
    $muted  = "DarkGray"
    $white  = "White"

    $os = $null
    $cpu = "Unavailable"
    $gpu = "Unavailable"
    $ramTotal = 0.0
    $ramFree = 0.0
    $hostName = $env:COMPUTERNAME
    $userName = $env:USERNAME
    $uptime = "Unavailable"
    $localIP = "Unavailable"
    $psVersion = $PSVersionTable.PSVersion.ToString()
    $architecture = if ([Environment]::Is64BitOperatingSystem) { "x64" } else { "x86" }

    try {
        $os = Get-CimInstance Win32_OperatingSystem -ErrorAction Stop
        $osName = $os.Caption
        $osVersion = "$($os.Version) (Build $($os.BuildNumber))"
        $ramTotal = [math]::Round($os.TotalVisibleMemorySize / 1MB, 1)
        $ramFree = [math]::Round($os.FreePhysicalMemory / 1MB, 1)
        $boot = $os.LastBootUpTime
        $uptimeSpan = (Get-Date) - $boot
        $uptime = "{0}d {1}h {2}m" -f [int]$uptimeSpan.TotalDays, $uptimeSpan.Hours, $uptimeSpan.Minutes
    } catch {
        $osName = "Windows"
        $osVersion = "Unavailable"
    }

    try {
        $cpu = (Get-CimInstance Win32_Processor -ErrorAction Stop | Select-Object -First 1 -ExpandProperty Name).Trim()
    } catch {}

    try {
        $gpuNames = Get-CimInstance Win32_VideoController -ErrorAction Stop |
            Where-Object { $_.Name -and $_.Name -notmatch "Microsoft Basic Display" } |
            Select-Object -ExpandProperty Name -Unique
        if ($gpuNames) { $gpu = $gpuNames -join " / " }
    } catch {}

    try {
        $ip = Get-NetIPAddress -AddressFamily IPv4 -ErrorAction Stop |
            Where-Object {
                $_.IPAddress -notlike "169.254*" -and
                $_.IPAddress -ne "127.0.0.1" -and
                $_.InterfaceOperationalStatus -eq "Up"
            } |
            Select-Object -First 1 -ExpandProperty IPAddress
        if ($ip) { $localIP = $ip }
    } catch {}

    $ramUsed = [math]::Max(0, [math]::Round($ramTotal - $ramFree, 1))
    $ramPercent = if ($ramTotal -gt 0) { [math]::Round(($ramUsed / $ramTotal) * 100) } else { 0 }

    $drives = @()
    try {
        $drives = Get-CimInstance Win32_LogicalDisk -Filter "DriveType=3" -ErrorAction Stop |
            ForEach-Object {
                $size = [double]$_.Size
                $free = [double]$_.FreeSpace
                if ($size -gt 0) {
                    [pscustomobject]@{
                        Name = $_.DeviceID
                        Used = [math]::Round(($size - $free) / 1GB, 1)
                        Total = [math]::Round($size / 1GB, 1)
                        Percent = [math]::Round((($size - $free) / $size) * 100)
                    }
                }
            }
    } catch {}

    $left = @(
        " ██████╗ ███████╗███╗   ███╗██╗██╗   ██╗███╗   ███╗"
        "██╔═══██╗██╔════╝████╗ ████║██║██║   ██║████╗ ████║"
        "██║   ██║███████╗██╔████╔██║██║██║   ██║██╔████╔██║"
        "██║   ██║╚════██║██║╚██╔╝██║██║╚██╗ ██╔╝██║╚██╔╝██║"
        "╚██████╔╝███████║██║ ╚═╝ ██║██║ ╚████╔╝ ██║ ╚═╝ ██║"
        " ╚═════╝ ╚══════╝╚═╝     ╚═╝╚═╝  ╚═══╝  ╚═╝     ╚═╝"
    )

    Clear-Host
    Write-Host ""
    Write-Host "  OSMIUM // SYSTEM FETCH" -ForegroundColor $purple
    Write-Host "  ------------------------------------------------------------" -ForegroundColor DarkMagenta

    for ($i = 0; $i -lt $left.Count; $i++) {
        Write-Host ("  " + $left[$i]) -ForegroundColor $purple -NoNewline
        switch ($i) {
            0 { $label = "SYSTEM"; $value = $hostName }
            1 { $label = "OS"; $value = $osName }
            2 { $label = "KERNEL"; $value = $osVersion }
            3 { $label = "CPU"; $value = $cpu }
            4 { $label = "GPU"; $value = $gpu }
            5 { $label = "USER"; $value = $userName }
        }
        Write-Host ("    " + $label.PadRight(9) + " " + $value) -ForegroundColor $white
    }

    Write-Host ""
    Write-Host "  HARDWARE" -ForegroundColor $purple
    Write-Host ("  RAM       {0} / {1} GB ({2}% used)" -f $ramUsed, $ramTotal, $ramPercent) -ForegroundColor $white

    foreach ($drive in $drives) {
        Write-Host ("  {0,-9} {1} / {2} GB ({3}% used)" -f ("DISK " + $drive.Name), $drive.Used, $drive.Total, $drive.Percent) -ForegroundColor $white
    }

    Write-Host ""
    Write-Host "  SESSION" -ForegroundColor $purple
    Write-Host ("  UPTIME    " + $uptime) -ForegroundColor $white
    Write-Host ("  NETWORK   " + $localIP) -ForegroundColor $white
    Write-Host ("  SHELL     PowerShell " + $psVersion + " / " + $architecture) -ForegroundColor $white
    Write-Host ""
    Write-Host "  OSMIUM CORE // ONLINE" -ForegroundColor $purple
    Write-Host "  ------------------------------------------------------------" -ForegroundColor DarkMagenta
}
