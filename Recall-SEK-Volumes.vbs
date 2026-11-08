' Launches the PowerShell Apply script completely hidden.
' Suitable for Bome MIDI Translator Pro > Outgoing > Execute File.
' The PowerShell script writes a log to the Logs folder.
Option Explicit
Dim shell, fs, folder, ps, scriptFile, command
Set shell = CreateObject("WScript.Shell")
Set fs = CreateObject("Scripting.FileSystemObject")
folder = fs.GetParentFolderName(WScript.ScriptFullName)
ps = shell.ExpandEnvironmentStrings("%SystemRoot%") & "\System32\WindowsPowerShell\v1.0\powershell.exe"
scriptFile = folder & "\SEK-Volumes.ps1"
command = Chr(34) & ps & Chr(34) & " -NoProfile -NonInteractive -ExecutionPolicy Bypass -File " & Chr(34) & scriptFile & Chr(34) & " -Mode Apply -TrustLocalCertificate"
shell.Run command, 0, False
