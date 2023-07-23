drvload D:\drivers\netkvm.inf
wmic nic get ConnectionID
wpeinit
netsh interface ipv4 set address name=”Local Area Connection” source=dhcp

D:\promtail.exe

