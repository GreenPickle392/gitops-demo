<#
  Builds the complete demo with one command (idempotent, can be re-run any time):
  preflight -> Argo CD via Helm -> pre-pull images -> root app (App of Apps) -> wait -> open browser.
  Usage:  powershell -ExecutionPolicy Bypass -File .\scripts\setup.ps1 [-NoBrowser]
#>
param([switch]$NoBrowser)
. "$PSScriptRoot\_lib.ps1"
$total = [Diagnostics.Stopwatch]::StartNew()

Write-Host ""
Write-Host "GitOps-Demo – Aufbau" -ForegroundColor White

# --- 1. Preflight ------------------------------------------------------------
Write-Step "Vorabprüfung"
foreach ($t in 'kubectl', 'helm', 'git', 'curl.exe') {
    if (Test-Tool $t) { Write-Ok "$t gefunden" } else { Stop-Demo "$t fehlt – siehe docs/Anleitung.md, Abschnitt 3" }
}
$ctx = Invoke-Native kubectl @('config', 'current-context')
if ($ctx.Code -ne 0) { Stop-Demo "Kein Kube-Kontext gesetzt. Läuft dein Cluster?" }
Write-Ok "Kube-Kontext: $($ctx.Out)"
$nodes = Invoke-Native kubectl @('get', 'nodes', '--no-headers')
if ($nodes.Code -ne 0) { Stop-Demo "Cluster nicht erreichbar: $($nodes.Out)" }
Write-Ok "Cluster erreichbar ($(@($nodes.Out -split "`n").Count) Node(s))"
$ic = Invoke-Native kubectl @('get', 'ingressclass', 'traefik')
if ($ic.Code -ne 0) { Stop-Demo "Keine IngressClass 'traefik' gefunden – die Demo braucht Traefik als Ingress." }
Write-Ok "Traefik-Ingress vorhanden"

# --- 2. Argo CD --------------------------------------------------------------
Write-Step "Argo CD installieren/aktualisieren (Helm-Chart argo-cd $ArgoChartVersion)"
$helmArgs = @('upgrade', '--install', 'argocd', 'argo-cd',
    '--repo', 'https://argoproj.github.io/argo-helm', '--version', $ArgoChartVersion,
    '--namespace', 'argocd', '--create-namespace',
    '-f', (Join-Path $RepoRoot 'bootstrap\argocd-values.yaml'),
    '--wait', '--timeout', '10m')
$h = Invoke-Native helm $helmArgs
if ($h.Code -ne 0) { Stop-Demo "Helm-Installation fehlgeschlagen:`n$($h.Out)" }
Write-Ok "Argo CD installiert"

Write-Step "Warten, bis Argo CD bereit ist"
$deps = (Kube -n argocd get deploy -o 'jsonpath={.items[*].metadata.name}') -split ' '
foreach ($d in $deps + 'statefulset/argocd-application-controller') {
    $name = if ($d -like '*/*') { $d } else { "deployment/$d" }
    $r = Invoke-Native kubectl @('-n', 'argocd', 'rollout', 'status', $name, '--timeout=300s')
    if ($r.Code -ne 0) { Stop-Demo "$name wird nicht bereit:`n$($r.Out)" }
}
Write-Ok "Alle Argo-CD-Komponenten laufen"

# --- 3. Pre-pull images ------------------------------------------------------
Write-Step "nginx-Images vorab in den Cluster laden (damit live nichts vom WLAN abhängt)"
$cache = Get-CachedImages
$missing = @($Images | Where-Object { -not (Test-ImageCached $_ $cache) })
if ($missing.Count -eq 0) {
    Write-Ok "Images schon vorhanden: $($Images -join ', ')"
} else {
    # A DaemonSet pulls every image on every node; works on any cluster, not only k3d.
    $inits = ($Images | ForEach-Object { $i = [array]::IndexOf($Images, $_)
@"
        - name: pull-$i
          image: $_
          imagePullPolicy: IfNotPresent
          command: ["true"]
"@ }) -join "`n"
    $yaml = @"
apiVersion: v1
kind: Namespace
metadata:
  name: demo-prepull
---
apiVersion: apps/v1
kind: DaemonSet
metadata:
  name: prepull
  namespace: demo-prepull
spec:
  selector:
    matchLabels: { app: prepull }
  template:
    metadata:
      labels: { app: prepull }
    spec:
      terminationGracePeriodSeconds: 0
      initContainers:
$inits
      containers:
        - name: wait
          image: $($Images[0])
          command: ["sleep", "3600"]
"@
    $tmp = Join-Path ([IO.Path]::GetTempPath()) 'gitops-demo-prepull.yaml'
    [IO.File]::WriteAllText($tmp, $yaml)
    Kube apply -f $tmp | Out-Null
    $r = Invoke-Native kubectl @('-n', 'demo-prepull', 'rollout', 'status', 'ds/prepull', '--timeout=300s')
    Invoke-Native kubectl @('delete', 'namespace', 'demo-prepull', '--wait=false') | Out-Null
    Remove-Item $tmp -ErrorAction SilentlyContinue
    if ($r.Code -ne 0) { Write-Bad "Images konnten nicht geladen werden (Internet?). Die Demo läuft trotzdem, aber das Upgrade braucht dann live Netz." }
    else { Write-Ok "Images geladen: $($Images -join ', ')" }
}

# --- 4. Root app -------------------------------------------------------------
Write-Step "Demo per Argo CD ausrollen (App of Apps: gitops-demo -> demo-app)"
Kube apply -f (Join-Path $RepoRoot 'bootstrap\root-app.yaml') | Out-Null
Write-Ok "Root-Application angelegt – ab jetzt arbeitet nur noch Argo CD"
$sw = [Diagnostics.Stopwatch]::StartNew(); $last = ''
while ($true) {
    $root = Get-AppStatus 'gitops-demo'; $app = Get-AppStatus 'demo-app'
    $line = "gitops-demo: $(if ($root) { "$($root.Sync)/$($root.Health)" } else { '…' })   demo-app: $(if ($app) { "$($app.Sync)/$($app.Health)" } else { '…' })"
    if ($line -ne $last) { Write-Info ("{0,3}s  {1}" -f [int]$sw.Elapsed.TotalSeconds, $line); $last = $line }
    if ($root -and $app -and $root.Sync -eq 'Synced' -and $root.Health -eq 'Healthy' -and
        $app.Sync -eq 'Synced' -and $app.Health -eq 'Healthy') { break }
    if ($sw.Elapsed.TotalSeconds -gt 240) { Stop-Demo "Argo CD ist nach 4 Minuten nicht Synced/Healthy. Schau in die Argo-CD-Oberfläche: $ArgoAppUrl" }
    Start-Sleep -Seconds 1
}
Write-Ok "Alles Synced und Healthy"

# --- 5. Website --------------------------------------------------------------
Write-Step "Webseite prüfen"
$ok = $false
for ($i = 0; $i -lt 20 -and -not $ok; $i++) {
    $res = Get-Http "$DemoUrl/"
    $ok = $res.Status -eq '200' -and $res.Body -match 'Live aus dem Kubernetes-Cluster'
    if (-not $ok) { Start-Sleep -Seconds 1 }
}
if ($ok) { Write-Ok "$DemoUrl antwortet" } else { Stop-Demo "$DemoUrl antwortet nicht (Status $($res.Status)). Siehe Fehlerbehebung in docs/Anleitung.md." }

# --- 6. Done -----------------------------------------------------------------
Write-Host ""
Write-Host ("Fertig nach {0:N0} s." -f $total.Elapsed.TotalSeconds) -ForegroundColor Green
Write-Host "  Webseite : $DemoUrl"
Write-Host "  Argo CD  : $ArgoUrl   (Benutzer: admin)"
if ($NoBrowser) {
    $pw = Get-ArgoPassword
    if ($pw) { try { Set-Clipboard -Value $pw; Write-Ok "Argo-CD-Passwort liegt in der Zwischenablage" } catch { } }
} else {
    Open-DemoTabs
}
