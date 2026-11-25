<#
  Regenerates the exported documents after you edited the Markdown sources:
    docs/Anleitung.md        -> docs/img/ablauf.png (Mermaid) + docs/Anleitung.odt
    slides/praesentation.md  -> slides/praesentation.pdf + slides/praesentation.pptx
  Needs: pandoc (winget install JohnMacFarlane.Pandoc), Node.js (npx), Edge or Chrome,
         LibreOffice for the editable PPTX.
  Usage:  powershell -ExecutionPolicy Bypass -File .\scripts\build-docs.ps1 [-NurAnleitung] [-NurFolien]
#>
param([switch]$NurAnleitung, [switch]$NurFolien)
. "$PSScriptRoot\_lib.ps1"

$browser = @("${env:ProgramFiles(x86)}\Microsoft\Edge\Application\msedge.exe",
             "$env:ProgramFiles\Microsoft\Edge\Application\msedge.exe",
             "$env:ProgramFiles\Google\Chrome\Application\chrome.exe") | Where-Object { Test-Path $_ } | Select-Object -First 1
if (-not $browser) { Stop-Demo "Weder Edge noch Chrome gefunden" }
$env:PUPPETEER_SKIP_DOWNLOAD = '1'
$env:PUPPETEER_EXECUTABLE_PATH = $browser
$env:CHROME_PATH = $browser
$tmp = Join-Path ([IO.Path]::GetTempPath()) 'gitops-demo-build'
New-Item -ItemType Directory -Force $tmp | Out-Null
$utf8 = New-Object Text.UTF8Encoding($false)

if (-not $NurFolien) {
    Write-Step "Anleitung: Mermaid-Diagramm und ODT"
    $pandoc = (Get-Command pandoc -ErrorAction SilentlyContinue).Source
    if (-not $pandoc -and (Test-Path "$env:LOCALAPPDATA\Pandoc\pandoc.exe")) { $pandoc = "$env:LOCALAPPDATA\Pandoc\pandoc.exe" }
    if (-not $pandoc) { Stop-Demo "pandoc fehlt: winget install JohnMacFarlane.Pandoc" }

    $md = [IO.File]::ReadAllText((Join-Path $RepoRoot 'docs\Anleitung.md'), [Text.Encoding]::UTF8)
    $m = [regex]::Match($md, '(?s)```mermaid\r?\n(.*?)```')
    [IO.File]::WriteAllText("$tmp\ablauf.mmd", $m.Groups[1].Value, $utf8)
    [IO.File]::WriteAllText("$tmp\pptr.json", (@{ executablePath = $browser; args = @('--no-sandbox') } | ConvertTo-Json), $utf8)
    [IO.File]::WriteAllText("$tmp\mmd.json", '{"theme":"default","themeVariables":{"fontFamily":"Segoe UI, Arial, sans-serif","fontSize":"16px"}}', $utf8)
    $r = Invoke-Native npx @('-y', '@mermaid-js/mermaid-cli@11', '-i', "$tmp\ablauf.mmd", '-o', (Join-Path $RepoRoot 'docs\img\ablauf.png'),
        '-p', "$tmp\pptr.json", '-c', "$tmp\mmd.json", '-b', 'white', '-s', '2')
    if ($r.Code -ne 0) { Stop-Demo "mermaid-cli fehlgeschlagen:`n$($r.Out)" }
    Write-Ok "docs/img/ablauf.png"

    # For the ODT: diagram as image, images scaled to page width
    $odtMd = $md.Remove($m.Index, $m.Length).Insert($m.Index, '![Ablauf: vom Commit bis in den Browser](img/ablauf.png){width=16cm}')
    $odtMd = ([regex]'(?m)^# .*\r?\n').Replace($odtMd, '', 1)   # title comes from metadata
    $odtMd = [regex]::Replace($odtMd, '(!\[[^\]]*\]\(img/(website|argocd-tree)\.png\))', '$1{width=16cm}')
    [IO.File]::WriteAllText("$tmp\Anleitung.md", $odtMd, $utf8)
    Push-Location (Join-Path $RepoRoot 'docs')
    try {
        $r = Invoke-Native $pandoc @("$tmp\Anleitung.md", '-f', 'gfm+attributes', '-t', 'odt', '-o', 'Anleitung.odt',
            '--resource-path=.', '--metadata', 'title=GitOps-Demo – Anleitung', '--metadata', 'lang=de-DE')
    } finally { Pop-Location }
    if ($r.Code -ne 0) { Stop-Demo "pandoc fehlgeschlagen:`n$($r.Out)" }
    Write-Ok "docs/Anleitung.odt"
}

if (-not $NurAnleitung) {
    Write-Step "Folien: PDF und PPTX (Marp)"
    $slides = Join-Path $RepoRoot 'slides'
    $marp = @('-y', '@marp-team/marp-cli@4', 'praesentation.md', '--theme', 'gitops.css', '--html', '--allow-local-files')
    Push-Location $slides
    try {
        $r = Invoke-Native npx ($marp + @('--pdf', '-o', 'praesentation.pdf'))
        if ($r.Code -ne 0) { Stop-Demo "Marp (PDF) fehlgeschlagen:`n$($r.Out)" }
        Write-Ok "slides/praesentation.pdf"
        $r = Invoke-Native npx ($marp + @('--notes', '-o', 'sprechernotizen.txt'))
        if ($r.Code -eq 0) { Write-Ok "slides/sprechernotizen.txt" }
        # Plain PPTX (slides as images + editable speaker notes). '--pptx-editable' was tested:
        # LibreOffice turns the background gradient and the SVG text into garbage, so it is opt-in.
        $pptx = if ($env:PPTX_EDITABLE) { @('--pptx', '--pptx-editable') } else { @('--pptx') }
        $r = Invoke-Native npx ($marp + $pptx + @('-o', 'praesentation.pptx'))
        if ($r.Code -ne 0) { Stop-Demo "Marp (PPTX) fehlgeschlagen:`n$($r.Out)" }
        Write-Ok "slides/praesentation.pptx"
    } finally { Pop-Location }
}
