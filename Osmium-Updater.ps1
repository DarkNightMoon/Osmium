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

    if ($ahead -gt 0) {
        if ($behind -gt 0) {
            Write-Host "Update stopped: local and remote branches have diverged. Reconcile Git history first." -ForegroundColor Yellow
        } else {
            Write-Host "Your local branch is $ahead commit(s) ahead of GitHub. Push your changes first." -ForegroundColor Yellow
        }
        return
    }

    if ($behind -gt 0) {
        Write-Host "[2/4] Updating project from GitHub..." -ForegroundColor Gray
        & git -C $projectPath pull --ff-only $remote $branch
        if ($LASTEXITCODE -ne 0) {
            Write-Host "Git pull failed. Installed runtime was not changed." -ForegroundColor Red
            return
        }
    }

    $allowed = @("Osmium-Banner.ps1", "Osmium-Commands.ps1", "Osmium-Fetch.ps1", "Osmium-AI.ps1", "Osmium-AI-Server.ps1", "Osmium-Policy.ps1", "Osmium-Transactions.ps1", "Osmium-Audit.ps1", "Osmium-Updater.ps1")
    $missing = @($allowed | Where-Object { -not (Test-Path -LiteralPath (Join-Path $projectPath $_) -PathType Leaf) })
    if ($missing.Count -gt 0) { throw "Update aborted; required modules missing: $($missing -join ', ')" }
    if (-not (Test-Path -LiteralPath $runtimePath -PathType Container)) { throw "Installed runtime is missing; update aborted." }
    $runtimeRootItem = Get-Item -LiteralPath $runtimePath -Force -ErrorAction Stop
    if (($runtimeRootItem.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { throw "Runtime root is a reparse point; update aborted." }
    $runtimeLinks = @(Get-ChildItem -LiteralPath $runtimePath -Force -Recurse -ErrorAction Stop | Where-Object { ($_.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0 })
    if ($runtimeLinks.Count -gt 0) { throw "Runtime contains reparse points; update aborted: $($runtimeLinks[0].FullName)" }
    $existing = @()
    $runtimeMatches = $true
    foreach ($name in $allowed) {
        $destination = Join-Path $runtimePath $name
        if (Test-Path -LiteralPath $destination) {
            $item = Get-Item -LiteralPath $destination -Force -ErrorAction Stop
            if ($item.PSIsContainer -or (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0)) { throw "Unsafe runtime module destination: $name" }
            $existing += $name
            $sourceHash = (Get-FileHash -LiteralPath (Join-Path $projectPath $name) -Algorithm SHA256 -ErrorAction Stop).Hash
            $runtimeHash = (Get-FileHash -LiteralPath $destination -Algorithm SHA256 -ErrorAction Stop).Hash
            if ($sourceHash -ne $runtimeHash) { $runtimeMatches = $false }
        } else {
            $runtimeMatches = $false
        }
    }
    if ($runtimeMatches) { Write-Host "OSMIUM runtime already matches the project. No deployment required." -ForegroundColor Green; return }
    Write-Host "[2/4] Backing up installed runtime..." -ForegroundColor Gray
    if (-not (Test-Path -LiteralPath $runtimePath -PathType Container)) { throw "Installed runtime is missing; update aborted." }
    $backupRoot = Join-Path $env:LOCALAPPDATA "OsmiumBackups"
    New-Item -ItemType Directory -Force -Path $backupRoot -ErrorAction Stop | Out-Null
    $stamp = Get-Date -Format "yyyyMMdd-HHmmss-fff"
    $backup = Join-Path $backupRoot "Osmium-$stamp"
    Copy-Item -LiteralPath $runtimePath -Destination $backup -Recurse -Force -ErrorAction Stop
    if (-not (Test-Path -LiteralPath $backup -PathType Container)) { throw "Runtime backup verification failed; update aborted." }
    $originalItems = @(Get-ChildItem -LiteralPath $runtimePath -Force -Recurse -ErrorAction Stop)
    $backupItems = @(Get-ChildItem -LiteralPath $backup -Force -Recurse -ErrorAction Stop)
    if ($originalItems.Count -ne $backupItems.Count) { throw "Runtime backup inventory mismatch; update aborted." }
    foreach ($item in $originalItems) {
        $relative = $item.FullName.Substring($runtimePath.Length).TrimStart([char[]]@([IO.Path]::DirectorySeparatorChar,[IO.Path]::AltDirectorySeparatorChar))
        $savedPath = Join-Path $backup $relative
        if (-not (Test-Path -LiteralPath $savedPath)) { throw "Runtime backup item missing: $relative" }
        $savedItem = Get-Item -LiteralPath $savedPath -Force -ErrorAction Stop
        if ($item.PSIsContainer -ne $savedItem.PSIsContainer) { throw "Runtime backup item type mismatch: $relative" }
        if (-not $item.PSIsContainer) {
            $originalHash = (Get-FileHash -LiteralPath $item.FullName -Algorithm SHA256 -ErrorAction Stop).Hash
            $savedHash = (Get-FileHash -LiteralPath $savedPath -Algorithm SHA256 -ErrorAction Stop).Hash
            if ($originalHash -ne $savedHash) { throw "Runtime backup hash mismatch: $relative" }
        }
    }
    Write-Host "Backup: $backup" -ForegroundColor DarkGray


    Write-Host "[4/4] Staging updated OSMIUM files..." -ForegroundColor Gray
    $stage = Join-Path $runtimePath (".osmium-stage-" + [guid]::NewGuid().ToString("N"))
    $moduleBackup = Join-Path $backup "module-files"

    $deployed = $false
    $deploymentStarted = $false
    try {
        New-Item -ItemType Directory -Path $stage -ErrorAction Stop | Out-Null
        New-Item -ItemType Directory -Path $moduleBackup -ErrorAction Stop | Out-Null
        foreach ($name in $allowed) {
            $source = Join-Path $projectPath $name
            $stagedFile = Join-Path $stage $name
            Copy-Item -LiteralPath $source -Destination $stagedFile -ErrorAction Stop
            $sourceHash = (Get-FileHash -LiteralPath $source -Algorithm SHA256 -ErrorAction Stop).Hash
            $stageHash = (Get-FileHash -LiteralPath $stagedFile -Algorithm SHA256 -ErrorAction Stop).Hash
            if ($sourceHash -ne $stageHash) { throw "Staging verification failed: $name" }
        }
        foreach ($name in $existing) {
            $original = Join-Path $runtimePath $name
            $saved = Join-Path $moduleBackup $name
            Copy-Item -LiteralPath $original -Destination $saved -ErrorAction Stop
            $originalHash = (Get-FileHash -LiteralPath $original -Algorithm SHA256 -ErrorAction Stop).Hash
            $savedHash = (Get-FileHash -LiteralPath $saved -Algorithm SHA256 -ErrorAction Stop).Hash
            if ($originalHash -ne $savedHash) { throw "Recovery snapshot verification failed: $name" }
        }
        Write-Host "All staged modules verified. Deploying..." -ForegroundColor Gray
        $deploymentStarted = $true
        foreach ($name in $allowed) { Copy-Item -LiteralPath (Join-Path $stage $name) -Destination (Join-Path $runtimePath $name) -Force -ErrorAction Stop }
        foreach ($name in $allowed) {
            $deployedHash = (Get-FileHash -LiteralPath (Join-Path $runtimePath $name) -Algorithm SHA256 -ErrorAction Stop).Hash
            $stageHash = (Get-FileHash -LiteralPath (Join-Path $stage $name) -Algorithm SHA256 -ErrorAction Stop).Hash
            if ($deployedHash -ne $stageHash) { throw "Deployment verification failed: $name" }
        }
        $deployed = $true
    } catch {
        $deployError = $_.Exception.Message
        Write-Host "Deployment failed: $deployError" -ForegroundColor Red
        if (-not $deploymentStarted) { throw "Deployment did not begin; installed modules were not changed. $deployError" }
        Write-Host "Restoring previous module state..." -ForegroundColor Yellow
        try {
            foreach ($name in $allowed) {
                $destination = Join-Path $runtimePath $name
                if ($existing -contains $name) {
                    $saved = Join-Path $moduleBackup $name
                    if (-not (Test-Path -LiteralPath $saved -PathType Leaf)) { throw "Recovery copy missing: $name" }
                    Copy-Item -LiteralPath $saved -Destination $destination -Force -ErrorAction Stop
                    $savedHash = (Get-FileHash -LiteralPath $saved -Algorithm SHA256 -ErrorAction Stop).Hash
                    $restoredHash = (Get-FileHash -LiteralPath $destination -Algorithm SHA256 -ErrorAction Stop).Hash
                    if ($savedHash -ne $restoredHash) { throw "Recovery verification failed: $name" }
                } elseif (Test-Path -LiteralPath $destination) {
                    Remove-Item -LiteralPath $destination -Force -ErrorAction Stop
                }
            }
            Write-Host "Previous module state restored and verified." -ForegroundColor Green
        } catch {
            Write-Host "CRITICAL: Module restoration failed: $($_.Exception.Message)" -ForegroundColor Red
            Write-Host "Preserve recovery data at: $moduleBackup" -ForegroundColor Yellow
            throw "Deployment failed and automatic restoration requires manual recovery. Original error: $deployError"
        }
        throw "Deployment failed; previous module state was restored. $deployError"
    } finally {
        if (($deployed -or -not $deploymentStarted) -and (Test-Path -LiteralPath $stage)) { Remove-Item -LiteralPath $stage -Recurse -Force -ErrorAction SilentlyContinue }
    }
    Write-Host "OSMIUM updated successfully." -ForegroundColor Green
    Write-Host "Restart PowerShell to load the updated command module." -ForegroundColor Cyan
}
