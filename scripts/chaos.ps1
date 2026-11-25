<#
  "Sabotage" for the self-healing demo: changes the cluster by hand, Argo CD reverts it.
  Usage:  .\scripts\chaos.ps1                       # deletes the Deployment
          .\scripts\chaos.ps1 -Modus skalieren       # scales it by hand to 0 Pods
          .\scripts\chaos.ps1 -Modus skalieren -Replicas 8
#>
param(
    [ValidateSet('loeschen', 'skalieren')][string]$Modus = 'loeschen',
    [int]$Replicas = 0
)
. "$PSScriptRoot\_lib.ps1"

$before = Invoke-Native kubectl @('-n', 'demo', 'get', 'deployment', 'demo-app', '-o', 'jsonpath={.spec.replicas} {.metadata.uid}')
if ($before.Code -ne 0) { Stop-Demo "Deployment demo-app nicht gefunden – läuft die Demo (setup.ps1)?" }
$want, $oldUid = $before.Out -split ' '
$want = [int]$want

Write-Step "Sabotage!"
if ($Modus -eq 'loeschen') {
    Kube -n demo delete deployment demo-app --wait=false | Out-Null
    Write-Bad "Deployment demo-app von Hand gelöscht (kubectl delete)"
} else {
    Kube -n demo scale deployment demo-app "--replicas=$Replicas" | Out-Null
    Write-Bad "Deployment demo-app von Hand auf $Replicas Pod(s) skaliert (Git sagt: $want)"
}

Write-Step "Argo CD stellt den Soll-Zustand aus Git wieder her …"
$sw = [Diagnostics.Stopwatch]::StartNew(); $last = ''
while ($sw.Elapsed.TotalSeconds -lt 120) {
    $r = Invoke-Native kubectl @('-n', 'demo', 'get', 'deployment', 'demo-app', '-o',
        'jsonpath={.metadata.uid} {.spec.replicas} {.status.readyReplicas}')
    $s = Get-AppStatus 'demo-app'
    $argo = if ($s) { "$($s.Sync)/$($s.Health)" } else { '?' }
    if ($r.Code -ne 0) { $line = "Deployment fehlt         Argo CD: $argo" }
    else {
        $p = $r.Out -split ' '
        $ready = if ($p.Count -gt 2 -and $p[2]) { [int]$p[2] } else { 0 }
        $line = "Pods bereit: $ready/$($p[1])     Argo CD: $argo"
        $isNew = ($Modus -ne 'loeschen') -or ($p[0] -ne $oldUid)
        if (-not $isNew) { $line = "altes Deployment wird gelöscht …   Argo CD: $argo" }
        elseif ([int]$p[1] -eq $want -and $ready -eq $want -and $s -and $s.Sync -eq 'Synced' -and $s.Health -eq 'Healthy') {
            Write-Info ("{0,3}s  {1}" -f [int]$sw.Elapsed.TotalSeconds, $line)
            Write-Host ""
            Write-Ok ("Selbstheilung nach {0:N0} s – niemand musste eingreifen." -f $sw.Elapsed.TotalSeconds)
            exit 0
        }
    }
    if ($line -ne $last) { Write-Info ("{0,3}s  {1}" -f [int]$sw.Elapsed.TotalSeconds, $line); $last = $line }
    Start-Sleep -Milliseconds 500
}
Stop-Demo "Nach 2 Minuten noch nicht geheilt – in Argo CD auf 'Refresh' bzw. 'Sync' klicken."
