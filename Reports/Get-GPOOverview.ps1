<#
.SYNOPSIS
    Übersicht über alle Gruppenrichtlinien: Verknüpfungen, Status und Auffälligkeiten.

.DESCRIPTION
    Liest alle GPOs der Domäne aus und zeigt pro GPO:
    - wo sie verknüpft ist (OU, Domäne) und ob die Verknüpfung aktiv ist
    - welcher Teil (Benutzer/Computer) aktiviert ist
    - wann sie zuletzt geändert wurde
    Hervorgehoben werden nicht verknüpfte und vollständig deaktivierte GPOs –
    typische Kandidaten zum Aufräumen.
    Optional wird für jede GPO ein HTML-Bericht erzeugt.

.PARAMETER HtmlFolder
    Ordner für HTML-Berichte je GPO (optional).

.EXAMPLE
    .\Get-GPOOverview.ps1 -HtmlFolder .\gpo-berichte

.NOTES
    Autor:     Ismail Yildiz
    Benötigt:  Modul GroupPolicy
#>
#Requires -Modules GroupPolicy

[CmdletBinding()]
param(
    [string]$HtmlFolder
)

if ($HtmlFolder -and -not (Test-Path $HtmlFolder)) {
    New-Item -ItemType Directory -Path $HtmlFolder | Out-Null
}

$overview = foreach ($gpo in Get-GPO -All | Sort-Object DisplayName) {
    [xml]$xml = Get-GPOReport -Guid $gpo.Id -ReportType Xml
    $links = @($xml.GPO.LinksTo)
    $linkText = if ($links -and $links[0]) {
        ($links | ForEach-Object { '{0}{1}' -f $_.SOMPath, $(if ($_.Enabled -eq 'false') { ' (deaktiviert)' } else { '' }) }) -join ', '
    } else { '' }

    if ($HtmlFolder) {
        $file = Join-Path $HtmlFolder (($gpo.DisplayName -replace '[\\/:*?"<>|]', '_') + '.html')
        Get-GPOReport -Guid $gpo.Id -ReportType Html -Path $file
    }

    [PSCustomObject]@{
        GPO          = $gpo.DisplayName
        Status       = $gpo.GpoStatus
        Verknuepfung = if ($linkText) { $linkText } else { '— nicht verknüpft —' }
        Geaendert    = $gpo.ModificationTime.ToString('yyyy-MM-dd')
    }
}

Write-Host "`nGruppenrichtlinien: $(@($overview).Count)" -ForegroundColor Cyan
$overview | Format-Table -AutoSize -Wrap

$unlinked = @($overview | Where-Object Verknuepfung -like '*nicht verknüpft*')
$disabled = @($overview | Where-Object Status -eq 'AllSettingsDisabled')
Write-Host "Nicht verknüpft:      $($unlinked.Count)" -ForegroundColor $(if ($unlinked) { 'Yellow' } else { 'Green' })
Write-Host "Komplett deaktiviert: $($disabled.Count)" -ForegroundColor $(if ($disabled) { 'Yellow' } else { 'Green' })

if ($HtmlFolder) {
    Write-Host "HTML-Berichte gespeichert in $HtmlFolder" -ForegroundColor Green
}
