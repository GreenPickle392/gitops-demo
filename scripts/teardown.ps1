<#
  Removes everything the demo installed: apps, namespaces, Argo CD (incl. CRDs).
  -ClusterLoeschen also deletes the k3d cluster (only on the k3d path).
  Usage:  powershell -ExecutionPolicy Bypass -File .\scripts\teardown.ps1 [-ClusterLoeschen] [-Force]
#>
param([switch]$ClusterLoeschen, [switch]$Force)
. "$PSScriptRoot\_lib.ps1"

$ctx = (Invoke-Native kubectl @('config', 'current-context')).Out
if (-not $Force) {
    $a = Read-Host "Alles aus Kontext '$ctx' entfernen$(if ($ClusterLoeschen) { ' und den Cluster löschen' })? (j/n)"
    if ($a -notmatch '^[jJyY]') { Write-Info "Abgebrochen."; exit 0 }
}

Write-Step "Demo-App entfernen"
Invoke-Native kubectl @('-n', 'argocd', 'delete', 'application', 'gitops-demo', '--ignore-not-found') | Out-Null
Invoke-Native kubectl @('-n', 'argocd', 'delete', 'application', 'demo-app', '--ignore-not-found') | Out-Null
Invoke-Native kubectl @('delete', 'namespace', 'demo', 'demo-prepull', '--ignore-not-found', '--timeout=120s') | Out-Null
Write-Ok "Namespace demo entfernt"

Write-Step "Argo CD entfernen"
$h = Invoke-Native helm @('status', 'argocd', '-n', 'argocd')
if ($h.Code -eq 0) { Invoke-Native helm @('uninstall', 'argocd', '-n', 'argocd', '--wait') | Out-Null }
Invoke-Native kubectl @('delete', 'namespace', 'argocd', '--ignore-not-found', '--timeout=180s') | Out-Null
Invoke-Native kubectl @('delete', 'crd', 'applications.argoproj.io', 'applicationsets.argoproj.io',
    'appprojects.argoproj.io', '--ignore-not-found') | Out-Null
Write-Ok "Argo CD entfernt"

if ($ClusterLoeschen) {
    Write-Step "Cluster löschen"
    if ($ctx -like 'k3d-*' -and (Test-Tool 'k3d')) {
        $name = $ctx.Substring(4)
        $r = Invoke-Native k3d @('cluster', 'delete', $name)
        if ($r.Code -eq 0) { Write-Ok "k3d-Cluster '$name' gelöscht" } else { Write-Bad "k3d-Fehler:`n$($r.Out)" }
    } else {
        Write-Info "Kontext '$ctx' ist kein k3d-Cluster – den lösche ich nicht (z. B. Rancher Desktop: dort 'Reset Kubernetes')."
    }
}
Write-Host ""
Write-Host "Aufgeräumt." -ForegroundColor Green
