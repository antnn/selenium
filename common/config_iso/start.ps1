function Start-App() {
    if (-not (Test-Administrator)) {
        Start-ElevatedProcess
        exit
    }
  
    $MainCodeFile = "C:\Users\Virt\Desktop\auto.cs";
    $sourceCode = [System.IO.File]::ReadAllText($MainCodeFile)
    $scriptAssembly = "System.Web.Extensions, Version=3.5.0.0, Culture=neutral, PublicKeyToken=31bf3856ad364e35"
    Add-Type -ReferencedAssemblies $scriptAssembly -TypeDefinition $sourceCode -Language CSharp
    [WinImageBuilderAutomation]::Run()
    Enable-RemoteManagement
}

function Test-Administrator {
    $currentUser = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
    $isAdmin = $currentUser.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    return $isAdmin
}

function Start-ElevatedProcess() {
    Set-Location D:\
    # Set the username and password for the admin account
    $User = "\Administrator"
    $PWord = ConvertTo-SecureString -String "Passw0rd!" -AsPlainText -Force
    $adminCredential = New-Object -TypeName System.Management.Automation.PSCredential -ArgumentList $User, $PWord
    # Restart the PowerShell process with admin credentials and execute main.ps1
    Start-Process powershell.exe -Credential $adminCredential -ArgumentList "-ExecutionPolicy Bypass ./start.ps1"
}

function Enable-RemoteManagement {
    [WinImageBuilderAutomation]::SetNetworksLocationToPrivate()
    Enable-PSRemoting -Force
    winrm quickconfig -q

    winrm set winrm/config/client/auth '@{Basic="true"}'
    winrm set winrm/config/service/auth '@{Basic="true"}'
    winrm set winrm/config/service '@{AllowUnencrypted="true"}'
    winrm set winrm/config/winrs '@{MaxMemoryPerShellMB="2048"}'
    Restart-Service -Name WinRM
    netsh advfirewall firewall add rule name="WinRM-HTTP" dir=in `
        localport=5985 protocol=TCP action=allow

}

Start-App
