<#
.SYNOPSIS
    Prüft Benutzerkonten auf typische Sicherheits- und Aufräum-Themen.

.DESCRIPTION
    Erstellt einen Bericht über alle Benutzerkonten und markiert:
    - aktive Konten ohne Anmeldung seit X Tagen
    - Konten, die sich noch nie angemeldet haben
    - Konten mit „Kennwort läuft nie ab“
    - Konten, die kein Kennwort benötigen (PasswordNotRequired)
    - deaktivierte Konten, die noch in Gruppen sind
    Das Skript ändert nichts.

.PARAMETER Days
    Inaktivitätsgrenze in Tagen. Standard: 90

.PARAMETER ExportPath
    Optionaler CSV-Export aller auffälligen Konten.

.EXAMPLE
    .\Get-ADUserAuditReport.ps1 -Days 60 -ExportPath .\benutzer-audit.csv

.NOTES
    Autor:     Ismail Yildiz
    Benötigt:  Modul ActiveDirectory
    Hinweis:   LastLogonDate (lastLogonTimestamp) wird nur alle ~14 Tage repliziert
               und eignet sich daher für Inaktivitätsberichte, nicht für Echtzeit.
#>
#Requires -Modules ActiveDirectory

[CmdletBinding()]
param(
    [int]$Days = 90,
    [string]$ExportPath
)

$cutoff = (Get-Date).AddDays(-$Days)

$users = Get-ADUser -Filter * -Properties LastLogonDate, PasswordNeverExpires, PasswordNotRequired,
    PasswordLastSet, Enabled, MemberOf, WhenCreated, Description

$findings = foreach ($u in $users) {
    $issues = @()

    if ($u.Enabled -and $u.LastLogonDate -and $u.LastLogonDate -lt $cutoff) { $issues += "inaktiv seit $Days+ Tagen" }
    if ($u.Enabled -and -not $u.LastLogonDate -and $u.WhenCreated -lt $cutoff) { $issues += 'nie angemeldet' }
    if ($u.Enabled -and $u.PasswordNeverExpires) { $issues += 'Kennwort läuft nie ab' }
    if ($u.PasswordNotRequired) { $issues += 'kein Kennwort erforderlich' }
    if (-not $u.Enabled -and $u.MemberOf.Count -gt 0) { $issues += "deaktiviert, aber in $($u.MemberOf.Count) Gruppe(n)" }

    if ($issues) {
        [PSCustomObject]@{
            Benutzer         = $u.SamAccountName
            Name             = $u.Name
            Aktiv            = $u.Enabled
            LetzteAnmeldung  = if ($u.LastLogonDate) { $u.LastLogonDate.ToString('yyyy-MM-dd') } else { 'nie' }
            KennwortGesetzt  = if ($u.PasswordLastSet) { $u.PasswordLastSet.ToString('yyyy-MM-dd') } else { '-' }
            Befunde          = $issues -join '; '
        }
    }
}

Write-Host "`nBenutzerkonten gesamt: $(@($users).Count)   auffällig: $(@($findings).Count)" -ForegroundColor Cyan

foreach ($topic in 'inaktiv', 'nie angemeldet', 'läuft nie ab', 'kein Kennwort', 'deaktiviert') {
    $n = @($findings | Where-Object { $_.Befunde -like "*$topic*" }).Count
    $color = if ($n) { 'Yellow' } else { 'Green' }
    Write-Host ('  {0,-28} {1,4}' -f $topic, $n) -ForegroundColor $color
}

$findings | Sort-Object Aktiv, Benutzer | Format-Table -AutoSize -Wrap

if ($ExportPath) {
    $findings | Export-Csv -Path $ExportPath -NoTypeInformation -Encoding UTF8 -Delimiter ';'
    Write-Host "Exportiert nach $ExportPath" -ForegroundColor Green
}
