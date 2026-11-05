$ErrorActionPreference = "Stop"

$project = "D:\OSMIUM-Command-System"
$commandsFile = Join-Path $project "Osmium-Commands.ps1"
$installerFile = Join-Path $project "Install-Osmium-Command-System.ps1"

if (-not (Test-Path $commandsFile)) {
    throw "Cannot find $commandsFile. Run this patch from the expected OSMIUM project layout."
}

$source = Get-Content -LiteralPath $commandsFile -Raw

if ($source -match 'function\s+Invoke-OsmiumUpdate') {
    Write-Host "Updater function already exists in the project." -ForegroundColor Yellow
    exit 0
}

$functionCode = @'
function Invoke-OsmiumUpdate {
    $projectPath = "D:\OSMIUM-Command-System"
    $runtimePath = Join-Path $env:LOCALAPPDATA "OsmiumTerminal"
    $remote = "origin"
    $branch = "main"

    Write-Host "`nOSMIUM // UPDATE SERVICE" -ForegroundColor Magenta

    if (-not (Get-Command git.exe -ErrorAction SilentlyContinue)) {
        Write-Host "Git is not installed or not on PATH." -ForegroundColor Red
        return
    }
    if (-not (Test-Path (Join-Path $projectPath ".git"))) {
        Write-Host "Development repository not found: $projectPath" -ForegroundColor Red
        return
    }

    $status = & git -C $projectPath status --porcelain
    if ($LASTEXITCODE -ne 0) {
        Write-Host "Could not inspect Git working tree." -ForegroundColor Red
        return
    }
    if ($status) {
        Write-Host "Update stopped: local project has uncommitted changes." -ForegroundColor Yellow
        Write-Host "Commit or stash them, then run osmium -update again." -ForegroundColor Yellow
        return
    }

    Write-Host "[1/4] Checking GitHub..." -ForegroundColor Gray
    & git -C $projectPath fetch $remote $branch
    if ($LASTEXITCODE -ne 0) {
        Write-Host "Fetch failed. Check internet access and GitHub authentication." -ForegroundColor Red
        return
    }

    $counts = & git -C $projectPath rev-list --left-right --count "HEAD...$remote/$branch"
    if ($LASTEXITCODE -ne 0 -or -not $counts) {
        Write-Host "Could not compare local and remote versions." -ForegroundColor Red
        return
    }
    $parts = ($counts -split '\s+')
    $ahead = [int]$parts[0]
    $behind = [int]$parts[1]

    if ($behind -eq 0) {
        if ($ahead -gt 0) {
            Write-Host "Your local branch is $ahead commit(s) ahead of GitHub. Push your changes first." -ForegroundColor Yellow
        } else {
            Write-Host "OSMIUM is already up to date." -ForegroundColor Green
        }
        return
    }
    if ($ahead -gt 0) {
        Write-Host "Update stopped: local and remote branches have diverged. Reconcile Git history first." -ForegroundColor Yellow
        return
    }

    Write-Host "[2/4] Backing up installed runtime..." -ForegroundColor Gray
    if (Test-Path $runtimePath) {
        $backupRoot = Join-Path $env:LOCALAPPDATA "OsmiumBackups"
        New-Item -ItemType Directory -Force -Path $backupRoot | Out-Null
        $stamp = Get-Date -Format "yyyyMMdd-HHmmss"
        $backup = Join-Path $backupRoot "Osmium-$stamp"
        Copy-Item -LiteralPath $runtimePath -Destination $backup -Recurse -Force
        Write-Host "Backup: $backup" -ForegroundColor DarkGray
    }

    Write-Host "[3/4] Updating project from GitHub..." -ForegroundColor Gray
    & git -C $projectPath pull --ff-only $remote $branch
    if ($LASTEXITCODE -ne 0) {
        Write-Host "Git pull failed. Installed runtime was not changed." -ForegroundColor Red
        return
    }

    Write-Host "[4/4] Installing updated OSMIUM files..." -ForegroundColor Gray
    New-Item -ItemType Directory -Force -Path $runtimePath | Out-Null
    $allowed = @("Osmium-Banner.ps1", "Osmium-Commands.ps1")
    foreach ($name in $allowed) {
        $from = Join-Path $projectPath $name
        if (Test-Path $from) {
            Copy-Item -LiteralPath $from -Destination (Join-Path $runtimePath $name) -Force
        }
    }

    Write-Host "OSMIUM updated successfully." -ForegroundColor Green
    Write-Host "Restart PowerShell to load the updated command module." -ForegroundColor Cyan
}
'@

# Add updater function before the public command dispatcher.
$marker = 'function global:osmium {'
if (-not $source.Contains($marker)) {
    throw "Could not locate the osmium command dispatcher. No changes were made."
}
$source = $source.Replace($marker, $functionCode + "`r`n`r`n" + $marker)

# Add the command to the help menu.
$helpLine = 'Write-Host " osmium -sys Open live system monitor" -ForegroundColor White'
if ($source.Contains($helpLine) -and $source -notmatch 'osmium -update') {
    $source = $source.Replace($helpLine, $helpLine + "`r`nWrite-Host `" osmium -update Check GitHub and update installed OSMIUM`" -ForegroundColor White")
}

# Add the command branch to the dispatcher.
$defaultMarker = '        default {'
if (-not $source.Contains('"-update"')) {
    if (-not $source.Contains($defaultMarker)) {
        throw "Could not locate command switch default branch. No changes were made."
    }
    $source = $source.Replace($defaultMarker, @'
        "-update" {
            Invoke-OsmiumUpdate
        }
        default {
'@)
}

Set-Content -LiteralPath $commandsFile -Value $source -Encoding UTF8

# Ensure future installations include the updated command module in runtime.
if (Test-Path $installerFile) {
    $installer = Get-Content -LiteralPath $installerFile -Raw
    if ($installer -notmatch 'Osmium-Commands\.ps1') {
        Write-Warning "Installer did not contain the expected module-copy rule. Review it manually."
    }
}

Write-Host "`nUpdater added to project source." -ForegroundColor Green
Write-Host "Next: test syntax, commit, and push the change to GitHub." -ForegroundColor Cyan
