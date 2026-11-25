<#
  Opens Argo CD (app tree) and the website, copies the Argo CD admin password to the clipboard.
  Usage:  powershell -ExecutionPolicy Bypass -File .\scripts\open-demo.ps1
#>
. "$PSScriptRoot\_lib.ps1"
Write-Step "Demo öffnen"
Open-DemoTabs
Write-Info "Login in Argo CD: Benutzer admin, Passwort mit Strg+V einfügen"
