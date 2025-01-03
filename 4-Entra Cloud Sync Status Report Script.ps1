function Start-EntraCloudSyncWithReport {
    [CmdletBinding()]
    param(
        [Parameter()]
        [string]$OutputPath = "$env:USERPROFILE\Desktop\EntraSync",
        [Parameter()]
        [string]$ModulePath = "C:\Program Files\Microsoft Azure AD Connect Provisioning Agent\Utility\AADCloudSyncTools"
    )

    function Initialize-CloudSync {
        try {
            Import-Module $ModulePath
            Connect-AADCloudSyncTools
            return $true
        }
        catch {
            Write-Error "Failed to initialize AADCloudSyncTools: $_"
            return $false
        }
    }

    function Get-StatusColor {
        param([string]$status)
        
        switch ($status) {
            "Succeeded" { "green" }
            "Failed" { "red" }
            "Active" { "blue" }
            "NotRun" { "gray" }
            default { "black" }
        }
    }

    function Get-FormattedJobStatus {
        $jobs = Get-AADCloudSyncToolsJobStatus
        
        $jobs | ForEach-Object {
            [PSCustomObject]@{
                JobId = $_.id
                Status = $_.lastRun_state
                Code = $_.code
                LastRunStart = $_.lastRun_timeBegan
                LastRunEnd = $_.lastRun_timeEnded
                EntitiesProcessed = $_.lastRun_countEntitled
                ImportedCount = $_.lastRun_countImported
                ExportedCount = $_.lastRun_countExported
                Error = $_.lastRun_error.message
            }
        }
    }

    function Export-StatusToHtml {
        param(
            [Parameter(Mandatory)]
            [object[]]$BeforeStatus,
            [Parameter(Mandatory)]
            [object[]]$AfterStatus,
            [Parameter(Mandatory)]
            [string]$OutputPath,
            [Parameter(Mandatory)]
            [datetime]$StartTime
        )

        $reportFile = Join-Path $OutputPath "EntraCloudSync_Report_$(Get-Date -Format 'yyyyMMdd_HHmmss').html"
        $css = @"
        <style>
            body { font-family: Arial, sans-serif; margin: 20px; }
            h1, h2 { color: #2c3e50; }
            table { border-collapse: collapse; width: 100%; margin: 20px 0; }
            th, td { padding: 12px; text-align: left; border: 1px solid #ddd; }
            th { background-color: #f5f6fa; }
            tr:nth-child(even) { background-color: #f9f9f9; }
            .summary { background-color: #f8f9fa; padding: 15px; border-radius: 5px; margin: 20px 0; }
            .timestamp { color: #666; font-size: 0.9em; }
        </style>
"@

        $html = @"
<!DOCTYPE html>
<html>
<head>
    <title>Entra Cloud Sync Report</title>
    $css
</head>
<body>
    <h1>Entra Cloud Sync Operation Report</h1>
    <div class="summary">
        <p>Operation started: $StartTime</p>
        <p>Operation completed: $(Get-Date)</p>
        <p>Duration: $((Get-Date) - $StartTime)</p>
    </div>

    <h2>Status Before Sync</h2>
    <table>
        <tr>
            <th>Job ID</th>
            <th>Status</th>
            <th>Code</th>
            <th>Last Run Start</th>
            <th>Last Run End</th>
            <th>Entities</th>
            <th>Imported</th>
            <th>Exported</th>
            <th>Error</th>
        </tr>
        $(foreach ($job in $BeforeStatus) {
            $color = Get-StatusColor $job.Status
            "<tr>
                <td>$($job.JobId)</td>
                <td style='color: $color;'>$($job.Status)</td>
                <td>$($job.Code)</td>
                <td>$($job.LastRunStart)</td>
                <td>$($job.LastRunEnd)</td>
                <td>$($job.EntitiesProcessed)</td>
                <td>$($job.ImportedCount)</td>
                <td>$($job.ExportedCount)</td>
                <td style='color: red;'>$($job.Error)</td>
            </tr>"
        })
    </table>

    <h2>Status After Sync</h2>
    <table>
        <tr>
            <th>Job ID</th>
            <th>Status</th>
            <th>Code</th>
            <th>Last Run Start</th>
            <th>Last Run End</th>
            <th>Entities</th>
            <th>Imported</th>
            <th>Exported</th>
            <th>Error</th>
        </tr>
        $(foreach ($job in $AfterStatus) {
            $color = Get-StatusColor $job.Status
            "<tr>
                <td>$($job.JobId)</td>
                <td style='color: $color;'>$($job.Status)</td>
                <td>$($job.Code)</td>
                <td>$($job.LastRunStart)</td>
                <td>$($job.LastRunEnd)</td>
                <td>$($job.EntitiesProcessed)</td>
                <td>$($job.ImportedCount)</td>
                <td>$($job.ExportedCount)</td>
                <td style='color: red;'>$($job.Error)</td>
            </tr>"
        })
    </table>
</body>
</html>
"@

        # Create output directory if it doesn't exist
        if (-not (Test-Path $OutputPath)) {
            New-Item -Path $OutputPath -ItemType Directory -Force | Out-Null
        }

        $html | Out-File $reportFile -Encoding UTF8
        return $reportFile
    }

    try {
        $startTime = Get-Date
        
        # Initialize connection
        if (-not (Initialize-CloudSync)) {
            throw "Failed to initialize cloud sync tools"
        }

        # Get status before sync
        Write-Host "Getting current status..."
        $beforeStatus = Get-FormattedJobStatus

        # Get and restart all jobs
        Write-Host "Starting sync operation..."
        $jobs = Get-AADCloudSyncToolsJob
        $jobs | ForEach-Object {
            Write-Host "Restarting job: $($_.Id)"
            Restart-AADCloudSyncToolsJob -Id $_.Id
        }

        # Wait a bit for jobs to start
        Write-Host "Waiting for jobs to process..."
        Start-Sleep -Seconds 30

        # Get status after sync
        Write-Host "Getting updated status..."
        $afterStatus = Get-FormattedJobStatus

        # Generate report
        Write-Host "Generating report..."
        $reportPath = Export-StatusToHtml -BeforeStatus $beforeStatus -AfterStatus $afterStatus -OutputPath $OutputPath -StartTime $startTime

        Write-Host "`nOperation complete!"
        Write-Host "Report generated: $reportPath"
    }
    catch {
        Write-Error "Error during sync operation: $_"
    }
}



# Basic usage with default output location (Desktop\EntraSync)
Start-EntraCloudSyncWithReport

# Specify custom output path
# Start-EntraCloudSyncWithReport -OutputPath "C:\Reports\EntraSync"