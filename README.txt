OSMIUM updater patch

1. Extract this ZIP.
2. Run PowerShell as your normal user.
3. Execute:
   powershell -ExecutionPolicy Bypass -File .\Add-OsmiumUpdater.ps1

The patch edits D:\OSMIUM-Command-System\Osmium-Commands.ps1.
Then test, commit and push the change:
   . "$env:LOCALAPPDATA\OsmiumTerminal\Osmium-Commands.ps1"
   osmium -h
   git -C D:\OSMIUM-Command-System diff
   git -C D:\OSMIUM-Command-System add Osmium-Commands.ps1
   git -C D:\OSMIUM-Command-System commit -m "Add GitHub updater command"
   git -C D:\OSMIUM-Command-System push

After the change is pushed, `osmium -update` will fetch GitHub, require a clean local tree,
fast-forward only, back up the installed runtime, and copy the banner/command module.
Restart PowerShell after updating.
