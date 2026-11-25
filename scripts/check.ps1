<#
  Pre-talk checklist. Prints green/red per item, exit code 1 if anything is red.
  Usage:  powershell -ExecutionPolicy Bypass -File .\scripts\check.ps1
#>
. "$PSScriptRoot\_lib.ps1"
$script:fails = 0
function Pass([string]$t) { Write-Ok $t }
function Fail([string]$t) { Write-Bad $t; $script:fails++ }

Write-Host ""
Write-Host "GitOps-Demo – Checkliste vor dem Talk" -ForegroundColor White

Write-Step "Cluster"
$ctx = Invoke-Native kubectl @('config', 'current-context')
if ($ctx.Code -eq 0) { Pass "Kube-Kontext: $($ctx.Out)" } else { Fail "Kein Kube-Kontext gesetzt" }
$nodes = Invoke-Native kubectl @('get', 'nodes', '--no-headers')
if ($nodes.Code -eq 0 -and $nodes.Out -match '\sReady\s' -and $nodes.Out -notmatch 'NotReady') { Pass "Node(s) Ready" }
else { Fail "Cluster nicht erreichbar oder Node nicht Ready – läuft Docker Desktop?" }

Write-Step "Argo CD"
$d = Get-KubeJson -n argocd get 'deploy,statefulset'
if (-not $d -or @($d.items).Count -eq 0) { Fail "Argo CD nicht installiert – setup.ps1 ausführen" }
else {
    $bad = @($d.items | Where-Object { [int]$_.status.readyReplicas -ne [int]$_.spec.replicas } | ForEach-Object { $_.metadata.name })
    if ($bad.Count -eq 0) { Pass "Alle Argo-CD-Komponenten laufen ($(@($d.items).Count) Workloads)" } else { Fail "Nicht bereit: $($bad -join ', ')" }
}
$argo = Get-Http "$ArgoUrl/"
if ($argo.Status -eq '200') { Pass "Oberfläche erreichbar: $ArgoUrl" } else { Fail "$ArgoUrl antwortet nicht (Status $($argo.Status))" }
if (Get-ArgoPassword) { Pass "Admin-Passwort vorhanden (open-demo.ps1 kopiert es)" } else { Fail "Admin-Passwort-Secret fehlt" }

Write-Step "Demo-App"
$root = Get-AppStatus 'gitops-demo'; $app = Get-AppStatus 'demo-app'
if (-not $root -and -not $app) {
    Write-Host "  ○ Demo-App noch nicht ausgerollt – ok, wenn du Schritt 1 (Bootstrap) live mit setup.ps1 zeigst" -ForegroundColor Yellow
} else {
    foreach ($pair in @(@('gitops-demo', $root), @('demo-app', $app))) {
        $s = $pair[1]
        if ($s -and $s.Sync -eq 'Synced' -and $s.Health -eq 'Healthy') { Pass "$($pair[0]): Synced / Healthy" }
        else { Fail "$($pair[0]): $(if ($s) { "$($s.Sync) / $($s.Health)" } else { 'fehlt' })" }
    }
    $web = Get-Http "$DemoUrl/"
    if ($web.Status -eq '200' -and $web.Body -match '<h1 id="title">([^<]*)</h1>') { Pass "Webseite erreichbar: $DemoUrl  (Titel: $($Matches[1]))" }
    else { Fail "$DemoUrl antwortet nicht richtig (Status $($web.Status))" }
}

Write-Step "Git und GitHub"
Push-Location $RepoRoot
try {
    $remote = Invoke-Native git @('ls-remote', 'origin', 'refs/heads/main')
    if ($remote.Code -eq 0 -and $remote.Out) { Pass "GitHub erreichbar ($(((Invoke-Native git @('remote', 'get-url', 'origin')).Out)))" }
    else { Fail "GitHub nicht erreichbar – Internet/Hotspot prüfen" }
    $head = (Invoke-Native git @('rev-parse', 'HEAD')).Out
    if ($remote.Out -and $remote.Out.StartsWith($head)) { Pass "Lokaler Stand = GitHub (main)" }
    else { Fail "Lokales main weicht von GitHub ab – 'git pull' bzw. 'git push'" }
    $dirty = (Invoke-Native git @('status', '--porcelain')).Out
    if (-not $dirty) { Pass "Keine offenen Änderungen im Repo" } else { Fail "Offene Änderungen im Repo:`n$dirty" }
    $start = [IO.File]::ReadAllText((Join-Path $RepoRoot 'scripts\values.start.yaml'))
    $now   = [IO.File]::ReadAllText((Join-Path $RepoRoot 'chart\values.yaml'))
    if ($start.Replace("`r", '') -eq $now.Replace("`r", '')) { Pass "values.yaml ist im Startzustand" }
    else { Fail "values.yaml ist nicht im Startzustand – reset.ps1 ausführen" }
} finally { Pop-Location }

Write-Step "Images im Cluster-Cache"
$cache = Get-CachedImages
foreach ($i in $Images) {
    if (Test-ImageCached $i $cache) { Pass "$i" } else { Fail "$i fehlt – setup.ps1 erneut ausführen" }
}

Write-Host ""
if ($script:fails -eq 0) {
    Write-Host "Alles grün. Viel Erfolg beim Talk!" -ForegroundColor Green
    exit 0
} else {
    Write-Host "$($script:fails) Punkt(e) rot – siehe oben und docs/Anleitung.md (Fehlerbehebung)." -ForegroundColor Red
    exit 1
}
