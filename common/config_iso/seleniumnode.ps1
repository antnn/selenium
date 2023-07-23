$ErrorActionPreference = "Stop"
Function Get-SelenimParams(){
    $namespace = 'root\CIMV2'
    $obj= Get-WmiObject -class Win32_Bios -computername 'LocalHost' -namespace $namespace
    $split=$obj.SerialNumber.split('_')
    $ret=New-Object -TypeName PSObject | Select-Object ip, port, hub
    $ret.ip=$split[0]
    $ret.port=$split[1]
    $ret.hub=$split[2]
    if (!$ret.ip.Length -or !$ret.port.Length) {
        throw "Error: Cannot get External (Qemu host) IP address or Port"
    }
    return $ret
}

Function Wait-Net($Comp) {
    Write-Host -ForegroundColor Yellow "Waiting for network to become online"
    do {
        try {
            $ping = test-connection -comp $Comp -count 1 -Quiet
        }
        catch {
        }
    } until ($ping)
    Write-Host -ForegroundColor Yellow  "Connected"
}
$e=$(Get-SelenimParams)
$ip=$e.ip
$port=$e.port
$hub=$e.hub

#Wait-Net -Comp 1.1.1.1 # bug with IPv6
Write-Host "Checking network"
Wait-Net -Comp $hub
#Start-Transcript -Force -Path $env:USERPROFILE\Desktop\seleniumnodelog.txt
$java="$env:JAVA_HOME\bin\java.exe"
$path = "$env:ProgramFiles\Selenium\selenium-server.jar"
#$hub = "selenium-hub.grid"


Start-Process $java -ArgumentList "-jar `"$path`" node --bind-host false --host $ip --port $port --hub $hub"



