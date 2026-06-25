#Requires -Modules Az.Storage
<#
.SYNOPSIS
  Exports the Participants table for a cohort to a CSV file.
  Run before teardown if you want a permanent attendance record.

.EXAMPLE
  .\export-cohort.ps1 -SessionId contoso-2026-01-01 -StorageAccount wkstorexxxxxx
#>
[CmdletBinding()]
param(
  [Parameter(Mandatory)][string]$SessionId,
  [Parameter(Mandatory)][string]$StorageAccount,
  [string]$AppRg      = 'workshop-app-rg',
  [string]$OutputFile = "cohort-$SessionId-$(Get-Date -Format 'yyyyMMdd-HHmm').csv"
)
$ErrorActionPreference = 'Stop'

Write-Host "[export-cohort] Exporting session '$SessionId' from storage account '$StorageAccount'" -ForegroundColor Cyan

$storageKey = (az storage account keys list `
  --account-name $StorageAccount `
  --resource-group $AppRg `
  --query '[0].value' -o tsv)

$rows = az storage entity query `
  --account-name $StorageAccount `
  --account-key $storageKey `
  --table-name Participants `
  --filter "PartitionKey eq '$SessionId'" `
  --output json | ConvertFrom-Json

if (-not $rows -or $rows.items.Count -eq 0) {
  Write-Warning "No participants found for session '$SessionId'"
  return
}

$csv = $rows.items | ForEach-Object {
  $statuses = $_.moduleStatuses | ConvertFrom-Json -ErrorAction SilentlyContinue
  [PSCustomObject]@{
    email           = $_.RowKey
    displayName     = $_.displayName
    slot            = $_.assignedSlot
    assignedRg      = $_.assignedRg
    assignedCidr    = $_.assignedCidr
    onboarding      = $statuses.onboarding
    module1         = $statuses.module1
    module2         = $statuses.module2
    module3         = $statuses.module3
    portalSignedInAt = $_.portalSignedInAt
    lastUpdated     = $_.lastUpdated
  }
}

$csv | Export-Csv -Path $OutputFile -NoTypeInformation -Encoding UTF8
Write-Host "[export-cohort] Exported $($csv.Count) participants to $OutputFile" -ForegroundColor Green
