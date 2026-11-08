' Hidden SAVE launcher for Bome Execute File; saves current base-station-stored volumes.
Option Explicit
Dim shell, fs, folder, ps, scriptFile, command
Set shell = CreateObject("WScript.Shell")
Set fs = CreateObject("Scripting.FileSystemObject")
folder = fs.GetParentFolderName(WScript.ScriptFullName)
ps = shell.ExpandEnvironmentStrings("%SystemRoot%") & "\System32\WindowsPowerShell\v1.0\powershell.exe"
scriptFile = folder & "\SEK-Volumes.ps1"
command = Chr(34) & ps & Chr(34) & " -NoProfile -NonInteractive -ExecutionPolicy Bypass -File " & Chr(34) & scriptFile & Chr(34) & " -Mode Save -TrustLocalCertificate"
shell.Run command, 0, False
