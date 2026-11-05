# OSMIUM AI Prototype — Qwen 0.8B + llama.cpp

This is the first local AI prototype for OSMIUM. It is designed for Windows PowerShell 5.1 and an OpenAI-compatible llama.cpp server.

## Architecture

User request → Qwen planner → JSON tool plan → OSMIUM allowlist/validation → PowerShell tool → result.

The model does **not** execute PowerShell. It can only select one of the hard-coded tools in `Osmium-AI.ps1`.

## Included tools

- `respond` — conversational fallback
- `system_status` — basic host/OS/CPU/RAM/uptime summary
- `find_large_files` — read-only large-file scan
- `search_files` — read-only filename search
- `organise_preview` — categorises Desktop files without moving anything
- `create_folder` — asks for confirmation before creating a directory

Delete, move, overwrite, process termination, software installation and settings changes are deliberately disabled in this prototype.

## Install

1. Copy `Osmium-AI.ps1` into `D:\OSMIUM-Command-System`.
2. Open `D:\OSMIUM-Command-System\Osmium-Commands.ps1`.
3. Add this near the top, after the existing Fetch dot-source line:

   `. (Join-Path $PSScriptRoot "Osmium-AI.ps1")`

4. In `Invoke-OsmiumUpdate`, add `"Osmium-AI.ps1"` to `$allowed`.
5. In the `osmium` switch, add these cases:

   ```powershell
   "-ai" {
       $request = ($Arguments | Select-Object -Skip 1) -join " "
       Invoke-OsmiumAI -Request $request
   }
   "-ai-status" {
       Test-OsmiumAIConnection
   }
   ```

6. Add these lines to the help menu:

   ```powershell
   Write-Host " osmium -ai       Ask local OSMIUM AI" -ForegroundColor White
   Write-Host " osmium -ai-status Check local AI connection" -ForegroundColor White
   ```

7. Copy the module into the installed runtime:

   ```powershell
   Copy-Item "D:\OSMIUM-Command-System\Osmium-AI.ps1" "$env:LOCALAPPDATA\OsmiumTerminal\Osmium-AI.ps1" -Force
   Unblock-File "$env:LOCALAPPDATA\OsmiumTerminal\Osmium-AI.ps1"
   ```

8. Reload the command module:

   `. "$env:LOCALAPPDATA\OsmiumTerminal\Osmium-Commands.ps1"`

## llama.cpp server

The module defaults to:

- Base URL: `http://127.0.0.1:8080/v1`
- Model label: `qwen08`

Start your Qwen 0.8B GGUF with llama.cpp's server on port 8080 and use an OpenAI-compatible `/v1` API. The `model` field is a label; llama.cpp often accepts any non-empty model name when a single model is loaded.

If your server uses another port:

```powershell
$env:OSMIUM_AI_URL = "http://127.0.0.1:PORT/v1"
```

Optionally set the model label:

```powershell
$env:OSMIUM_AI_MODEL = "qwen08"
```

These environment variables apply to the current PowerShell session. To make them persistent, use `[Environment]::SetEnvironmentVariable(...)` with the `User` target.

## Test

```powershell
osmium -ai-status
osmium -ai "show my system status"
osmium -ai "find files larger than 500 MB in D:\"
osmium -ai "preview how you would organise my desktop"
osmium -ai "create a folder named OSMIUM-Test in my Documents"
```

For the last example, OSMIUM asks for confirmation before creating anything.

## Known limitations

- A 0.8B model may emit malformed JSON or choose the wrong tool. The dispatcher rejects invalid/unknown tools; retry or simplify the request.
- Recursive file scans can be slow on large drives. Start with a specific directory.
- The first prototype uses one tool call per request; no autonomous multi-step loops yet.
- This module does not modify the existing `-sys` or `-fetch` tools.
