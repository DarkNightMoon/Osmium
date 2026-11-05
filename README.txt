OSMIUM COMMAND SYSTEM

This keeps the OSMIUM startup logo/boot page and does NOT open system information at startup.

Install:
1. Extract this ZIP.
2. Open PowerShell in the extracted folder.
3. Run:
   powershell.exe -ExecutionPolicy Bypass -File .\Install-Osmium-Command-System.ps1
4. Close and reopen PowerShell.

Commands:
  osmium -h     Help / command index
  osmium -sys   Live system information dashboard
  Ctrl+C        Exit dashboard and return to OSMIUM prompt

The command dashboard refreshes once per second. NVIDIA GPU/VRAM/temperature data requires nvidia-smi.exe.
