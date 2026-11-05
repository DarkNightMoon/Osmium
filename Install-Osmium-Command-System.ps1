$ErrorActionPreference = "Stop"
$root = Join-Path $env:LOCALAPPDATA "OsmiumTerminal"
New-Item -ItemType Directory -Force -Path $root | Out-Null
Copy-Item "$PSScriptRoot\Osmium-Banner.ps1" "$root\Osmium-Banner.ps1" -Force
Copy-Item "$PSScriptRoot\Osmium-Commands.ps1" "$root\Osmium-Commands.ps1" -Force

$docs = [Environment]::GetFolderPath("MyDocuments")
$profilePath = Join-Path $docs "WindowsPowerShell\Microsoft.PowerShell_profile.ps1"
New-Item -ItemType Directory -Force -Path (Split-Path $profilePath) | Out-Null
$old = if (Test-Path $profilePath) { Get-Content -LiteralPath $profilePath -Raw } else { "" }

# Remove previous OSMIUM profile hooks while retaining unrelated user profile content.
$old = [regex]::Replace($old, '(?im)^.*OSMIUM.*(?:START|AUTO|LIVE).*$', '')
$old = [regex]::Replace($old, '(?im)^.*Osmium-(?:Banner|Monitor|LiveShell|Commands)\.ps1.*$', '')
$old = [regex]::Replace($old, '(?im)^.*Start-OsmiumShell.*$', '')
$old = [regex]::Replace($old, '(?im)^.*Show-OsmiumSystem.*$', '')
$hook = @"
# OSMIUM STARTUP
. "$root\Osmium-Commands.ps1"
& "$root\Osmium-Banner.ps1"
"@
Set-Content -LiteralPath $profilePath -Value ($old.TrimEnd() + "`r`n" + $hook + "`r`n") -Encoding UTF8

Write-Host "OSMIUM command system installed." -ForegroundColor Green
Write-Host "Restart PowerShell. Use 'osmium -h' or 'osmium -sys'." -ForegroundColor Cyan
