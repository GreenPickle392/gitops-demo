# GitOps-Demo: Deployen per Git-Commit

Eine kleine Live-Demo für Kubernetes und GitOps mit **Argo CD**, komplett lokal auf einem Windows-Laptop.
Du änderst `chart/values.yaml` (Text, Emoji, Farbe, Anzahl Pods, nginx-Version), machst commit und push, und die Webseite ändert sich live, ohne dass jemand den Cluster anfasst.

![Die Demo-Webseite](docs/img/website.png)

## Schnellstart (Windows, PowerShell)

Voraussetzung: Docker Desktop + k3d **oder** Rancher Desktop, dazu helm und git (siehe [Anleitung](docs/Anleitung.md#3-einmalige-einrichtung-auf-windows)).

```powershell
git clone https://github.com/GreenPickle392/gitops-demo.git; cd gitops-demo
Set-ExecutionPolicy -Scope Process Bypass; .\scripts\k3d-cluster.ps1   # Cluster anlegen (nur bei k3d)
.\scripts\setup.ps1                                                     # Argo CD + Demo, ca. 1,5 min
```

Dann: Webseite unter <http://demo.localhost>, Argo CD unter <http://argocd.localhost> (Benutzer `admin`, das Passwort liegt in der Zwischenablage).

## Was steckt drin?

| Pfad | Inhalt |
|---|---|
| `chart/` | Helm-Chart der Webseite (nginx + SSI). **`values.yaml` ist die Demo-Datei.** |
| `apps/` | Argo-CD-Application für die Webseite |
| `bootstrap/` | Argo-CD-Einstellungen und Root-Application („App of Apps“) |
| `scripts/` | `setup`, `check`, `open-demo`, `chaos`, `reset`, `teardown`, `k3d-cluster`, `build-docs` |
| `docs/` | Anleitung mit Drehbuch für die Demo ([Markdown](docs/Anleitung.md) · [ODT für LibreOffice](docs/Anleitung.odt)) |
| `slides/` | Präsentation ([PDF](slides/praesentation.pdf) · [PPTX](slides/praesentation.pptx) · [Marp-Quelle](slides/praesentation.md) · [Sprechernotizen](slides/sprechernotizen.txt)) |

## Die Demo in 6 Schritten

1. Bootstrap: `.\scripts\setup.ps1` baut alles
2. Text, Emoji und Farbe in `values.yaml` ändern → push
3. `replicaCount: 5` → push
4. Selbstheilung: `.\scripts\chaos.ps1`
5. `tag: "1.29-alpine"` → push
6. Rollback: `git revert HEAD --no-edit; git push`

Die Details stehen im [Demo-Drehbuch](docs/Anleitung.md#5-demo-drehbuch). Danach setzt `.\scripts\reset.ps1` alles auf den Start zurück.
