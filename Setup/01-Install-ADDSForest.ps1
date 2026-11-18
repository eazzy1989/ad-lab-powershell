<#
.SYNOPSIS
    Macht einen frisch installierten Windows Server zum ersten Domänencontroller einer neuen Gesamtstruktur.

.DESCRIPTION
    Installiert die Rolle „Active Directory Domain Services“ inklusive Verwaltungstools,
    legt eine neue Gesamtstruktur mit integriertem DNS an und startet den Server neu.
    Das DSRM-Kennwort (Verzeichnisdienst-Wiederherstellungsmodus) wird interaktiv abgefragt
    und nirgends gespeichert.

    Nur für Test- und Lab-Umgebungen gedacht.

.PARAMETER DomainName
    FQDN der neuen Domäne. Standard: corp.contoso.test

.PARAMETER NetbiosName
    NetBIOS-Name der Domäne. Standard: CONTOSO

.EXAMPLE
    .\01-Install-ADDSForest.ps1 -WhatIf

.EXAMPLE
    .\01-Install-ADDSForest.ps1 -DomainName corp.contoso.test -NetbiosName CONTOSO

.NOTES
    Autor:      Ismail Yildiz
    Ausführen:  als lokaler Administrator auf Windows Server 2022/2025 mit fester IP-Adresse
#>
#Requires -RunAsAdministrator

[CmdletBinding(SupportsShouldProcess)]
param(
    [string]$DomainName = 'corp.contoso.test',
    [ValidateLength(1, 15)]
    [string]$NetbiosName = 'CONTOSO'
)

# Feste IP-Adresse prüfen – ein DC mit DHCP-Adresse führt später zu DNS-Problemen
$dhcp = Get-NetIPInterface -AddressFamily IPv4 -ConnectionState Connected |
    Where-Object { $_.Dhcp -eq 'Enabled' -and $_.InterfaceAlias -notlike 'Loopback*' }
if ($dhcp) {
    Write-Warning "Netzwerkadapter mit DHCP gefunden: $($dhcp.InterfaceAlias -join ', '). Für einen DC eine feste IP-Adresse vergeben."
}

if ($PSCmdlet.ShouldProcess($env:COMPUTERNAME, 'Rolle AD DS installieren')) {
    Install-WindowsFeature -Name AD-Domain-Services -IncludeManagementTools | Out-Null
    Write-Host 'Rolle AD DS installiert.' -ForegroundColor Green
}

if ($PSCmdlet.ShouldProcess($DomainName, 'Neue Gesamtstruktur anlegen und neu starten')) {
    $dsrm = Read-Host -AsSecureString -Prompt 'DSRM-Kennwort (Wiederherstellungsmodus)'

    Import-Module ADDSDeployment
    Install-ADDSForest `
        -DomainName $DomainName `
        -DomainNetbiosName $NetbiosName `
        -InstallDns `
        -SafeModeAdministratorPassword $dsrm `
        -Force
}
