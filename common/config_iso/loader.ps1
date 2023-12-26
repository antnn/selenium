$MAIN_CLASS = "C:\Users\Virt\Desktop\auto.cs";
$code = [System.IO.File]::ReadAllText($MAIN_CLASS)
$scriptAssembly = "System.Web.Extensions, Version=3.5.0.0, Culture=neutral, PublicKeyToken=31bf3856ad364e35"
Add-Type -ReferencedAssemblies $scriptAssembly -TypeDefinition $code -Language CSharp
