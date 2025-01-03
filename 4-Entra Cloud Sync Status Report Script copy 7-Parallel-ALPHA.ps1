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
        
        foreach ($job in $jobs) {
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
        param(
            [Parameter(Mandatory)]
            [object[]]$JobStatusData
        )

        $jobs = Get-AADCloudSyncToolsJob
        $domainMapping = Get-UniqueDomainMapping
        
        $results = foreach ($job in $jobs) {
            $status = $JobStatusData | Where-Object { $_.id -eq $job.id }
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

    function Start-ParallelSyncOperations {
        [CmdletBinding()]
        param(
            [Parameter(Mandatory)]
            [array]$Jobs,
            [Parameter()]
            [int]$ThrottleLimit = 3
        )

        $runspacePool = [runspacefactory]::CreateRunspacePool(1, $ThrottleLimit)
        $runspacePool.Open()

        $scriptBlock = {
            param($JobId, $ModulePath)
            try {
                Import-Module $ModulePath -Force
                Connect-AADCloudSyncTools
                Restart-AADCloudSyncToolsJob -Id $JobId
                
                [PSCustomObject]@{
                    JobId = $JobId
                    Status = "Success"
                    Error = $null
                }
            }
            catch {
                [PSCustomObject]@{
                    JobId = $JobId
                    Status = "Failed"
                    Error = $_.Exception.Message
                }
            }
        }

        $runspaces = @()

        foreach ($job in $Jobs) {
            $powerShell = [powershell]::Create().AddScript($scriptBlock)
            $powerShell.RunspacePool = $runspacePool

            $parameters = @{
                JobId = $job.Id
                ModulePath = $ModulePath
            }
            
            $powerShell.AddParameters($parameters)

            $runspaces += @{
                PowerShell = $powerShell
                Handle = $powerShell.BeginInvoke()
                JobId = $job.Id
                StartTime = Get-Date
            }
            Write-Host "Started sync for job: $($job.Id)" -ForegroundColor Cyan
        }

        $results = @()
        while ($runspaces.Handle.IsCompleted -contains $false) {
            $completed = $runspaces | Where-Object { $_.Handle.IsCompleted -eq $true }
            foreach ($runspace in $completed) {
                if ($null -ne $runspace.PowerShell) {
                    $result = $runspace.PowerShell.EndInvoke($runspace.Handle)
                    $results += $result
                    Write-Host "Completed sync for job: $($runspace.JobId) - Status: $($result.Status)" -ForegroundColor Green
                    $runspace.PowerShell.Dispose()
                    $runspace.PowerShell = $null
                }
            }
            Start-Sleep -Milliseconds 100
        }

        $runspacePool.Close()
        $runspacePool.Dispose()

        return $results
    }

    function Get-ParallelJobStatus {
        [CmdletBinding()]
        param(
            [Parameter(Mandatory)]
            [array]$Jobs,
            [Parameter()]
            [int]$ThrottleLimit = 3
        )

        $runspacePool = [runspacefactory]::CreateRunspacePool(1, $ThrottleLimit)
        $runspacePool.Open()

        $scriptBlock = {
            param($JobId, $ModulePath)
            try {
                Import-Module $ModulePath -Force
                Connect-AADCloudSyncTools
                $status = Get-AADCloudSyncToolsJobStatus | Where-Object { $_.id -eq $JobId }
                return $status
            }
            catch {
                Write-Error "Failed to get status for job $JobId : $_"
                return $null
            }
        }

        $runspaces = @()

        foreach ($job in $Jobs) {
            $powerShell = [powershell]::Create().AddScript($scriptBlock)
            $powerShell.RunspacePool = $runspacePool

            $parameters = @{
                JobId = $job.Id
                ModulePath = $ModulePath
            }
            
            $powerShell.AddParameters($parameters)

            $runspaces += @{
                PowerShell = $powerShell
                Handle = $powerShell.BeginInvoke()
                JobId = $job.Id
            }
            Write-Host "Started status check for job: $($job.Id)" -ForegroundColor Cyan
        }

        $results = @()
        while ($runspaces.Handle.IsCompleted -contains $false) {
            $completed = $runspaces | Where-Object { $_.Handle.IsCompleted -eq $true }
            foreach ($runspace in $completed) {
                if ($null -ne $runspace.PowerShell) {
                    $results += $runspace.PowerShell.EndInvoke($runspace.Handle)
                    Write-Host "Completed status check for job: $($runspace.JobId)" -ForegroundColor Green
                    $runspace.PowerShell.Dispose()
                    $runspace.PowerShell = $null
                }
            }
            Start-Sleep -Milliseconds 100
        }

        $runspacePool.Close()
        $runspacePool.Dispose()

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

    # Main execution block
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

        # Get all jobs
        $jobs = Get-AADCloudSyncToolsJob

        # Get status before sync (in parallel)
        Write-Host "`nGetting current status..." -ForegroundColor Cyan
        $beforeStatusRaw = Get-ParallelJobStatus -Jobs $jobs -ThrottleLimit 3
        $beforeStatus = Get-FormattedJobStatus -JobStatusData $beforeStatusRaw

        # Start sync operations in parallel
        Write-Host "`nStarting sync operations..." -ForegroundColor Cyan
        $syncResults = Start-ParallelSyncOperations -Jobs $jobs -ThrottleLimit 3

        # Wait a bit for jobs to process
        Write-Host "`nWaiting for jobs to process..." -ForegroundColor Cyan
        Start-Sleep -Seconds 30

        # Get status after sync (in parallel)
        Write-Host "`nGetting updated status..." -ForegroundColor Cyan
        $afterStatusRaw = Get-ParallelJobStatus -Jobs $jobs -ThrottleLimit 3
        $afterStatus = Get-FormattedJobStatus -JobStatusData $afterStatusRaw

        # Generate report
        Write-Host "`nGenerating report..." -ForegroundColor Cyan
        $reportPaths = Export-StatusToHtml -BeforeStatus $beforeStatus -AfterStatus $afterStatus -OutputDir $OutputPath -StartTime $startTime

        Write-Host "`nOperation complete!" -ForegroundColor Green
        Write-Host "Total jobs processed: $($jobs.Count)"
        Write-Host "Successful syncs: $($syncResults.Count)"
        Write-Host "Failed syncs: $($syncResults | Where-Object { $_.Status -eq 'Failed' }).Count"
        
        return $reportPaths
    }
    catch {
        Write-Error "Error during sync operation: $_"
    }
}

# Usage example:
Start-EntraCloudSyncWithReport -OutputPath "C:\Reports\EntraSync"