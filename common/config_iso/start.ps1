# Note: autounattend.xml also contains setup commands
Set-Location D:\
$User = "\Administrator"
$PWord = ConvertTo-SecureString -String "Passw0rd!" -AsPlainText -Force
$Credential = New-Object -TypeName System.Management.Automation.PSCredential -ArgumentList $User, $PWord
Start-Process powershell.exe -Credential $Credential -ArgumentList "-ExecutionPolicy Bypass ./main.ps1"
