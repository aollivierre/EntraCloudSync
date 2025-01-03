# Import required module and connect
Import-module "C:\Program Files\Microsoft Azure AD Connect Provisioning Agent\Utility\AADCloudSyncTools"
Connect-AADCloudSyncTools

# Function to add OUs to sync filter
function Add-OUsToSyncFilter {
   param (
       [string]$csvPath,
       [string]$jobId
   )
   
   # Track results
   $results = @{
       Success = 0
       Failed = 0
       Details = @()
   }

   # Get current schema and OUs
   $schema = Get-AADCloudSyncToolsJobSchema -Id $jobId
   $currentOUs = $schema.synchronizationRules[0].containerFilter.includedContainers
   Write-Host "`nCurrent OUs in sync filter:"
   $currentOUs | ForEach-Object { Write-Host "  $_" }

   # Import CSV
   $newOUs = Import-Csv $csvPath | Select-Object -ExpandProperty DistinguishedName
   Write-Host "`nOUs to be added from CSV:"
   $newOUs | ForEach-Object { Write-Host "  $_" }

   # Confirm with user
   $totalToAdd = $newOUs.Count
   Write-Host "`nTotal OUs to add: $totalToAdd"
   $confirm = Read-Host "Do you want to proceed? (Y/N)"
   
   if ($confirm -ne 'Y') {
       Write-Host "Operation cancelled by user"
       return $results
   }

   # Update schema
   $schemaJson = $schema | ConvertTo-Json -Depth 20 -Compress
   $schemaObject = $schemaJson | ConvertFrom-Json
   
   foreach ($ou in $newOUs) {
       try {
           # Add new OU to existing ones
           $updatedOUs = $currentOUs + $ou
           $schemaObject.synchronizationRules[0].containerFilter.includedContainers = $updatedOUs
           
           # Convert and apply
           $finalJson = $schemaObject | ConvertTo-Json -Depth 20 -Compress
           Set-AADCloudSyncToolsJobSchema -Id $jobId -Schema $finalJson
           
           $results.Success++
           $results.Details += @{
               OU = $ou
               Status = "Success"
               Error = $null
           }
           
           Write-Host "Successfully added: $ou"
           $currentOUs = $updatedOUs
       }
       catch {
           $results.Failed++
           $results.Details += @{
               OU = $ou
               Status = "Failed"
               Error = $_.Exception.Message
           }
           Write-Host "Failed to add: $ou"
           Write-Host "Error: $($_.Exception.Message)"
       }
   }

   # Final summary
   Write-Host "`nOperation Complete"
   Write-Host "Successful additions: $($results.Success)"
   Write-Host "Failed additions: $($results.Failed)"
   Write-Host "`nFinal OU list in sync filter:"
   Get-AADCloudSyncToolsJobSchema -Id $jobId | 
       Select-Object -ExpandProperty synchronizationRules | 
       Select-Object -First 1 | 
       Select-Object -ExpandProperty containerFilter | 
       Select-Object -ExpandProperty includedContainers |
       ForEach-Object { Write-Host "  $_" }

   return $results
}

# Example usage:
# $jobId = "AD2AADProvisioning.3c19ab789dd7444fa11ecd4ea7e9889e.3ac89e8a-9805-4667-90a2-e7301423c9f0" #OTT
# $jobId = "AD2AADProvisioning.3c19ab789dd7444fa11ecd4ea7e9889e.15cb083e-59ee-4721-9d98-f4724dbc9265" #IQ
# $jobId = "AD2AADProvisioning.3c19ab789dd7444fa11ecd4ea7e9889e.63007fea-0101-481f-b66b-5b81aebff352" #CB
$jobId = "AD2AADProvisioning.3c19ab789dd7444fa11ecd4ea7e9889e.54fdfaad-f2b2-4398-bbd2-2935fa5ba021" #RI
# $results = Add-OUsToSyncFilter -csvPath "path_to_your_csv.csv" -jobId $jobId
# $results = Add-OUsToSyncFilter -csvPath "C:\Code\Exports\AD\AddOUtoEntraCloudSync\OUs_Without_Computers_ott.nti.local_20241119-0833.csv" -jobId $jobId #OTT
# $results = Add-OUsToSyncFilter -csvPath "C:\Code\Exports\AD\AddOUtoEntraCloudSync\OUs_Without_Computers_iq.nti.local_20241119-1303-Import.csv" -jobId $jobId #IQ
# $results = Add-OUsToSyncFilter -csvPath "C:\Code\Exports\AD\AddOUtoEntraCloudSync\OUs_Without_Computers_cb.tunngavik.local_20241119-1501-import.csv" -jobId $jobId #CB
$results = Add-OUsToSyncFilter -csvPath "C:\Code\Exports\AD\AddOUtoEntraCloudSync\OUs_Without_Computers_ri.nti.local_20241120-0908-Import.csv" -jobId $jobId #RI