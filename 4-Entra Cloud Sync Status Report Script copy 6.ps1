#Requires -Modules PSWriteHTML

function Start-EntraCloudSyncWithReport {
    [CmdletBinding()]
    param (
        [Parameter()]
        [string]$OutputPath = "$env:USERPROFILE\Desktop\EntraSync",
        [Parameter()]
        [string]$ModulePath = "C:\Program Files\Microsoft Azure AD Connect Provisioning Agent\Utility\AADCloudSyncTools"
    )

    function Initialize-CloudSync {
        try {
            Import-Module $ModulePath -Force
            Connect-AADCloudSyncTools
            return $true
        }
        catch {
            Write-Error "Failed to initialize AADCloudSyncTools: $_"
            return $false
        }
    }

    function Get-DomainFromContainer {
        param([string]$container)
        if ($container -match 'DC=([^,]+),DC=([^,]+),DC=([^,\s]+)') {
            return "$($Matches[1]).$($Matches[2]).$($Matches[3])"
        }
        return $null
    }

    function Get-UniqueDomainMapping {
        $jobs = Get-AADCloudSyncToolsJob
        $domainMapping = @{}
        
        foreach($job in $jobs) {
            $schema = Get-AADCloudSyncToolsJobSchema -Id $job.id
            if ($schema.synchronizationRules[0].containerFilter.includedContainers) {
                # Take the first container's domain info
                $container = $schema.synchronizationRules[0].containerFilter.includedContainers[0]
                $domain = Get-DomainFromContainer $container
                if ($domain) {
                    $agentId = ($job.id -split '\.')[-1]
                    $domainMapping[$agentId] = $domain
                }
            }
        }
        
        return $domainMapping
    }

    function Get-FormattedJobStatus {
        $jobs = Get-AADCloudSyncToolsJob
        $jobStatus = Get-AADCloudSyncToolsJobStatus
        $domainMapping = Get-UniqueDomainMapping
        
        $results = foreach($job in $jobs) {
            $status = $jobStatus | Where-Object { $_.id -eq $job.id }
            $schema = Get-AADCloudSyncToolsJobSchema -Id $job.id
            $agentId = ($job.id -split '\.')[-1]
            
            [PSCustomObject]@{
                'Domain' = $domainMapping[$agentId]
                'Job Type' = $job.templateId
                'Agent ID' = $agentId
                'Direction' = switch -Wildcard ($job.templateId) {
                    'AAD2AD*' { 'Entra ID -> Active Directory' }
                    'AD2AAD*' { 'Active Directory -> Entra ID' }
                    default { 'Unknown' }
                }
                'Status' = $status.lastRun_state
                'Last Run Start' = $status.lastRun_timeBegan
                'Last Run End' = $status.lastRun_timeEnded
                'Duration' = if ($status.lastRun_timeBegan -and $status.lastRun_timeEnded) {
                    "{0:mm}m {0:ss}s" -f ([datetime]$status.lastRun_timeEnded - [datetime]$status.lastRun_timeBegan)
                } else { "N/A" }
                'Imported' = $status.lastRun_countImported
                'Exported' = $status.lastRun_countExported
                'Users Synced' = $status.synchronizedCount_User
                'Groups Synced' = $status.synchronizedCount_Group
                'Contacts Synced' = $status.synchronizedCount_Contact
                'Error Message' = if ($status.lastRun_error.message) { 
                    $status.lastRun_error.message 
                } else { "" }
            }
        }
        
        return $results
    }

    function Export-StatusToHtml {
        param(
            [Parameter(Mandatory)]
            [object[]]$BeforeStatus,
            [Parameter(Mandatory)]
            [object[]]$AfterStatus,
            [Parameter(Mandatory)]
            [string]$OutputDir,
            [Parameter(Mandatory)]
            [datetime]$StartTime
        )

        $timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
        $reportName = "EntraCloudSync_Report"
        $htmlPath = Join-Path $OutputDir "$($reportName)_$timestamp.html"
        $csvPath = Join-Path $OutputDir "$($reportName)_$timestamp.csv"

        # Export to CSV
        $AfterStatus | Export-Csv -Path $csvPath -NoTypeInformation

        $metadata = @{
            GeneratedBy = $env:USERNAME
            GeneratedOn = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
            StartTime = $StartTime.ToString("yyyy-MM-dd HH:mm:ss")
            EndTime = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
            Duration = "{0:hh\:mm\:ss}" -f ((Get-Date) - $StartTime)
            TotalJobs = $AfterStatus.Count
            SuccessCount = ($AfterStatus | Where-Object Status -eq "Succeeded").Count
            FailureCount = ($AfterStatus | Where-Object Status -eq "Failed").Count
            ActiveCount = ($AfterStatus | Where-Object Status -eq "Active").Count
        }

        New-HTML -Title "Entra Cloud Sync Status Report" -FilePath $htmlPath -ShowHTML {
            New-HTMLSection -HeaderText "Sync Operation Summary" {
                New-HTMLPanel {
                    New-HTMLText -Text @"
                    <h3>Report Details</h3>
                    <ul>
                        <li>Generated By: $($metadata.GeneratedBy)</li>
                        <li>Start Time: $($metadata.StartTime)</li>
                        <li>End Time: $($metadata.EndTime)</li>
                        <li>Duration: $($metadata.Duration)</li>
                        <li>Total Jobs: $($metadata.TotalJobs)</li>
                        <li>Successful Jobs: $($metadata.SuccessCount)</li>
                        <li>Failed Jobs: $($metadata.FailureCount)</li>
                        <li>Active Jobs: $($metadata.ActiveCount)</li>
                    </ul>
"@
                }
            }

            New-HTMLSection -HeaderText "Status Before Sync" {
                New-HTMLTable -DataTable $BeforeStatus -ScrollX -Buttons @('copyHtml5', 'excelHtml5', 'csvHtml5', 'searchPanes') -SearchBuilder {
                    New-TableCondition -Name 'Status' -ComparisonType string -Operator eq -Value 'Failed' -BackgroundColor Salmon -Color Black
                    New-TableCondition -Name 'Status' -ComparisonType string -Operator eq -Value 'Succeeded' -BackgroundColor LightGreen -Color Black
                    New-TableCondition -Name 'Status' -ComparisonType string -Operator eq -Value 'Active' -BackgroundColor LightBlue -Color Black
                    New-TableCondition -Name 'Duration' -ComparisonType string -Operator contains -Value 'N/A' -BackgroundColor LightGray -Color Black
                    New-TableCondition -Name 'Error Message' -ComparisonType string -Operator ne -Value '' -BackgroundColor LightYellow -Color Black
                }
            }

            New-HTMLSection -HeaderText "Status After Sync" {
                New-HTMLTable -DataTable $AfterStatus -ScrollX -Buttons @('copyHtml5', 'excelHtml5', 'csvHtml5', 'searchPanes') -SearchBuilder {
                    New-TableCondition -Name 'Status' -ComparisonType string -Operator eq -Value 'Failed' -BackgroundColor Salmon -Color Black
                    New-TableCondition -Name 'Status' -ComparisonType string -Operator eq -Value 'Succeeded' -BackgroundColor LightGreen -Color Black
                    New-TableCondition -Name 'Status' -ComparisonType string -Operator eq -Value 'Active' -BackgroundColor LightBlue -Color Black
                    New-TableCondition -Name 'Duration' -ComparisonType string -Operator contains -Value 'N/A' -BackgroundColor LightGray -Color Black
                    New-TableCondition -Name 'Error Message' -ComparisonType string -Operator ne -Value '' -BackgroundColor LightYellow -Color Black
                }
            }
        }

        Write-Host "`nReports generated:" -ForegroundColor Green
        Write-Host "CSV Report: $csvPath" -ForegroundColor Green
        Write-Host "HTML Report: $htmlPath" -ForegroundColor Green

        return @{
            CSVPath = $csvPath
            HTMLPath = $htmlPath
        }
    }

    try {
        $startTime = Get-Date
        
        # Initialize connection
        if (-not (Initialize-CloudSync)) {
            throw "Failed to initialize required modules"
        }

        # Create output directory if it doesn't exist
        if (-not (Test-Path $OutputPath)) {
            New-Item -Path $OutputPath -ItemType Directory -Force | Out-Null
        }

        # Get status before sync
        Write-Host "Getting current status..."
        $beforeStatus = Get-FormattedJobStatus

        # Get and restart all jobs
        Write-Host "Starting sync operation..."
        $jobs = Get-AADCloudSyncToolsJob
        $jobs | ForEach-Object {
            Write-Host "Restarting job: $($_.Id)" -ForegroundColor Yellow
            Restart-AADCloudSyncToolsJob -Id $_.Id
        }

        # Wait a bit for jobs to start and process
        Write-Host "Waiting for jobs to process..."
        Start-Sleep -Seconds 30

        # Get status after sync
        Write-Host "Getting updated status..."
        $afterStatus = Get-FormattedJobStatus

        # Generate report
        Write-Host "Generating report..."
        $reportPaths = Export-StatusToHtml -BeforeStatus $beforeStatus -AfterStatus $afterStatus -OutputDir $OutputPath -StartTime $startTime

        Write-Host "`nOperation complete!" -ForegroundColor Green
        
        return $reportPaths
    }
    catch {
        Write-Error "Error during sync operation: $_"
    }
}

# Example usage:
Start-EntraCloudSyncWithReport -OutputPath "C:\Reports\EntraSync"