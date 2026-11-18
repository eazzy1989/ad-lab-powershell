<#
.SYNOPSIS
    Deaktiviert inaktive Benutzerkonten und verschiebt sie in die OU „Deaktiviert“.

.DESCRIPTION
    Sucht aktive Benutzerkonten unterhalb einer Such-OU, die sich seit X Tagen
    nicht angemeldet haben, und
    - deaktiviert sie,
    - vermerkt Datum und Grund in der Beschreibung,
    - verschiebt sie in die OU „Deaktiviert“.

    Ausgenommen sind Dienstkonten-OUs und Konten aus der Ausnahmeliste.
    Unbedingt zuerst mit -WhatIf ausführen.

.PARAMETER Days
    Inaktivitätsgrenze in Tagen. Standard: 90

.PARAMETER SearchBase
    OU, unterhalb der gesucht wird. Standard: OU=Benutzer,OU=Lab,<Domäne>

.PARAMETER Exclude
    SamAccountNames, die nie deaktiviert werden.

.EXAMPLE
    .\Disable-InactiveUsers.ps1 -Days 90 -WhatIf

.NOTES
    Autor:     Ismail Yildiz
    Benötigt:  Modul ActiveDirectory
#>
#Requires -Modules ActiveDirectory

[CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
param(
    [int]$Days = 90,
    [string]$SearchBase,
    [string]$TargetOu,
    [string[]]$Exclude = @()
)

$domainDn = (Get-ADDomain).DistinguishedName
if (-not $SearchBase) { $SearchBase = "OU=Benutzer,OU=Lab,$domainDn" }
if (-not $TargetOu)   { $TargetOu   = "OU=Deaktiviert,OU=Lab,$domainDn" }

$cutoff = (Get-Date).AddDays(-$Days)
$today  = Get-Date -Format 'yyyy-MM-dd'

$candidates = Get-ADUser -SearchBase $SearchBase -Filter 'Enabled -eq $true' -Properties LastLogonDate, WhenCreated |
    Where-Object {
        $_.SamAccountName -notin $Exclude -and
        $_.DistinguishedName -notlike '*OU=Dienstkonten*' -and
        (($_.LastLogonDate -and $_.LastLogonDate -lt $cutoff) -or (-not $_.LastLogonDate -and $_.WhenCreated -lt $cutoff))
    }

Write-Host "Kandidaten (keine Anmeldung seit $Days Tagen): $(@($candidates).Count)" -ForegroundColor Cyan

$done = 0
foreach ($u in $candidates) {
    $last = if ($u.LastLogonDate) { $u.LastLogonDate.ToString('yyyy-MM-dd') } else { 'nie' }
    if ($PSCmdlet.ShouldProcess("$($u.SamAccountName) (letzte Anmeldung: $last)", 'Deaktivieren und verschieben')) {
        Disable-ADAccount -Identity $u
        Set-ADUser -Identity $u -Description "Deaktiviert am $today – inaktiv seit $last"
        Move-ADObject -Identity $u.DistinguishedName -TargetPath $TargetOu
        Write-Host "[DEAKTIVIERT] $($u.SamAccountName)" -ForegroundColor Yellow
        $done++
    }
}

Write-Host "`nDeaktiviert: $done" -ForegroundColor Green
