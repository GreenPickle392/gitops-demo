# Shared helpers for all demo scripts. Dot-source it: . "$PSScriptRoot\_lib.ps1"
# Works in Windows PowerShell 5.1 and PowerShell 7.

$ErrorActionPreference = 'Stop'
try { [Console]::OutputEncoding = [Text.Encoding]::UTF8 } catch { }

$RepoRoot   = Split-Path -Parent $PSScriptRoot
$Port       = if ($env:DEMO_PORT) { [int]$env:DEMO_PORT } else { 80 }
$PortSuffix = if ($Port -eq 80) { '' } else { ":$Port" }
$DemoHost   = 'demo.localhost'
$ArgoHost   = 'argocd.localhost'
$DemoUrl    = "http://$DemoHost$PortSuffix"
$ArgoUrl    = "http://$ArgoHost$PortSuffix"
$ArgoAppUrl = "$ArgoUrl/applications/argocd/demo-app?view=tree"
$Images     = @('nginx:1.27-alpine', 'nginx:1.29-alpine')
$ArgoChartVersion = '10.19.1'   # Argo CD v3.6.3

function Write-Step([string]$Text) { Write-Host ""; Write-Host "▶ $Text" -ForegroundColor Cyan }
function Write-Ok([string]$Text)   { Write-Host "  ✓ $Text" -ForegroundColor Green }
function Write-Bad([string]$Text)  { Write-Host "  ✗ $Text" -ForegroundColor Red }
function Write-Info([string]$Text) { Write-Host "  · $Text" -ForegroundColor Gray }

function Stop-Demo([string]$Text) {
    Write-Bad $Text
    exit 1
}

# Run a native command without PowerShell turning stderr into errors.
# Returns an object with .Code and .Out (combined stdout+stderr as one string).
function Invoke-Native {
    param([Parameter(Mandatory)][string]$Exe, [string[]]$Arguments = @())
    $old = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        $out = & $Exe @Arguments 2>&1 | ForEach-Object { "$_" }
        $code = $LASTEXITCODE
    } finally { $ErrorActionPreference = $old }
    [pscustomobject]@{ Code = $code; Out = (($out | Out-String).Trim()) }
}

# kubectl helper (simple function on purpose: all arguments land in $args). Throws on failure.
function Kube {
    $r = Invoke-Native kubectl ([string[]]$args)
    if ($r.Code -ne 0) { throw "kubectl $($args -join ' ') fehlgeschlagen:`n$($r.Out)" }
    $r.Out
}

function Test-Tool([string]$Name) { [bool](Get-Command $Name -ErrorAction SilentlyContinue) }

# HTTP GET via curl.exe (ships with Windows 10/11). Resolves *.localhost to 127.0.0.1 itself.
function Get-Http([string]$Url) {
    $r = Invoke-Native curl.exe @('-s', '-m', '5', '-w', "`n%{http_code}", $Url)
    $lines = $r.Out -split "`n"
    [pscustomobject]@{ Status = $lines[-1].Trim(); Body = ($lines[0..([Math]::Max(0, $lines.Count - 2))] -join "`n") }
}

# Returns "<sync> <health> <revision>" for an Argo CD Application, or $null if it does not exist.
function Get-AppStatus([string]$Name) {
    $r = Invoke-Native kubectl @('-n', 'argocd', 'get', 'application', $Name, '-o',
        'jsonpath={.status.sync.status} {.status.health.status} {.status.sync.revision}')
    if ($r.Code -ne 0) { return $null }
    $p = $r.Out -split ' '
    [pscustomobject]@{ Sync = $p[0]; Health = $p[1]; Revision = $(if ($p.Count -gt 2) { $p[2] } else { '' }) }
}

# Ask Argo CD to look at Git right now (same as the "Refresh" button).
function Request-AppRefresh([string]$Name) {
    Invoke-Native kubectl @('-n', 'argocd', 'annotate', 'application', $Name,
        'argocd.argoproj.io/refresh=normal', '--overwrite') | Out-Null
}

# Wait until the app is Synced + Healthy (optionally at a given Git revision).
function Wait-App {
    param([string]$Name, [int]$TimeoutSec = 180, [string]$Revision = '')
    $sw = [Diagnostics.Stopwatch]::StartNew()
    while ($sw.Elapsed.TotalSeconds -lt $TimeoutSec) {
        $s = Get-AppStatus $Name
        if ($s -and $s.Sync -eq 'Synced' -and $s.Health -eq 'Healthy' -and
            (-not $Revision -or $s.Revision -eq $Revision)) { return $true }
        Start-Sleep -Seconds 2
    }
    return $false
}

function Get-ArgoPassword {
    $r = Invoke-Native kubectl @('-n', 'argocd', 'get', 'secret', 'argocd-initial-admin-secret',
        '-o', 'jsonpath={.data.password}')
    if ($r.Code -ne 0 -or -not $r.Out) { return $null }
    [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($r.Out))
}

function Open-DemoTabs {
    $pw = Get-ArgoPassword
    if ($pw) {
        try { Set-Clipboard -Value $pw; Write-Ok "Argo-CD-Passwort liegt in der Zwischenablage (Benutzer: admin)" }
        catch { Write-Info "Argo-CD-Passwort (Benutzer admin): $pw" }
    }
    Start-Process $ArgoAppUrl
    Start-Process $DemoUrl
    Write-Ok "Browser-Tabs geöffnet: $ArgoUrl und $DemoUrl"
}

# Note: no double quotes inside native arguments - Windows PowerShell 5.1 strips them. Use -o json instead.
function Get-KubeJson {
    $r = Invoke-Native kubectl (([string[]]$args) + @('-o', 'json'))
    if ($r.Code -ne 0) { return $null }
    $r.Out | ConvertFrom-Json
}

function Get-CachedImages {
    $j = Get-KubeJson get nodes
    if (-not $j) { return '' }
    (@($j.items | ForEach-Object { $_.status.images } | ForEach-Object { $_.names }) -join "`n")
}

function Test-ImageCached([string]$Image, [string]$Cache) {
    # node image names look like docker.io/library/nginx:1.27-alpine
    $Cache -match [regex]::Escape("/library/$Image")
}
