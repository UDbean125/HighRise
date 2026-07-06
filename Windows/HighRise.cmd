@echo off
rem HighRise mail merge - double-click launcher.
rem Opens the point-and-click window (HighRise-GUI.ps1) with the right options,
rem so there are no PowerShell commands to type. Keep this file in the same
rem folder as HighRise-GUI.ps1 and HighRise-Merge.ps1.
start "" powershell.exe -NoProfile -ExecutionPolicy Bypass -STA -WindowStyle Hidden -File "%~dp0HighRise-GUI.ps1"
