$ErrorActionPreference = "Stop"
$project = $PSScriptRoot
$commandsFile = Join-Path $project "Osmium-Commands.ps1"
$installerFile = Join-Path $project "Install-Osmium-Command-System.ps1"
$updaterFile = Join-Path $project "Osmium-Updater.ps1"
foreach ($file in @($commandsFile,$installerFile,$updaterFile)) { if (-not (Test-Path -LiteralPath $file -PathType Leaf)) { throw "Required project file missing: $file" } }
$updaterSource = [IO.File]::ReadAllText($updaterFile)
$updaterTokens = $null; $updaterErrors = $null
$updaterAst = [System.Management.Automation.Language.Parser]::ParseInput($updaterSource,[ref]$updaterTokens,[ref]$updaterErrors)
if ($updaterErrors.Count -gt 0) { throw "Standalone updater syntax invalid." }
$updaterDefinitions = @($updaterAst.FindAll({ param($n) $n -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq "Invoke-OsmiumUpdate" },$true))
if ($updaterDefinitions.Count -ne 1) { throw "Expected exactly one standalone updater definition; found $($updaterDefinitions.Count)." }
$commands = [IO.File]::ReadAllText($commandsFile)
$tokens = $null; $errors = $null
$commandsAst = [System.Management.Automation.Language.Parser]::ParseInput($commands,[ref]$tokens,[ref]$errors)
if ($errors.Count -gt 0) { throw "Command module syntax invalid." }
$embedded = @($commandsAst.FindAll({ param($n) $n -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq "Invoke-OsmiumUpdate" },$true))
if ($embedded.Count -gt 1) { throw "Multiple embedded updater definitions found; manual review required." }
$commandsChanged = $false
if ($embedded.Count -eq 1) { $start = $embedded[0].Extent.StartOffset; $end = $embedded[0].Extent.EndOffset; $commands = $commands.Remove($start,$end - $start); $commandsChanged = $true }
$loaderText = '. (Join-Path $PSScriptRoot "Osmium-Updater.ps1")'
$loaderCount = ([regex]::Matches($commands,[regex]::Escape($loaderText))).Count
if ($loaderCount -gt 1) { throw "Multiple standalone updater loaders found." }
if ($loaderCount -eq 0) { $anchor = '. (Join-Path $PSScriptRoot "Osmium-AI-Server.ps1")'; if (-not $commands.Contains($anchor)) { throw "Module import anchor missing; command file unchanged." }; $commands = $commands.Replace($anchor,$anchor + "`r`n" + $loaderText); $commandsChanged = $true }
$dispatchCount = ([regex]::Matches($commands,'(?m)^\s*"-update"\s*\{')).Count
if ($dispatchCount -ne 1) { throw "Expected exactly one -update dispatcher branch; found $dispatchCount." }
$tokens = $null; $errors = $null; [void][System.Management.Automation.Language.Parser]::ParseInput($commands,[ref]$tokens,[ref]$errors)
if ($errors.Count -gt 0) { throw "Patched command module syntax invalid." }
$installer = [IO.File]::ReadAllText($installerFile)
$manifestMatch = [regex]::Match($installer,'(?m)^\s*\$requiredFiles\s*=\s*@\((?<items>[^)]*)\)')
if (-not $manifestMatch.Success) { throw "Installer required-file manifest not found." }
$installerChanged = $false
if ($manifestMatch.Groups["items"].Value -notmatch '"Osmium-Updater\.ps1"') { $old = '"Osmium-Audit.ps1")'; $new = '"Osmium-Audit.ps1","Osmium-Updater.ps1")'; if (-not $installer.Contains($old)) { throw "Installer manifest anchor missing; manual review required." }; $installer = $installer.Replace($old,$new); $installerChanged = $true }
$tokens = $null; $errors = $null; [void][System.Management.Automation.Language.Parser]::ParseInput($installer,[ref]$tokens,[ref]$errors)
if ($errors.Count -gt 0) { throw "Installer syntax invalid." }
$stamp = Get-Date -Format "yyyyMMdd-HHmmss-fff"
if ($commandsChanged) { Copy-Item -LiteralPath $commandsFile -Destination ($commandsFile + ".pre-patcher-" + $stamp) -ErrorAction Stop }
if ($installerChanged) { Copy-Item -LiteralPath $installerFile -Destination ($installerFile + ".pre-patcher-" + $stamp) -ErrorAction Stop }
$encoding = New-Object System.Text.UTF8Encoding($true)
if ($commandsChanged) { [IO.File]::WriteAllText($commandsFile,$commands,$encoding) }
if ($installerChanged) { [IO.File]::WriteAllText($installerFile,$installer,$encoding) }
Write-Host "OSMIUM updater integration verified." -ForegroundColor Green
Write-Host "Embedded updater removed: $($embedded.Count -eq 1)" -ForegroundColor Gray
Write-Host "Standalone loader count: 1" -ForegroundColor Gray
Write-Host "Update dispatcher count: 1" -ForegroundColor Gray
Write-Host "Installer includes standalone updater: True" -ForegroundColor Gray
if (-not $commandsChanged -and -not $installerChanged) { Write-Host "No changes required; integration is already canonical." -ForegroundColor Cyan }
