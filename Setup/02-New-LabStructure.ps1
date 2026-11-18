<#
.SYNOPSIS
    Legt OU-Struktur, Gruppen nach dem AGDLP-Prinzip und Benutzer aus einer CSV an.

.DESCRIPTION
    Baut in der aktuellen Domäne eine übersichtliche Lab-Struktur auf:

    OU=Lab
      ├─ OU=Benutzer   (je Abteilung eine Unter-OU)
      ├─ OU=Gruppen
      ├─ OU=Computer
      ├─ OU=Dienstkonten
      └─ OU=Deaktiviert

    Gruppen nach AGDLP (Accounts → Global → Domain Local → Permissions):
      - je Abteilung eine globale Gruppe          GG_<Abteilung>
      - je Abteilung zwei domänenlokale Gruppen    DL_Share_<Abteilung>_RW / _RO
      - die globale Gruppe ist Mitglied der RW-Gruppe;
        Berechtigungen auf Freigaben werden später nur an DL-Gruppen vergeben.

    Benutzer erhalten ein zufälliges Startkennwort und müssen es bei der ersten
    Anmeldung ändern. Vorhandene Objekte werden übersprungen – das Skript kann
    also beliebig oft ausgeführt werden. Unterstützt -WhatIf.

.PARAMETER CsvPath
    CSV mit den Spalten Vorname, Nachname, Abteilung, Position.

.EXAMPLE
    .\02-New-LabStructure.ps1 -CsvPath ..\Beispiele\benutzer.csv -WhatIf

.NOTES
    Autor:     Ismail Yildiz
    Benötigt:  Modul ActiveDirectory, Rechte zum Anlegen von OUs, Gruppen und Benutzern
#>
#Requires -Modules ActiveDirectory

[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory)][ValidateScript({ Test-Path $_ })][string]$CsvPath,
    [string]$RootOuName = 'Lab'
)

$domain   = Get-ADDomain
$domainDn = $domain.DistinguishedName
$upnSuffix = $domain.DNSRoot

function Confirm-OU([string]$Name, [string]$Path) {
    $dn = "OU=$Name,$Path"
    if (-not (Get-ADOrganizationalUnit -Filter "DistinguishedName -eq '$dn'" -ErrorAction SilentlyContinue)) {
        if ($PSCmdlet.ShouldProcess($dn, 'OU anlegen')) {
            New-ADOrganizationalUnit -Name $Name -Path $Path -ProtectedFromAccidentalDeletion $true
            Write-Host "[OU]       $dn" -ForegroundColor Green
        }
    }
    return $dn
}

function Confirm-Group([string]$Name, [string]$Scope, [string]$Path, [string]$Description) {
    if (-not (Get-ADGroup -Filter "Name -eq '$Name'" -ErrorAction SilentlyContinue)) {
        if ($PSCmdlet.ShouldProcess($Name, "Gruppe ($Scope) anlegen")) {
            New-ADGroup -Name $Name -GroupScope $Scope -GroupCategory Security -Path $Path -Description $Description
            Write-Host "[GRUPPE]   $Name ($Scope)" -ForegroundColor Green
        }
    }
}

function ConvertTo-UpnPart([string]$Text) {
    $t = $Text.Trim().ToLower() -replace 'ä', 'ae' -replace 'ö', 'oe' -replace 'ü', 'ue' -replace 'ß', 'ss'
    return ($t -replace '[^a-z0-9\-]', '')
}

function New-RandomSecurePassword([int]$Length = 16) {
    $chars = 'ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz23456789!$%&*?'.ToCharArray()
    $bytes = [byte[]]::new($Length)
    [Security.Cryptography.RandomNumberGenerator]::Create().GetBytes($bytes)
    $plain = 'Aa1!' + (-join ($bytes | ForEach-Object { $chars[$_ % $chars.Length] }))
    $secure = [Security.SecureString]::new()
    foreach ($c in $plain.ToCharArray()) { $secure.AppendChar($c) }
    $secure.MakeReadOnly()
    return [PSCustomObject]@{ Plain = $plain; Secure = $secure }
}

# --- OU-Struktur ---------------------------------------------------------
$rootOu   = Confirm-OU $RootOuName $domainDn
$usersOu  = Confirm-OU 'Benutzer' $rootOu
$groupsOu = Confirm-OU 'Gruppen' $rootOu
Confirm-OU 'Computer' $rootOu | Out-Null
Confirm-OU 'Dienstkonten' $rootOu | Out-Null
Confirm-OU 'Deaktiviert' $rootOu | Out-Null

$rows = Import-Csv -Path $CsvPath
$departments = $rows.Abteilung | Sort-Object -Unique

# --- Abteilungs-OUs und Gruppen (AGDLP) ----------------------------------
foreach ($dept in $departments) {
    Confirm-OU $dept $usersOu | Out-Null

    $gg   = "GG_$dept"
    $dlRw = "DL_Share_${dept}_RW"
    $dlRo = "DL_Share_${dept}_RO"

    Confirm-Group $gg   'Global'      $groupsOu "Alle Mitarbeitenden der Abteilung $dept"
    Confirm-Group $dlRw 'DomainLocal' $groupsOu "Schreibrechte auf die Abteilungsfreigabe $dept"
    Confirm-Group $dlRo 'DomainLocal' $groupsOu "Leserechte auf die Abteilungsfreigabe $dept"

    if ($PSCmdlet.ShouldProcess("$gg -> $dlRw", 'Gruppe verschachteln')) {
        $members = Get-ADGroupMember -Identity $dlRw -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Name
        if ($members -notcontains $gg) {
            Add-ADGroupMember -Identity $dlRw -Members $gg
            Write-Host "[AGDLP]    $gg ist Mitglied von $dlRw" -ForegroundColor Cyan
        }
    }
}

# --- Benutzer -------------------------------------------------------------
$created = @()
foreach ($row in $rows) {
    $first = $row.Vorname.Trim(); $last = $row.Nachname.Trim(); $dept = $row.Abteilung.Trim()
    $sam = ('{0}.{1}' -f (ConvertTo-UpnPart $first), (ConvertTo-UpnPart $last))
    if ($sam.Length -gt 20) { $sam = $sam.Substring(0, 20) }

    if (Get-ADUser -Filter "SamAccountName -eq '$sam'" -ErrorAction SilentlyContinue) {
        Write-Host "[VORHANDEN] $sam" -ForegroundColor Yellow
        continue
    }

    if (-not $PSCmdlet.ShouldProcess($sam, 'Benutzer anlegen')) { continue }

    $pw = New-RandomSecurePassword
    New-ADUser `
        -Name "$first $last" `
        -GivenName $first `
        -Surname $last `
        -DisplayName "$first $last" `
        -SamAccountName $sam `
        -UserPrincipalName "$sam@$upnSuffix" `
        -Department $dept `
        -Title $row.Position `
        -Path "OU=$dept,$usersOu" `
        -AccountPassword $pw.Secure `
        -ChangePasswordAtLogon $true `
        -Enabled $true

    Add-ADGroupMember -Identity "GG_$dept" -Members $sam
    Write-Host "[BENUTZER] $sam -> GG_$dept" -ForegroundColor Green
    $created += [PSCustomObject]@{ Benutzer = $sam; Startkennwort = $pw.Plain }
}

if ($created) {
    Write-Host "`nStartkennwörter (nur Lab – nicht speichern):" -ForegroundColor Yellow
    $created | Format-Table -AutoSize
}
