Option Explicit

Dim fso, shell, root, scriptPath, powershellPath, command, waitForExit
Dim exitCode, index, argument

Set fso = CreateObject("Scripting.FileSystemObject")
Set shell = CreateObject("WScript.Shell")

root = fso.GetParentFolderName(WScript.ScriptFullName)
scriptPath = fso.BuildPath(root, "FreeSignal.ps1")

If Not fso.FileExists(scriptPath) Then
    MsgBox "FreeSignal.ps1 was not found next to the launcher." & vbCrLf & vbCrLf & scriptPath, vbCritical, "FreeSignal"
    WScript.Quit 2
End If

powershellPath = shell.ExpandEnvironmentStrings("%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe")
If Not fso.FileExists(powershellPath) Then
    powershellPath = "powershell.exe"
End If

command = QuoteArgument(powershellPath) & _
    " -NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -STA -File " & _
    QuoteArgument(scriptPath)
waitForExit = False

For index = 0 To WScript.Arguments.Count - 1
    argument = LCase(CStr(WScript.Arguments(index)))
    Select Case argument
        Case "--self-test", "-selftest", "/selftest"
            command = command & " -SelfTest"
            waitForExit = True
        Case "--safe-mode", "-safemode", "/safemode"
            command = command & " -SafeMode"
            waitForExit = True
        Case "--emergency", "-emergency", "/emergency"
            command = command & " -SafeMode -Emergency"
            waitForExit = True
        Case "--auto-start", "-autostart", "/autostart"
            command = command & " -AutoStart"
        Case Else
            MsgBox "Unsupported FreeSignal launcher argument:" & vbCrLf & CStr(WScript.Arguments(index)), vbExclamation, "FreeSignal"
            WScript.Quit 2
    End Select
Next

On Error Resume Next
exitCode = shell.Run(command, 0, waitForExit)
If Err.Number <> 0 Then
    MsgBox "FreeSignal could not launch Windows PowerShell." & vbCrLf & vbCrLf & _
        "Error " & CStr(Err.Number) & ": " & Err.Description, vbCritical, "FreeSignal"
    WScript.Quit 1
End If
On Error GoTo 0

If waitForExit Then
    WScript.Quit exitCode
End If

Function QuoteArgument(ByVal value)
    QuoteArgument = Chr(34) & Replace(CStr(value), Chr(34), Chr(34) & Chr(34)) & Chr(34)
End Function
