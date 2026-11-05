# OSMIUM AI server lifecycle management.
# Requires Get-OsmiumAIConfig from Osmium-AI.ps1.

function Get-OsmiumAIServerPaths {
    $root = Join-Path $env:LOCALAPPDATA "OsmiumTerminal"
    $logs = Join-Path $root "logs"

    if (-not (Test-Path -LiteralPath $logs)) {
        New-Item -ItemType Directory -Path $logs -Force | Out-Null
    }

    return @{
        Root = $root
        Pid  = Join-Path $root "ai-server.pid"
        Out  = Join-Path $logs "ai-server.out.log"
        Err  = Join-Path $logs "ai-server.err.log"
    }
}

function Start-OsmiumAIServer {
    $config = Get-OsmiumAIConfig
    $uri = [uri]$config.BaseUrl

    if ($uri.Scheme -ne "http" -or
        $uri.Host -notin @("127.0.0.1", "localhost") -or
        $uri.Port -ne 8080) {
        Write-Host "OSMIUM AI // Server manager requires http://127.0.0.1:8080/v1" -ForegroundColor Red
        return
    }

    # Do not claim ownership of a server started outside OSMIUM.
    try {
        Invoke-RestMethod "$($config.BaseUrl)/models" -TimeoutSec 2 | Out-Null
        Write-Host "OSMIUM AI // A server is already responding at $($config.BaseUrl)." -ForegroundColor Yellow
        Write-Host "It was not started by this OSMIUM session; no PID ownership was claimed." -ForegroundColor DarkGray
        return
    }
    catch {}

    $paths = Get-OsmiumAIServerPaths

    # Remove a stale PID file, but never stop a process based only on a stale PID.
    if (Test-Path -LiteralPath $paths.Pid) {
        Remove-Item -LiteralPath $paths.Pid -Force -ErrorAction SilentlyContinue
    }

    $llama = Get-Command "llama.exe" -ErrorAction SilentlyContinue
    if (-not $llama) {
        $llama = Get-Command "llama" -ErrorAction SilentlyContinue
    }

    if (-not $llama -or -not $llama.Source) {
        Write-Host "OSMIUM AI // llama.exe was not found on PATH." -ForegroundColor Red
        return
    }

    $serverArgs = @(
        "serve",
        "--hf-repo", "ggml-org/Qwen3.5-0.8B-GGUF:Q8_0",
        "--host", "127.0.0.1",
        "--port", "8080",
        "-ngl", "all",
        "--reasoning", "off",
        "--reasoning-budget", "0"
    )

    try {
        $process = Start-Process -FilePath $llama.Source `
            -ArgumentList $serverArgs `
            -WindowStyle Hidden `
            -RedirectStandardOutput $paths.Out `
            -RedirectStandardError $paths.Err `
            -PassThru

        Set-Content -LiteralPath $paths.Pid -Value $process.Id -Encoding ASCII
    }
    catch {
        Write-Host "OSMIUM AI // Failed to launch llama.cpp: $_" -ForegroundColor Red
        return
    }

    Write-Host "OSMIUM AI // Starting Qwen3.5 0.8B..." -ForegroundColor Cyan

    for ($i = 0; $i -lt 60; $i++) {
        Start-Sleep -Seconds 1

        if ($process.HasExited) {
            Remove-Item -LiteralPath $paths.Pid -Force -ErrorAction SilentlyContinue
            Write-Host "OSMIUM AI // Server exited during startup. Check $($paths.Err)" -ForegroundColor Red
            return
        }

        try {
            Invoke-RestMethod "$($config.BaseUrl)/models" -TimeoutSec 2 | Out-Null
            Write-Host "OSMIUM AI // Server online at $($config.BaseUrl)." -ForegroundColor Green
            return
        }
        catch {}
    }

    Write-Host "OSMIUM AI // Startup timed out. Check $($paths.Err)" -ForegroundColor Red
}

function Stop-OsmiumAIServer {
    $paths = Get-OsmiumAIServerPaths

    if (-not (Test-Path -LiteralPath $paths.Pid)) {
        Write-Host "OSMIUM AI // No OSMIUM-managed server PID found. Nothing stopped." -ForegroundColor Yellow
        return
    }

    $serverPid = 0
    $parsed = [int]::TryParse((Get-Content -LiteralPath $paths.Pid -Raw).Trim(), [ref]$serverPid)

    if (-not $parsed -or $serverPid -le 0) {
        Remove-Item -LiteralPath $paths.Pid -Force -ErrorAction SilentlyContinue
        Write-Host "OSMIUM AI // Invalid PID file removed; no process was stopped." -ForegroundColor Yellow
        return
    }

    $process = Get-CimInstance Win32_Process -Filter "ProcessId = $serverPid" -ErrorAction SilentlyContinue

    if (-not $process -or
        $process.Name -ine "llama.exe" -or
        $process.CommandLine -notmatch "--port\s+8080" -or
        $process.CommandLine -notmatch "Qwen3\.5-0\.8B-GGUF") {
        Remove-Item -LiteralPath $paths.Pid -Force -ErrorAction SilentlyContinue
        Write-Host "OSMIUM AI // PID ownership check failed. No process was stopped; stale PID file removed." -ForegroundColor Yellow
        return
    }

    try {
        Stop-Process -Id $serverPid -ErrorAction Stop
        Remove-Item -LiteralPath $paths.Pid -Force -ErrorAction SilentlyContinue
        Write-Host "OSMIUM AI // Managed server stopped." -ForegroundColor Green
    }
    catch {
        Write-Host "OSMIUM AI // Could not stop managed server: $_" -ForegroundColor Red
    }
}
