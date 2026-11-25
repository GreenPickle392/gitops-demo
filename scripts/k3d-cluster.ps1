<#
  OPTIONAL, only for the Docker Desktop + k3d path: creates a local k3s cluster with Traefik on port 80.
  Usage:  powershell -ExecutionPolicy Bypass -File .\scripts\k3d-cluster.ps1 [-Port 8088]
  (If you use a port other than 80, set $env:DEMO_PORT to the same value before the other scripts.)
#>
param([string]$Name = 'gitops-demo', [int]$Port = 80)
. "$PSScriptRoot\_lib.ps1"

Write-Step "k3d-Cluster '$Name' anlegen"
if (-not (Test-Tool 'k3d')) { Stop-Demo "k3d fehlt: winget install k3d.k3d" }
if ((Invoke-Native docker @('info')).Code -ne 0) { Stop-Demo "Docker läuft nicht – Docker Desktop starten und kurz warten." }

$list = (Invoke-Native k3d @('cluster', 'list', '--no-headers')).Out
if ($list -match "(?m)^$([regex]::Escape($Name))\s") {
    Write-Ok "Cluster '$Name' gibt es schon"
    Invoke-Native k3d @('cluster', 'start', $Name) | Out-Null
} else {
    $busy = Get-NetTCPConnection -State Listen -LocalPort $Port -ErrorAction SilentlyContinue
    if ($busy) { Stop-Demo "Port $Port ist belegt (PID $($busy[0].OwningProcess)). Nimm z. B. -Port 8088 und setze `$env:DEMO_PORT = 8088." }
    $r = Invoke-Native k3d @('cluster', 'create', $Name, '-p', "$($Port):80@loadbalancer", '--wait')
    if ($r.Code -ne 0) { Stop-Demo "k3d-Fehler:`n$($r.Out)" }
    Write-Ok "Cluster '$Name' angelegt (Traefik auf Port $Port)"
}
Invoke-Native kubectl @('config', 'use-context', "k3d-$Name") | Out-Null
Write-Ok "Kube-Kontext: k3d-$Name"
if ($Port -ne 80) { Write-Info "Wichtig: `$env:DEMO_PORT = $Port setzen, URLs dann z. B. http://demo.localhost:$Port" }
Write-Info "Weiter mit: .\scripts\setup.ps1"
