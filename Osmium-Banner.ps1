# OSMIUM startup screen — intentionally no system monitor at startup.
$Host.UI.RawUI.WindowTitle = "OSMIUM"
$purple = "$([char]27)[38;2;190;140;255m"
$white  = "$([char]27)[38;2;255;255;255m"
$reset  = "$([char]27)[0m"

$logo = @(
"██████╗ ███████╗███╗   ███╗██╗██╗   ██╗███╗   ███╗",
"██╔═══██╗██╔════╝████╗ ████║██║██║   ██║████╗ ████║",
"██║   ██║███████╗██╔████╔██║██║██║   ██║██╔████╔██║",
"██║   ██║╚════██║██║╚██╔╝██║██║██║   ██║██║╚██╔╝██║",
"╚██████╔╝███████║██║ ╚═╝ ██║██║╚██████╔╝██║ ╚═╝ ██║",
" ╚═════╝ ╚══════╝╚═╝     ╚═╝╚═╝ ══════╝ ╚═╝     ╚═╝"
)
# Keep the established OSMIUM logo text and two-tone glyph treatment.
$logo[5] = " ╚═════╝ ╚══════╝╚═╝     ╚═╝╚═╝ ══════╝ ╚═╝     ╚═╝"
foreach ($line in $logo) {
    foreach ($ch in $line.ToCharArray()) {
        if ($ch -eq [char]0x2588) { [Console]::Write($white + $ch + $reset) }
        elseif ([int]$ch -ge 0x2500 -and [int]$ch -le 0x257F) { [Console]::Write($purple + $ch + $reset) }
        else { [Console]::Write($ch) }
    }
    [Console]::WriteLine()
}
Write-Host ""
Write-Host "################## 3D DEPTH LAYER" -ForegroundColor DarkMagenta
Write-Host ""
Write-Host "T  BOOT SEQUENCE" -ForegroundColor Magenta
Write-Host "|" -ForegroundColor DarkMagenta
Write-Host "o  Shell session detected" -ForegroundColor Green
Write-Host "|" -ForegroundColor DarkMagenta
Write-Host "o  Configuration loaded" -ForegroundColor Green
Write-Host "|" -ForegroundColor DarkMagenta
Write-Host "o  Environment online" -ForegroundColor Green
Write-Host ""
Write-Host "OSMIUM CORE [====================] 100%" -ForegroundColor Magenta
Write-Host ""
