<#
  Restores the initial values.yaml, commits + pushes, waits until Argo CD has rolled it out.
  -OhneApp additionally removes the demo app, so step 1 (bootstrap with setup.ps1) can be shown live.
  Usage:  powershell -ExecutionPolicy Bypass -File .\scripts\reset.ps1 [-OhneApp]
#>
param([switch]$OhneApp)
. "$PSScriptRoot\_lib.ps1"

function Git-Run([string[]]$GitArgs) {
    $r = Invoke-Native git $GitArgs
    if ($r.Code -ne 0) { Stop-Demo "git $($GitArgs -join ' ') fehlgeschlagen:`n$($r.Out)" }
    $r.Out
}

Write-Step "values.yaml auf Startzustand zurücksetzen"
Push-Location $RepoRoot
try {
    Git-Run @('checkout', '--', 'chart/values.yaml') | Out-Null       # drop unsaved local edits
    Git-Run @('pull', '--ff-only', '--quiet') | Out-Null
    Copy-Item 'scripts\values.start.yaml' 'chart\values.yaml' -Force
    $changed = (Invoke-Native git @('status', '--porcelain', 'chart/values.yaml')).Out
    if ($changed) {
        Git-Run @('add', 'chart/values.yaml') | Out-Null
        Git-Run @('commit', '-m', 'Demo zurückgesetzt (reset.ps1)', '--quiet') | Out-Null
        Git-Run @('push', '--quiet') | Out-Null
        Write-Ok "Startzustand committet und gepusht"
    } else {
        Write-Ok "values.yaml war schon im Startzustand"
    }
    $rev = Git-Run @('rev-parse', 'HEAD')
} finally { Pop-Location }

if (-not (Get-AppStatus 'demo-app')) {
    Write-Info "Demo-App ist nicht ausgerollt – fertig. (Ausrollen: setup.ps1)"
    exit 0
}

Write-Step "Warten, bis Argo CD den Startzustand ausgerollt hat"
Request-AppRefresh 'gitops-demo'; Request-AppRefresh 'demo-app'
if (-not (Wait-App 'demo-app' -TimeoutSec 180 -Revision $rev)) { Stop-Demo "demo-app ist nach 3 Minuten nicht auf Stand $($rev.Substring(0,7))" }
$r = Invoke-Native kubectl @('-n', 'demo', 'rollout', 'status', 'deployment/demo-app', '--timeout=120s')
if ($r.Code -ne 0) { Stop-Demo "Rollout hängt:`n$($r.Out)" }
Write-Ok "Cluster läuft mit Stand $($rev.Substring(0,7)) – Synced / Healthy"

if ($OhneApp) {
    Write-Step "Demo-App entfernen (für den Live-Bootstrap)"
    # Root app first, otherwise it would immediately recreate demo-app.
    Kube -n argocd delete application gitops-demo --ignore-not-found | Out-Null
    Kube -n argocd delete application demo-app --ignore-not-found | Out-Null
    Kube delete namespace demo --ignore-not-found --timeout=120s | Out-Null
    Write-Ok "Demo-App entfernt. Argo CD läuft weiter. Live-Bootstrap: .\scripts\setup.ps1"
}
Write-Host ""
Write-Host "Bereit für die nächste Runde." -ForegroundColor Green
