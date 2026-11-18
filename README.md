# Active Directory Lab mit PowerShell

[![PowerShell](https://github.com/eazzy1989/ad-lab-powershell/actions/workflows/powershell-lint.yml/badge.svg)](https://github.com/eazzy1989/ad-lab-powershell/actions/workflows/powershell-lint.yml)

PowerShell-Skripte, die eine **Active-Directory-Testumgebung** von null aufbauen und anschließend prüfen: vom ersten Domänencontroller über OU-Struktur, AGDLP-Gruppenmodell und Gruppenrichtlinien bis zu Audit-Berichten und automatischer Bereinigung inaktiver Konten.

Ich nutze das Lab, um AD-Administration reproduzierbar zu üben – auf einer VM in meinem [Homelab](https://github.com/eazzy1989/homelab).

## Ablauf

| Schritt | Skript | Was passiert |
|---|---|---|
| 1 | `Setup/01-Install-ADDSForest.ps1` | AD-DS-Rolle installieren, neue Gesamtstruktur mit DNS anlegen |
| 2 | `Setup/02-New-LabStructure.ps1` | OU-Struktur, Gruppen nach AGDLP und Benutzer aus CSV |
| 3 | `Setup/03-New-LabPolicies.ps1` | Gruppenrichtlinien und strengere Kennwortrichtlinie für Admins |
| – | `Reports/Get-ADUserAuditReport.ps1` | inaktive Konten, „Kennwort läuft nie ab“, nie angemeldet … |
| – | `Reports/Get-ADPrivilegedGroupReport.ps1` | wer hat Adminrechte – auch über verschachtelte Gruppen |
| – | `Reports/Get-GPOOverview.ps1` | alle GPOs mit Verknüpfungen, nicht verknüpfte und deaktivierte GPOs |
| – | `Maintenance/Disable-InactiveUsers.ps1` | inaktive Konten deaktivieren und in „Deaktiviert“ verschieben |

## Aufbau nach dem Setup

```text
corp.contoso.test
└─ OU=Lab
   ├─ OU=Benutzer
   │  ├─ OU=IT
   │  ├─ OU=Vertrieb
   │  ├─ OU=Buchhaltung
   │  └─ OU=Personal
   ├─ OU=Gruppen        GG_<Abteilung>, DL_Share_<Abteilung>_RW / _RO
   ├─ OU=Computer
   ├─ OU=Dienstkonten
   └─ OU=Deaktiviert
```

### Gruppenmodell nach AGDLP

```mermaid
flowchart LR
    A[Benutzer<br/>Anna Becker] --> G[GG_IT<br/>globale Gruppe]
    G --> DL[DL_Share_IT_RW<br/>domänenlokale Gruppe]
    DL --> P[Schreibrecht auf<br/>Freigabe IT]
```

**A**ccounts kommen in **G**lobale Gruppen (nach Abteilung/Rolle), diese in **D**omänen**l**okale Gruppen (nach Ressource und Recht), und nur diese erhalten **P**ermissions. Wechselt jemand die Abteilung, ändert sich nur eine Gruppenmitgliedschaft – keine einzige Berechtigung auf dem Fileserver.

### Richtlinien

| Objekt | Inhalt | Verknüpfung |
|---|---|---|
| GPO `U_Bildschirmsperre` | Bildschirmsperre mit Kennwort nach 10 Minuten | OU=Benutzer |
| GPO `C_USB-Speicher-sperren` | Zugriff auf Wechseldatenträger verbieten | bewusst noch nicht verknüpft |
| PSO `PSO_Administratoren` | mind. 16 Zeichen, Sperre nach 5 Fehlversuchen | Gruppe Domain Admins |

## Verwendung

Voraussetzung: eine VM mit Windows Server 2022/2025 (die Evaluierungsversion läuft 180 Tage) und fester IP-Adresse.

```powershell
# 1. Domänencontroller (Server startet danach neu)
.\Setup\01-Install-ADDSForest.ps1

# 2. Struktur – erst simulieren, dann ausführen
.\Setup\02-New-LabStructure.ps1 -CsvPath .\Beispiele\benutzer.csv -WhatIf
.\Setup\02-New-LabStructure.ps1 -CsvPath .\Beispiele\benutzer.csv

# 3. Richtlinien
.\Setup\03-New-LabPolicies.ps1

# Berichte
.\Reports\Get-ADUserAuditReport.ps1 -Days 60
.\Reports\Get-ADPrivilegedGroupReport.ps1
.\Reports\Get-GPOOverview.ps1 -HtmlFolder .\gpo-berichte

# Bereinigung – immer zuerst mit -WhatIf
.\Maintenance\Disable-InactiveUsers.ps1 -Days 90 -WhatIf
```

Jedes Skript hat eine eingebaute Hilfe: `Get-Help .\Setup\02-New-LabStructure.ps1 -Full`

## Sicherheit und Robustheit

- Alle Skripte, die etwas ändern, unterstützen `-WhatIf`; das Deaktivieren fragt zusätzlich nach (`ConfirmImpact = High`).
- Die Setup-Skripte sind **idempotent**: vorhandene OUs, Gruppen und Benutzer werden übersprungen.
- Startkennwörter sind zufällig, werden nur angezeigt und müssen bei der ersten Anmeldung geändert werden.
- Der Bericht zu privilegierten Gruppen arbeitet mit **SIDs** statt Gruppennamen und funktioniert daher auch auf deutschsprachigen Domänencontrollern.
- Bei jedem Push prüft **PSScriptAnalyzer** alle Skripte automatisch.

## Lizenz

[MIT](LICENSE)
