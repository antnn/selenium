param (
    [Parameter(Mandatory = $false, Position = 0, ValueFromPipeline = $false)]
    [System.String]
    $UnZip,

    [Parameter(Mandatory = $false, Position = 1, ValueFromPipeline = $false)]
    [System.String]
    $Dest,

    [Parameter(Mandatory = $false, Position = 2, ValueFromPipeline = $false)]
    [System.String]
    $Msu
)
$ErrorActionPreference = "Stop"
$CONFIGDRIVE = "D:"
$INSTALLDIR = "${CONFIGDRIVE}\toinstall"
$INSTALL_LOG = "$env:SystemDrive\main_script_installed.log"
$LockFile = "$env:TEMP\mainps1.lock"

function Main() {
    $main_autostart = [PSCustomObject]@{
        name        = "start.ps1"
        sourceDir   = "$CONFIGDRIVE"
        autoStart   = $True
        interpreter = "powershell.exe -ExecutionPolicy Bypass -File"
        destination = "$CONFIGDRIVE"
    }
    $FileStream = $null # race condition between FirstLogonCommands and autostart
    try {
        $FileStream = [System.IO.File]::Open($LockFile, 'Create', 'Write')
    }
    catch {
        exit
    }

    try {
        Get-ItemProperty -Path "HKLM:\Software\Microsoft\Windows\CurrentVersion\Run" `
            -Name "start.ps1" > $null
    }
    catch {
        # run once
        reg add "HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update" /v AUOptions /t REG_DWORD /d 1 /f
        reg add "HKEY_CURRENT_USER\Software\Microsoft\Windows\CurrentVersion\Explorer\ControlPanel" /v StartupPage /t REG_DWORD /d 1 /f
        reg add "HKEY_CURRENT_USER\Software\Microsoft\Windows\CurrentVersion\Explorer\ControlPanel" /v AllItemsIconView /t REG_DWORD /d 0 /f
        Start-Process wmic -ArgumentList 'useraccount where name="IEUser" set PasswordExpires=false'
        Enable-RDP
        Enable-WinRM # for Ansible

        # SP1 installation forces reboot (BUG) add to autostart itself
        _AutoStart($main_autostart)
    }

    $installJson = Get-Content "${CONFIGDRIVE}\install.json"
    # Pass JSON array [{....}] Deserialize<object[]>
    $installJson = [JSON]::Sort([JSON]::Deserialize($installJson))
    foreach ($item in $installJson) {
        $_test = IsInstalled($item)
        if (-Not $_test) {
            _dispatch($item)
            AlreadyInstalledWrite($item)
            if ($item.restart) {
                Restart-Computer -Force
                shutdown /r /t 0
            }
        }
    }


    CleanUp $FileStream $LockFile $main_autostart
    Stop-Computer -Force
    shutdown /s /t 0
}

function CleanUp ($FileStream, $LockFile, $main_autostart) {
    net user administrator /active:no
    Remove-ItemProperty -Force -Path "HKLM:\Software\Microsoft\Windows\CurrentVersion\Run" `
        -Name $main_autostart.name
    $FileStream.Close()
    $FileStream.Dispose()
    Remove-Item -Path $LockFile -Force

}
function _dispatch($item) {
    if ($item.win_pass) {
        return #WinPE
    }
    $ext = Get-ext($item)
    if ( $ext -eq "msi") {
        _Msi($item)
    }
    if ( $ext -eq "exe") {
        _Exe($item)
    }
    if ( $ext -eq "msu") {
        _Wusa($item)
    }
    if ( $ext -eq "cab") {
        _Dism($item)
    }
    if ( $ext -eq "zip") {
        _Zip($item)
    }
    if ($item.sourceDir.length -gt 0) {
        _Copy($item)
    }
    if ($item.autoStart) {
        _AutoStart($item)
    }
    if ($item.addToPath) {
        _AddToPath($item)
    }
    if ($item.cmd) {
        _CMD($item)
    }
}


$code = @"
using System;
using System.Collections.Generic;
using _JSON=System.Web.Script.Serialization.JavaScriptSerializer; // keep FullName, otherwise - undefined reference
using Dict = System.Collections.Generic.Dictionary<string, object>;
public class JSON
{
    public static object[] Deserialize(string data)
    {
        _JSON serializer = new _JSON();
        return serializer.Deserialize<object[]>(data);
    }
    public static string Serialize(object[] data)
    {
        _JSON serializer = new _JSON();
        return serializer.Serialize(data);
    }
    public static object[] Sort(object[] array)
    {
        IComparer<Object> jsonComparer = new JSONComparer();
        Array.Sort(array, jsonComparer);
        return array;
    }

}
public class JSONComparer : IComparer<object>
{
    public int Compare(object a, object b)
    {
        Int32 _a = (Int32)((Dict)a)["index"];
        Int32 _b = (Int32)((Dict)b)["index"];
        return (_a.CompareTo(_b));
    }
}
"@
#[System.Reflection.Assembly]::LoadWithPartialName("System.Web.Extensions") .FullName
$scriptAssembly = "System.Web.Extensions, Version=3.5.0.0, Culture=neutral, PublicKeyToken=31bf3856ad364e35"
Add-Type -ReferencedAssemblies $scriptAssembly -TypeDefinition $code -Language CSharp


Function _unzip([string]$file, [string]$destination) {
    mkdir_-p($destination)
    $shell = New-Object -ComObject Shell.Application
    $zip_src = $shell.NameSpace($file)
    if (!$zip_src) {
        throw "Cannot find file: $file"
    }
    $zip_dest = $shell.NameSpace($destination)
    $zip_dest.CopyHere($zip_src.Items(), 1044)
}
Function Wait-Process($name) {
    Do {
        Start-Sleep 2
        $instanceCount = (Get-Process | Where-Object { $_.Name -eq $name } | Measure-Object).Count
    } while ($instanceCount -gt 0)
}


Function Add-ToPath ([string]$path) {
    $old = (Get-ItemProperty -Path 'HKLM:\System\CurrentControlSet\Control\Session Manager\Environment' -Name path).path
    $new = "$old;$path"
    Set-ItemProperty -Path 'HKLM:\System\CurrentControlSet\Control\Session Manager\Environment' -Name path -Value $new
}

Function Add-ToStartup([string]$name, [string]$value) {
    New-ItemProperty -Force -Path "HKLM:\Software\Microsoft\Windows\CurrentVersion\Run" `
        -PropertyType String -Name $name -Value $value
}

function Enable-RDP() {
    Write-Host -ForegroundColor DarkGreen  "Enabling Remote desktop"
    Set-ItemProperty -Path 'HKLM:\System\CurrentControlSet\Control\Terminal Server'-name "fDenyTSConnections" -Value 0
    Start-Process netsh -ArgumentList "advfirewall firewall set rule group=`"remote desktop`" new enable=yes"
}

function Get-Ext($item) {
    $item.name.split(".")[-1];
}

function mkdir_-p($dest) {
    if (Test-Path $dest) {
        return
    }
    Write-Host -ForegroundColor DarkGreen  "Creating path: $dest"
    New-Item -Force -ItemType File -Path "$dest\file"
    Remove-Item -Force -Path "$dest\file"
}
Function _ExpandString($str) {
    return $ExecutionContext.InvokeCommand.ExpandString($str) # Interpolate strings in install.json: "$INSTALLDIR", "$env:..."
}
Function _Copy($item) {
    if ($item.sourceDir -eq $item.destination) { return }
    $name = $item.name
    Write-Host -ForegroundColor DarkGreen  "Copying: $name"
    $s = $item.sourceDir;
    $d = $item.destination
    $s = _ExpandString("$s\$name");
    $d = _ExpandString("$d");
    #mkdir_-p($d)
    Copy-Item -Force -Path $s -Destination $d
}
function _Exe($item) {
    if ($item.destination) {
        # Installed by simply Copying
        return
    }
    $path = $item.name
    Write-Host -ForegroundColor DarkGreen  "Running: $path"
    $path = "$INSTALLDIR\$path"
    $_args = $item.args
    Start-Process $path -Wait -ArgumentList " $_args"
}
function _Msi($item) {
    $path = $item.name
    Write-Host -ForegroundColor DarkGreen  "Installing: $path"
    $path = "$INSTALLDIR\$path"
    $_args = $item.args
    Start-Process msiexec.exe -Wait -ArgumentList "/I $path $_args"
}
function wusaf($path) {
    Write-Host -ForegroundColor DarkGreen  "Installing updates: $path"
    Wait-Process -name wusa
    Start-Process wusa.exe -Wait -ArgumentList " $path /quiet /NoRestart"
    Wait-Process -name wusa
}
function _Wusa($pkg) {
    $path = $pkg.name
    $path = "$INSTALLDIR\$path"
    wusaf($path)
}
function dismf($path) {
    Write-Host -ForegroundColor DarkGreen  "Installing updates: $path"
    Wait-Process -name dism
    Start-Process dism.exe -Wait -ArgumentList "/Online /Add-Package /PackagePath:$path /NoRestart"
    Wait-Process -name dism
}
function _Dism($pkg) {
    $path = $pkg.name
    #$pkg = $pkg.split(" ") -join ' /PackagePath:'
    $path = "$INSTALLDIR\$path"
    dismf($path)
}

function _AutoStart($item) {
    if ($item.start) {
        $entry = $item.start
    }
    else {
        $entry = $item.name
    }
    $interpreter = $item.interpreter
    $_args = $item.args
    $dest = $item.destination
    $dest = _ExpandString($dest)
    Add-ToStartup -name $entry -value "cmd /C $interpreter `"${dest}\${entry}`" $_args"
}
function _AddToPath($item) {
    $p = $item.destination;
    $p = _ExpandString($p);
    Add-ToPath -Path $p
}
function _Zip($item) {
    $path = $item.name
    $dest = $item.destination
    if (-Not $dest) {
        return
    }
    $path = "$INSTALLDIR\$path"
    $dest = _ExpandString($dest)
    Write-Host -ForegroundColor DarkGreen  "Extracting: $path"
    #mkdir_-p($dest)
    _unzip -file $path -destination $dest
}
# use wisely
function _CMD($item) {
    $command = _ExpandString($item.cmd)
    cmd /C $command
}
function AlreadyInstalledWrite($item) {
    $item.name | Out-File -Append $INSTALL_LOG
}

function IsInstalled($item) {
    return [bool] ($_installed -match $item.name)
}

function Enable-WinRM {
    $networkListManager = [Activator]::CreateInstance(`
        [Type]::GetTypeFromCLSID([Guid]"{DCB00C01-570F-4A9B-8D69-199FDBA5723B}"))
    $connections = $networkListManager.GetNetworkConnections()
    $connections | ForEach-Object {
        $_.GetNetwork().SetCategory(1)
    }

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

##################################
# Entrypoint

if ($UnZip) {
    _unzip $UnZip $Dest
    exit
}
if ($msu) {
    wusaf($msu)
    exit
}

# Skip already installed packages
Write-Output $null >> $INSTALL_LOG
$_installed = Get-Content $INSTALL_LOG
Main



