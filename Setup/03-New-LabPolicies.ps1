<#
.SYNOPSIS
    Legt Beispiel-Gruppenrichtlinien und eine strengere Kennwortrichtlinie für Administratoren an.

.DESCRIPTION
    1. GPO „U_Bildschirmsperre“ (Benutzerkonfiguration):
       Bildschirmschoner nach 10 Minuten mit Kennwortabfrage – verknüpft mit OU=Benutzer.
    2. GPO „C_USB-Speicher-sperren“ (Computerkonfiguration):
       verbietet Lese- und Schreibzugriff auf Wechseldatenträger – erstellt, aber bewusst
       NICHT verknüpft, damit sie erst bewusst getestet wird.
    3. Fein abgestimmte Kennwortrichtlinie (PSO) für die Gruppe „Domain Admins“:
       mindestens 16 Zeichen, Sperre nach 5 Fehlversuchen.

    Vorhandene Objekte werden übersprungen. Unterstützt -WhatIf.

.EXAMPLE
    .\03-New-LabPolicies.ps1 -WhatIf

.NOTES
    Autor:     Ismail Yildiz
    Benötigt:  Module GroupPolicy und ActiveDirectory
#>
#Requires -Modules GroupPolicy, ActiveDirectory

[CmdletBinding(SupportsShouldProcess)]
param(
    [string]$RootOuName = 'Lab',
    [int]$ScreenSaverSeconds = 600
)

$domainDn = (Get-ADDomain).DistinguishedName
$usersOu  = "OU=Benutzer,OU=$RootOuName,$domainDn"

# --- 1. Bildschirmsperre ---------------------------------------------------
$gpoName = 'U_Bildschirmsperre'
if (-not (Get-GPO -Name $gpoName -ErrorAction SilentlyContinue)) {
    if ($PSCmdlet.ShouldProcess($gpoName, 'GPO anlegen und mit OU=Benutzer verknüpfen')) {
        $gpo = New-GPO -Name $gpoName -Comment 'Bildschirmsperre mit Kennwort nach Inaktivität'
        $gpo.GpoStatus = 'ComputerSettingsDisabled'   # nur Benutzerkonfiguration verwenden

        $key = 'HKCU\Software\Policies\Microsoft\Windows\Control Panel\Desktop'
        Set-GPRegistryValue -Name $gpoName -Key $key -ValueName 'ScreenSaveActive'    -Type String -Value '1' | Out-Null
        Set-GPRegistryValue -Name $gpoName -Key $key -ValueName 'ScreenSaverIsSecure' -Type String -Value '1' | Out-Null
        Set-GPRegistryValue -Name $gpoName -Key $key -ValueName 'ScreenSaveTimeOut'   -Type String -Value "$ScreenSaverSeconds" | Out-Null

        New-GPLink -Name $gpoName -Target $usersOu -LinkEnabled Yes | Out-Null
        Write-Host "[GPO]  $gpoName angelegt und mit $usersOu verknüpft" -ForegroundColor Green
    }
}

# --- 2. USB-Speicher sperren (nicht verknüpft) -----------------------------
$gpoName = 'C_USB-Speicher-sperren'
if (-not (Get-GPO -Name $gpoName -ErrorAction SilentlyContinue)) {
    if ($PSCmdlet.ShouldProcess($gpoName, 'GPO anlegen (ohne Verknüpfung)')) {
        $gpo = New-GPO -Name $gpoName -Comment 'Sperrt Wechseldatenträger – vor dem Verknüpfen testen'
        $gpo.GpoStatus = 'UserSettingsDisabled'

        $key = 'HKLM\Software\Policies\Microsoft\Windows\RemovableStorageDevices'
        Set-GPRegistryValue -Name $gpoName -Key $key -ValueName 'Deny_All' -Type DWord -Value 1 | Out-Null
        Write-Host "[GPO]  $gpoName angelegt (noch nicht verknüpft)" -ForegroundColor Yellow
    }
}

# --- 3. Kennwortrichtlinie für Administratoren (PSO) -----------------------
$psoName = 'PSO_Administratoren'
if (-not (Get-ADFineGrainedPasswordPolicy -Filter "Name -eq '$psoName'" -ErrorAction SilentlyContinue)) {
    if ($PSCmdlet.ShouldProcess($psoName, 'Fein abgestimmte Kennwortrichtlinie anlegen')) {
        New-ADFineGrainedPasswordPolicy -Name $psoName `
            -Precedence 10 `
            -MinPasswordLength 16 `
            -PasswordHistoryCount 24 `
            -ComplexityEnabled $true `
            -ReversibleEncryptionEnabled $false `
            -MaxPasswordAge (New-TimeSpan -Days 180) `
            -MinPasswordAge (New-TimeSpan -Days 1) `
            -LockoutThreshold 5 `
            -LockoutDuration (New-TimeSpan -Minutes 30) `
            -LockoutObservationWindow (New-TimeSpan -Minutes 30) `
            -ProtectedFromAccidentalDeletion $true

        # Gruppe über ihre SID ermitteln (RID 512) – funktioniert auch auf deutschen DCs („Domänen-Admins“)
        $domainAdmins = Get-ADGroup -Identity "$((Get-ADDomain).DomainSID.Value)-512"
        Add-ADFineGrainedPasswordPolicySubject -Identity $psoName -Subjects $domainAdmins
        Write-Host "[PSO]  $psoName gilt für '$($domainAdmins.Name)'" -ForegroundColor Green
    }
}
