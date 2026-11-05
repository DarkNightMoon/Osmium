. (Join-Path $PSScriptRoot "Osmium-Policy.ps1")
. (Join-Path $PSScriptRoot "Osmium-Transactions.ps1")
function Resolve-OsmiumAIPath { param([string]$Path,[string]$DefaultFolder='Desktop'); if([string]::IsNullOrWhiteSpace($Path)){$Path=[Environment]::GetFolderPath($DefaultFolder)}; switch -Regex ($Path.Trim()) { '^(?i:documents|downloads|desktop)$' { $name=$_.ToLowerInvariant(); if($name -eq 'documents'){return [Environment]::GetFolderPath('MyDocuments')}; return (Join-Path $env:USERPROFILE $name) }; '^[A-Za-z]$' { return ($Path.ToUpperInvariant()+':\') }; default { return [Environment]::ExpandEnvironmentVariables($Path) } } }

# OSMIUM // LOCAL INTELLIGENCE
# PowerShell 5.1 compatible. Uses a local llama.cpp OpenAI-compatible endpoint.
# Default endpoint: http://127.0.0.1:8080/v1

function Get-OsmiumAIConfig {
    $base = $env:OSMIUM_AI_URL
    if ([string]::IsNullOrWhiteSpace($base)) { $base = "http://127.0.0.1:8080/v1" }
    $base = $base.TrimEnd("/")
    $model = $env:OSMIUM_AI_MODEL
    if ([string]::IsNullOrWhiteSpace($model)) { $model = "qwen08" }
    return @{ BaseUrl = $base; Model = $model }
}

function Get-OsmiumAISystemStatus {
    $os = Get-CimInstance Win32_OperatingSystem -ErrorAction SilentlyContinue
    $cpu = Get-CimInstance Win32_Processor -ErrorAction SilentlyContinue | Select-Object -First 1
    $ramTotal = 0.0
    $ramFree = 0.0
    if ($os) {
        $ramTotal = [math]::Round($os.TotalVisibleMemorySize / 1MB, 1)
        $ramFree = [math]::Round($os.FreePhysicalMemory / 1MB, 1)
    }
    $uptime = "N/A"
    if ($os -and $os.LastBootUpTime) {
        $span = (Get-Date) - $os.LastBootUpTime
        $uptime = "{0}d {1}h {2}m" -f [int]$span.TotalDays, $span.Hours, $span.Minutes
    }
    [pscustomobject]@{
        Host = $env:COMPUTERNAME
        OS = if ($os) { $os.Caption } else { "Windows" }
        CPU = if ($cpu) { $cpu.Name.Trim() } else { "N/A" }
        RAMUsedGB = [math]::Max(0, [math]::Round($ramTotal - $ramFree, 1))
        RAMTotalGB = $ramTotal
        Uptime = $uptime
    }
}

function Invoke-OsmiumAITool {
    param([Parameter(Mandatory=$true)]$Plan)

    $tool = [string]$Plan.tool
    $argsObject = $Plan.args
    if ($null -eq $argsObject) { $argsObject = [pscustomobject]@{} }
    if (-not (Get-Command Test-OsmiumToolPolicy -ErrorAction SilentlyContinue)) { throw "POLICY FAILURE: Policy engine is unavailable." }
    $policyCheck = Test-OsmiumToolPolicy -Tool $tool
    if (-not $policyCheck.Allowed) { throw "POLICY DENIED: $($policyCheck.Reason)" }

    switch ($tool) {
        "respond" {
            Write-Host ([string]$Plan.message) -ForegroundColor White
        }
        "system_status" {
            $data = Get-OsmiumAISystemStatus
            Write-Host ""
            Write-Host " OSMIUM // SYSTEM STATUS" -ForegroundColor Magenta
            $data | Format-List | Out-Host
        }
        "find_large_files" {
            $path = Resolve-OsmiumAIPath ([string]$argsObject.path)
            if ([string]::IsNullOrWhiteSpace($path)) { $path = (Get-Location).Path }
            $minMB = 100
            if ($argsObject.min_mb -and [int]$argsObject.min_mb -ge 1) { $minMB = [int]$argsObject.min_mb }
            $limit = 10
            if ($argsObject.limit -and [int]$argsObject.limit -ge 1) { $limit = [math]::Min(50, [int]$argsObject.limit) }
            if (-not (Test-Path -LiteralPath $path -PathType Container)) {
                throw "Directory not found: $path"
            }
            Write-Host "Scanning $path for files larger than $minMB MB..." -ForegroundColor DarkGray
            Get-ChildItem -LiteralPath $path -File -Recurse -Force -ErrorAction SilentlyContinue |
                Where-Object { $_.Length -ge ($minMB * 1MB) } |
                Sort-Object Length -Descending |
                Select-Object -First $limit @{N="SizeMB";E={[math]::Round($_.Length / 1MB,1)}}, FullName |
                Format-Table -AutoSize | Out-Host
        }
        "search_files" {
            $path = Resolve-OsmiumAIPath ([string]$argsObject.path)
            $query = [string]$argsObject.query
            if ([string]::IsNullOrWhiteSpace($path)) { $path = (Get-Location).Path }
            if ([string]::IsNullOrWhiteSpace($query)) { throw "The search query was empty." }
            if (-not (Test-Path -LiteralPath $path -PathType Container)) { throw "Directory not found: $path" }
            Get-ChildItem -LiteralPath $path -File -Recurse -Force -ErrorAction SilentlyContinue |
                Where-Object { $_.Name -like "*$query*" } |
                Select-Object -First 30 FullName |
                Format-Table -AutoSize | Out-Host
        }
        "organise_preview" {
            $path = Resolve-OsmiumAIPath ([string]$argsObject.path)
            if ([string]::IsNullOrWhiteSpace($path)) { $path = [Environment]::GetFolderPath("Desktop") }
            if (-not (Test-Path -LiteralPath $path -PathType Container)) { throw "Directory not found: $path" }
            $files = @(Get-ChildItem -LiteralPath $path -File -Force -ErrorAction SilentlyContinue)
            if ($files.Count -eq 0) {
                Write-Host "No files found in $path" -ForegroundColor DarkGray
                return
            }
            $groups = $files | Group-Object {
                switch -Regex ($_.Extension.ToLowerInvariant()) {
                    '^\.(jpg|jpeg|png|gif|webp|bmp|svg)$' { "Images"; break }
                    '^\.(mp4|mkv|mov|avi|webm)$' { "Videos"; break }
                    '^\.(mp3|wav|flac|aac|ogg)$' { "Audio"; break }
                    '^\.(pdf|doc|docx|txt|rtf|ppt|pptx|xls|xlsx|csv)$' { "Documents"; break }
                    '^\.(zip|7z|rar|tar|gz)$' { "Archives"; break }
                    '^\.(exe|msi|msix)$' { "Installers"; break }
                    default { "Other"; break }
                }
            }
            Write-Host " ORGANISATION PREVIEW â€” no files moved" -ForegroundColor Magenta
            foreach ($group in $groups) {
                Write-Host (" {0,-14} {1,4} file(s)" -f $group.Name, $group.Count) -ForegroundColor White
            }
            Write-Host "Run with a future explicit apply command to move files. Nothing was changed." -ForegroundColor DarkGray
        }
        "create_folder" {
            $path = Resolve-OsmiumAIPath ([string]$argsObject.path)
            if ([string]::IsNullOrWhiteSpace($path)) { throw "No folder path was supplied." }
            $fullPath = [IO.Path]::GetFullPath($path)
            $k = Get-ItemProperty "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\User Shell Folders"
            $roots = @([Environment]::GetFolderPath("MyDocuments"),[Environment]::GetFolderPath("Desktop"),[Environment]::ExpandEnvironmentVariables([string]$k.'{374DE290-123F-4565-9164-39C4925E467B}'))
            $allowed = $false
            foreach ($root in $roots) { $r = [IO.Path]::GetFullPath($root).TrimEnd("\") + "\"; if ($fullPath.StartsWith($r,[StringComparison]::OrdinalIgnoreCase)) { $allowed = $true; break } }
            if (-not $allowed) { throw "POLICY DENIED: Folder creation is restricted to Documents, Desktop, and Downloads." }
            $cursor = [IO.DirectoryInfo]$fullPath
            while ($null -ne $cursor) { if (Test-Path -LiteralPath $cursor.FullName) { $item = Get-Item -LiteralPath $cursor.FullName -Force; if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { throw "POLICY DENIED: Destination contains a junction or symbolic link." } }; $cursor = $cursor.Parent }
            if (Test-Path -LiteralPath $fullPath) { Write-Host "Already exists: $fullPath" -ForegroundColor Yellow; return }
            Write-Host "OSMIUM wants to create: $fullPath" -ForegroundColor Yellow
            $approval = Request-OsmiumApproval -Tool $tool -Target $fullPath -Arguments $argsObject; if ($approval.Approved) {
                $tx = $null; $created = $false; try { $tx = New-OsmiumTransaction -Tool "create_folder" -Target $fullPath
                    if (-not (Test-Path -LiteralPath ([IO.Directory]::GetParent($fullPath).FullName) -PathType Container)) { throw "Parent directory must already exist; automatic parent creation is disabled." }; New-Item -ItemType Directory -Path $fullPath -ErrorAction Stop | Out-Null
                    $created = $true; Register-OsmiumCreatedFolder -Record $tx
                    Set-OsmiumTransactionState -Record $tx -State "Applied"
                    if (-not (Test-Path -LiteralPath $fullPath -PathType Container)) { throw "Folder creation could not be verified." }; Write-OsmiumAuditEvent -EventType "EXECUTION" -Tool $tool -Target $fullPath -Risk $approval.Risk -Fingerprint $approval.Fingerprint -Decision "Approved" -Outcome "Success" -TransactionId $tx.Id -Details "Folder creation verified" | Out-Null
                    Write-Host "Folder created: $fullPath" -ForegroundColor Green
                } catch {
                    $failure = $_.Exception.Message; try { Write-OsmiumAuditEvent -EventType "EXECUTION" -Tool $tool -Target $fullPath -Risk $approval.Risk -Fingerprint $approval.Fingerprint -Decision "Approved" -Outcome "Failure" -TransactionId $(if ($null -ne $tx) { $tx.Id } else { "" }) -Details $failure | Out-Null } catch { Write-Host "EXECUTION AUDIT FAILURE: $($_.Exception.Message)" -ForegroundColor Red }
                    if ($created) {
                        try {
                            $rolledBack = Undo-OsmiumCreatedFolder -Record $tx
                            if ($rolledBack) { Write-OsmiumAuditEvent -EventType "ROLLBACK" -Tool $tool -Target $fullPath -Risk $approval.Risk -Fingerprint $approval.Fingerprint -Decision "Automatic" -Outcome "Success" -TransactionId $tx.Id -Details "Verified empty folder removed" | Out-Null; Write-Host "Automatic rollback completed." -ForegroundColor Green } else { Write-OsmiumAuditEvent -EventType "ROLLBACK" -Tool $tool -Target $fullPath -Risk $approval.Risk -Fingerprint $approval.Fingerprint -Decision "Automatic" -Outcome "Blocked" -TransactionId $tx.Id -Details $tx.RollbackMessage | Out-Null; Write-Host "ROLLBACK BLOCKED: Folder was preserved. Check transaction journal." -ForegroundColor Yellow }
                        } catch { $rollbackFailure=$_.Exception.Message; try { Set-OsmiumTransactionState -Record $tx -State "RecoveryRequired" -Message $rollbackFailure } catch { Write-Host "TRANSACTION RECOVERY STATE FAILURE: $($_.Exception.Message)" -ForegroundColor Red }; try { Write-OsmiumAuditEvent -EventType "ROLLBACK" -Tool $tool -Target $fullPath -Risk $approval.Risk -Fingerprint $approval.Fingerprint -Decision "Automatic" -Outcome "Error" -TransactionId $tx.Id -Details $rollbackFailure | Out-Null } catch { Write-Host "ROLLBACK AUDIT FAILURE: $($_.Exception.Message)" -ForegroundColor Red }; Write-Host "ROLLBACK ERROR: $rollbackFailure. Manual inspection required." -ForegroundColor Red }
                    }
                    if (-not $created -and $null -ne $tx) { try { Set-OsmiumTransactionState -Record $tx -State "Failed" -Message $failure } catch { Write-Host "TRANSACTION STATE FAILURE: $($_.Exception.Message)" -ForegroundColor Red } }
                    throw "Folder creation failed: $failure"
                }
            } else { Write-Host "Cancelled. No changes made." -ForegroundColor DarkGray }
        }
        default {
            throw "OSMIUM rejected an unknown tool: '$tool'. No action was executed."
        }
    }
}

function Invoke-OsmiumAI {
    param([Parameter(Mandatory=$true)][string]$Request)

    if ([string]::IsNullOrWhiteSpace($Request)) {
        Write-Host 'Usage: osmium -ai "organise my desktop"' -ForegroundColor Yellow
        return
    }

    if ($Request -match '(?i)\b(install|uninstall|delete|remove|move|rename|overwrite|terminate|kill|registry|winget|choco|scoop)\b') { Write-Host 'OSMIUM AI // This operation is not supported.' -ForegroundColor Yellow; Write-Host 'Available: system status, file search, large-file discovery, organisation preview, and confirmed folder creation.' -ForegroundColor DarkGray; return }

    $config = Get-OsmiumAIConfig
    $uri = "$($config.BaseUrl)/chat/completions"

    $systemPrompt = @'
You are OSMIUM, a local Windows automation assistant.

Return exactly one valid JSON object and no markdown.
Schema: {"tool":"TOOL_NAME","args":{},"message":"short user-facing explanation"}

AVAILABLE TOOLS:
- respond: answer conversationally; args {}
- system_status: retrieve basic Windows system status; args {}
- find_large_files: find large files; args {"path":"directory path or empty","min_mb":100,"limit":10}
- search_files: search filenames; args {"path":"directory path or empty","query":"filename fragment"}
- organise_preview: preview file organisation; args {"path":"directory path or empty"}. Never move or modify files.
- create_folder: create a folder; args {"path":"full folder path"}. User confirmation is required.

TOOL ROUTING RULES:
1. Default to respond for ordinary conversation, factual questions, definitions, explanations, advice, and general knowledge.
2. Use system_status only when the user explicitly asks about this computer, its hardware, operating system, uptime, memory usage, or system resources.
3. Use find_large_files only when the user asks to locate or list unusually large files.
4. Use search_files only when the user asks to find files by filename or filename fragment.
5. Use organise_preview only when the user explicitly asks to preview or plan file organisation.
6. Use create_folder only when the user explicitly asks to create a directory.
7. Never select a system tool merely because the question mentions computers, software, files, or technology.
8. If no system operation is explicitly requested, select respond with empty args.
9. Examples: 'What is ChatGPT?' -> respond; 'How much RAM is in use?' -> system_status; 'Find files larger than 1 GB' -> find_large_files; 'Search for report.xlsx' -> search_files.

STRICT RESTRICTIONS:
1. You cannot install or uninstall software.
2. You cannot execute arbitrary PowerShell, CMD, or scripts.
3. You cannot delete, move, rename, or overwrite files.
4. You cannot terminate processes.
5. You cannot modify Windows settings, registry, services, or security configuration.
6. You cannot control applications outside the listed tools.
7. A preview is not an executed action.
8. Never invent tools, capabilities, results, or completed actions.
9. Never claim an operation succeeded unless a tool actually performed it.
10. For unsupported requests, use respond and clearly explain the limitation.

Choose exactly one available tool per request.
'@

    $body = @{
        model = $config.Model
        temperature = 0.1
        max_tokens = 320
        response_format = @{ type = "json_schema"; json_schema = @{ name = "osmium_tool_plan"; strict = $true; schema = @{ type = "object"; properties = @{ tool = @{ type = "string"; enum = @("respond","system_status","find_large_files","search_files","organise_preview","create_folder") }; args = @{ type = "object"; additionalProperties = $true }; message = @{ type = "string" } }; required = @("tool","args","message"); additionalProperties = $false } } }
        messages = @(
            @{ role = "system"; content = $systemPrompt },
            @{ role = "user"; content = $Request }
        )
    } | ConvertTo-Json -Depth 8

    try {
        $response = Invoke-RestMethod -Uri $uri -Method Post -ContentType "application/json" -Body $body -TimeoutSec 45 -ErrorAction Stop
    } catch {
        Write-Host "OSMIUM AI could not reach llama.cpp at $uri" -ForegroundColor Red
        Write-Host "Start your local model server, then check OSMIUM_AI_URL if it uses another port." -ForegroundColor DarkGray
        Write-Host $_.Exception.Message -ForegroundColor DarkGray
        return
    }

    $content = [string]$response.choices[0].message.content
    if ([string]::IsNullOrWhiteSpace($content)) {
        Write-Host "The model returned an empty response." -ForegroundColor Red
        return
    }

    $content = $content.Trim()
    $content = $content -replace '^\s*```(?:json)?\s*', ''
    $content = $content -replace '\s*```\s*$', ''

    try {
        $plan = $content | ConvertFrom-Json -ErrorAction Stop
        if ($plan -is [array] -or -not $plan.tool) { throw "Invalid plan schema." }
    } catch {
        Write-Host "OSMIUM could not parse the model tool plan." -ForegroundColor Red
        Write-Host "Model output: $content" -ForegroundColor DarkGray
        return
    }

    try {
        Invoke-OsmiumAITool -Plan $plan
    } catch {
        Write-Host "OSMIUM tool execution failed: $($_.Exception.Message)" -ForegroundColor Red
    }
}

function Test-OsmiumAIConnection {
    $config = Get-OsmiumAIConfig
    try {
        $null = Invoke-RestMethod -Uri "$($config.BaseUrl)/models" -Method Get -TimeoutSec 5 -ErrorAction Stop
        Write-Host "OSMIUM AI // llama.cpp reachable at $($config.BaseUrl)" -ForegroundColor Green
        Write-Host "Configured model label: $($config.Model)" -ForegroundColor DarkGray
    } catch {
        Write-Host "OSMIUM AI // llama.cpp not reachable at $($config.BaseUrl)" -ForegroundColor Red
        Write-Host "Start the llama.cpp server and verify its port." -ForegroundColor DarkGray
    }
}
