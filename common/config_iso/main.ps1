#@formatter:off
$errorLog = "$env:SystemDrive\main.ps1.error.log"
$ErrorActionPreference = "Continue"

$CONFIGDRIVE = "{{config_drive}}"
$DONE_FILE = "$env:SystemDrive\ansible-win-setup-done-list-file.log"
$ONE_INSTANCE_LOCKFILE_PATH = "$env:TEMP\mainps1.lock"


function Main() {
    $ONE_INSTANCE_LOCKFILE = OneInstance($ONE_INSTANCE_LOCKFILE_PATH)

    $main_ps1_autostart = [PSCustomObject]@{
        name        = "start.ps1"
        sourceDir   = "$CONFIGDRIVE"
        autoStart   = $True
        interpreter = "powershell.exe -NoExit -ExecutionPolicy Bypass -File"
        destination = "$CONFIGDRIVE"
    }
    try {
        Get-ItemProperty -Path "HKLM:\Software\Microsoft\Windows\CurrentVersion\Run" `
            -Name "start.ps1" > $null
    }
    catch {
        # NOTE: Win7 SP1 installation forces reboot disregarding "/norestart" option
        # https://social.technet.microsoft.com/Forums/ie/en-US/c4b7c3fc-037c-4e45-ab11-f6f64837521a/how-to-disable-reboot-after-sp1-installation-distribution-as-exe-via-sccm?forum=w7itproinstall
        # It should continue installing after reboot skiping installed packages
        _AutoStart($main_ps1_autostart)
    }

    $installJson = Get-Content "${CONFIGDRIVE}\install.json"
    $installItems = GetInstallItems($installJson)
    DispatchInstallItems($installItems)

    Enable-WinRM

    CleanUp $ONE_INSTANCE_LOCKFILE $main_ps1_autostart
    Stop-Computer -Force
    shutdown /s /t 0
}


function OneInstance($path) {
    # It will start second time after first user login by autostart.
    try {
        return [System.IO.File]::Open($path, 'Create', 'Write')
    }
    catch {
        Write-Error "Only one instance of main.ps1 is allowed"
        exit
    }
}

function GetInstallItems($json) {
    return [JSON]::Sort([JSON]::Deserialize($json))
}

function IsItemDone($item) {
    return $doneLog -contains $item.id
}

function MarkItemDone($item) {
    $doneLog += "$( $item.id )`n"
    Add-Content -Path $DONE_FILE -Value "$( $item.id )`n"
}


function DispatchInstallItems($items) {
    foreach ($item in $items) {
        if (!(IsItemDone($item))) {
            DispatchItem($item)
            MarkItemDone($item)
            if ($item.restart) {
                RestartComputer
            }
        }

    }
}


$handlers = @{
    "file"      = { param($item) _InstallFile($item.file) }
    "package"   = { param($item) _InstallPackage($item.package) }
    "zip"       = { param($item) _Zip($item.zip) }
    "copy"      = { param($item) _Copy($item.copy) }
    "cmd"       = { param($item) _RunCMD($item.cmd) }
    "registry"  = { param($item) _SetRegistry($item.registry) }
    "addToPath" = { param($item) _AddToPath($item.path) }
}

function DispatchItem($item) {
    if (-not $item.type) {
        throw "Item missing required type property"
    }
    $handler = $handlers[$item.type]
    if (-not $handler) {
        throw "No handler for $( $item.type )"
    }
    try {
        & $handler $item
    }
    catch {
        Write-Error "Failed to dispatch $($item.type): $_"
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


Function Wait-Process($name) {
    Do {
        Start-Sleep 2
        $instanceCount = (Get-Process | Where-Object {
                $_.Name -eq $name
            } | Measure-Object).Count
    } while ($instanceCount -gt 0)
}


Function _AddToPath([string]$path) {
    $path = _ExpandString($path);
    $_path = [Environment]::GetEnvironmentVariable('PATH', 'Machine')
    [Environment]::SetEnvironmentVariable('PATH', "$_path;$path", 'Machine')
}


function Get-Ext($path) {
    $path.split(".")[-1];
}

function MakeDirectoryParents($path) {
    if (Test-Path $path) {
        return
    }
    New-Item -Force -ItemType File -Path "$path\file"
    Remove-Item -Force -Path "$path\file"
}

Function _ExpandString($str) {
    # Interpolate strings in install.json: "$INSTALLDIR", "$env:..."
    return $ExecutionContext.InvokeCommand.ExpandString($str) 
}


$packageHandlers = @{
    "msi" = { param($pkg) _InstallMsi $pkg }
    "exe" = { param($pkg) _InstallExe $pkg }
    "msu" = { param($pkg) _InstallWusa $pkg }
    "cab" = { param($pkg) _InstallDism $pkg }
}

function _InstallPackage($pkg) {

    $ext = Get-FileExtension $pkg.path

    $handler = $packageHandlers[$ext]
    if (-not $handler) {
        throw "No handler for .$ext packages"
    }

    try {
        & $handler $pkg
    }
    catch {
        Write-Error "Failed to install package: $_"
    }

}



Function _SetRegistry($item) {
    if (!$item.state) {
        return;
    }
    $path = _ExpandString($item.path)
    $value = $item.value
    if ($item.state -eq "present") {
        New-Item -Force:$item.force  -Path $path -Value $value -ItemType $item.type
        return
    }
    if ($item.state -eq "property") {
        New-ItemProperty -Force:$item.force -Path $path -Value $value -ItemType $item.type
        return
    }
    if ($item.state -eq "absent") {
        Remove-Item -Recurse:$item.recurse -Path $path
        return
    }
}

Function _InstallFile($file) {
    if (!$file.state) {
        return;
    }
    $path = _ExpandString($file.path)
    if ($file.state -eq "directory") {
        Write-Host -ForegroundColor DarkGreen  "Creating a path: $path"
        if ($file.parents) {
            MakeDirectoryParents($path)
        }
        else {
            New-Item -Force:$item.force -ItemType Directory -Path $path
        }
        return
    }
    if ($file.state -eq "touch") {
        New-Item -Force:$item.force -Path $path
        return
    }
    if ($file.state -eq "present") {
        New-Item -Force:$item.force  -Path $path -Value $file.$value
        return
    }
    if ($file.state -eq "absent") {
        Remove-Item -Recurse:$item.recurse -Path $path
        return
    }

}
Function _Copy($item) {
    if ($item.src -eq $item.dest) {
        return
    }
    $item.src = _ExpandString($item.src)
    $item.dest = _ExpandString($item.dest)
    Write-Host -ForegroundColor DarkGreen  "Copying: " $item.src " to " $item.dest
    Copy-Item -Force:$item.force -Path $item.src -Destination $item.dest
}
function _InstallExe($pkg) {
    Write-Host -ForegroundColor DarkGreen  "Running: " $pkg.path
    Start-Process $pkg.path -Wait -ArgumentList $pkg.args
}
function _InstallMsi($pkg) {
    Write-Host -ForegroundColor DarkGreen  "Installing: " $pkg.path
    Start-Process msiexec.exe -Wait -ArgumentList  "/I $( $pkg.path ) $( $pkg.args )"
}
function _InstallWusa($pkg) {
    Write-Host -ForegroundColor DarkGreen  "Installing updates (wusa): $( $pkg.path )"
    Wait-Process -name wusa
    Start-Process wusa.exe -Wait -ArgumentList "$( $pkg.path ) $( $pkg.args )"
    Wait-Process -name wusa
}
function _InstallDism($pkg) {
    Write-Host -ForegroundColor DarkGreen  "Installing updates (dism): $( $pkg.path )"
    Wait-Process -name dism
    Start-Process dism.exe -Wait -ArgumentList "/Online /Add-Package /PackagePath: $( $pkg.path ) $( $pkg.args )"
    Wait-Process -name dism
}

function _unzip([string]$path, [string]$dest) {
    $shell = New-Object -ComObject Shell.Application
    $zip_src = $shell.NameSpace($path)
    if (!$zip_src) {
        throw "Cannot find file: $path"
    }
    $zip_dest = $shell.NameSpace($dest)
    $zip_dest.CopyHere($zip_src.Items(), 1044)
}
function _Zip($zip) {
    $zip.path = _ExpandString($zip.path)
    $zip.dest = _ExpandString($zip.dest)
    if (-Not$zip.dest) {
        return
    }
    Write-Host -ForegroundColor DarkGreen  "Extracting: $( $zip.path ) to $( $zip.dest )"
    _unzip -path $zip.path -dest $zip.dest
}
# use wisely
function _RunCMD($cmd) {
    $command = _ExpandString($cmd)
    cmd /C $command
}
function AppendToDoneList($item) {
    $item.index | Out-File -Append $DoneList
}

function _AutoStart($item) {
    $entry = $item.name
    $interpreter = $item.interpreter
    $_args = $item.args
    $dest = $item.destination
    $dest = _ExpandString($dest)
    $value = "cmd /C $interpreter `"${dest}\${entry}`" $_args"
    New-ItemProperty -Force -Path "HKLM:\Software\Microsoft\Windows\CurrentVersion\Run" `
        -PropertyType String -Name $item.name -Value $value
}


function Enable-WinRM {
    $networkListManager = [Activator]::CreateInstance(`
            [Type]::GetTypeFromCLSID([Guid]"{DCB00C01-570F-4A9B-8D69-199FDBA5723B}"))
    $connections = $networkListManager.GetNetworkConnections()
    $connections | ForEach-Object {
        $_.GetNetwork().SetCategory(1)
    }
    # Enable-PSRemoting -Force Only works under Administrator account
    # E.g: Start-Process powershell.exe -Credential $Credential
    Enable-PSRemoting -Force
    winrm quickconfig -q

    winrm set winrm/config/client/auth '@{Basic="true"}'
    winrm set winrm/config/service/auth '@{Basic="true"}'
    winrm set winrm/config/service '@{AllowUnencrypted="true"}'
    winrm set winrm/config/winrs '@{MaxMemoryPerShellMB="2048"}'
    Restart-Service -Name WinRM
    netsh advfirewall firewall add rule name = "WinRM-HTTP" dir = in `
        localport = 5985 protocol = TCP action = allow

}


function Enable-RDP() {
    Write-Host -ForegroundColor DarkGreen  "Enabling Remote desktop"
    Set-ItemProperty -Path 'HKLM:\System\CurrentControlSet\Control\Terminal Server'-name "fDenyTSConnections" -Value 0
    Start-Process netsh -ArgumentList "advfirewall firewall set rule group=`"remote desktop`" new enable=yes"
}


function RestartComputer() {
    Restart-Computer -Force
    shutdown /r /t 0
}



function CleanUp($ONE_INSTANCE_LOCKFILE, $main_ps1_autostart) {
    net user administrator /active:no
    Remove-ItemProperty -Force -Path "HKLM:\Software\Microsoft\Windows\CurrentVersion\Run" `
        -Name $main_ps1_autostart.name
    $ONE_INSTANCE_LOCKFILE.Close()
    Remove-Item -Path $ONE_INSTANCE_LOCKFILE.Name -Force
    $ONE_INSTANCE_LOCKFILE.Dispose()
    Remove-Item -Path $DoneList  -Force
}


//TODO
function LogError {
    param($e)
    $errTime = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $errMessage = "Time: $errTime`n"
    $errMessage += "Exception: $( $e.GetType().FullName )`n"
    $errMessage += "Message: $( $e.Message )`n"
    $errMessage += "StackTrace: $( $e.StackTrace )`n"
    Add-Content -Path $errorLog -Value $errMessage
}


##################################
# Entrypoint
try {
    # Skip already installed packages across reboots
    Write-Output $null >> $DONE_FILE
    $doneLog = Get-Content $DONE_FILE
    Main
}
catch {
    LogError $_
    # Rethrow error to terminate after logging
    throw $_
    Write-Error "Critical error occurred. Terminating."
    exit 1
}
