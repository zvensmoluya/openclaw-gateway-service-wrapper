Option Explicit

Dim shell, fileSystem, repoRoot, trayScriptPath, command, configPath

Set shell = CreateObject("WScript.Shell")
Set fileSystem = CreateObject("Scripting.FileSystemObject")

repoRoot = fileSystem.GetParentFolderName(WScript.ScriptFullName)
trayScriptPath = repoRoot & "\tray-controller.ps1"
command = "powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File """ & trayScriptPath & """"

If WScript.Arguments.Count > 0 Then
  configPath = WScript.Arguments.Item(0)
  If Len(configPath) > 0 Then
    command = command & " -ConfigPath """ & configPath & """"
  End If
End If

shell.Run command, 0, False
