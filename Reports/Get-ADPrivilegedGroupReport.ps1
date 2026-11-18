<#
.SYNOPSIS
    Zeigt alle Mitglieder privilegierter Gruppen – auch über verschachtelte Gruppen.

.DESCRIPTION
    Prüft die wichtigsten administrativen Gruppen (Domain Admins, Enterprise Admins,
    Schema Admins, Administrators, Account/Server/Backup Operators …) und löst
    Verschachtelungen rekursiv auf. So wird sichtbar, wer über Umwege Adminrechte hat.
    Zusätzlich werden leere Sicherheitsgruppen aufgelistet.
    Das Skript ändert nichts.

.PARAMETER ExportPath
    Optionaler CSV-Export.

.EXAMPLE
    .\Get-ADPrivilegedGroupReport.ps1

.NOTES
    Autor:     Ismail Yildiz
    Benötigt:  Modul ActiveDirectory
#>
#Requires -Modules ActiveDirectory

[CmdletBinding()]
param(
    [string]$ExportPath
)

# Well-known SIDs/RIDs, damit der Bericht auch auf nicht-englischen Domänen funktioniert
$domainSid = (Get-ADDomain).DomainSID.Value
$rootSid   = (Get-ADDomain (Get-ADForest).RootDomain).DomainSID.Value
$privileged = @(
    "$domainSid-512"   # Domain Admins
    "$rootSid-519"     # Enterprise Admins
    "$rootSid-518"     # Schema Admins
    'S-1-5-32-544'     # Administrators
    'S-1-5-32-548'     # Account Operators
    'S-1-5-32-549'     # Server Operators
    'S-1-5-32-551'     # Backup Operators
    'S-1-5-32-550'     # Print Operators
)

$report = foreach ($sid in $privileged) {
    $group = Get-ADGroup -Identity $sid -ErrorAction SilentlyContinue
    if (-not $group) { continue }

    $direct = Get-ADGroupMember -Identity $group | Select-Object -ExpandProperty DistinguishedName
    foreach ($m in Get-ADGroupMember -Identity $group -Recursive) {
        [PSCustomObject]@{
            Gruppe    = $group.Name
            Mitglied  = $m.SamAccountName
            Typ       = $m.objectClass
            Zuweisung = if ($direct -contains $m.DistinguishedName) { 'direkt' } else { 'verschachtelt' }
        }
    }
}

Write-Host "`nPrivilegierte Gruppen" -ForegroundColor Cyan
$report | Sort-Object Gruppe, Zuweisung, Mitglied | Format-Table -AutoSize -GroupBy Gruppe

$nested = @($report | Where-Object Zuweisung -eq 'verschachtelt')
if ($nested) {
    Write-Host "Achtung: $($nested.Count) Adminrecht(e) nur über verschachtelte Gruppen – leicht zu übersehen." -ForegroundColor Yellow
}

$empty = Get-ADGroup -Filter "GroupCategory -eq 'Security'" -Properties Members |
    Where-Object { $_.Members.Count -eq 0 -and $_.SID.Value -notlike 'S-1-5-32-*' }
Write-Host "`nLeere Sicherheitsgruppen: $(@($empty).Count)" -ForegroundColor Cyan
$empty | Select-Object Name, GroupScope, DistinguishedName | Format-Table -AutoSize

if ($ExportPath) {
    $report | Export-Csv -Path $ExportPath -NoTypeInformation -Encoding UTF8 -Delimiter ';'
    Write-Host "Exportiert nach $ExportPath" -ForegroundColor Green
}
