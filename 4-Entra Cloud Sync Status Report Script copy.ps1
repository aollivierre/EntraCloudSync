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
            # Check and install required modules
            $modules = @(
                'PSWriteHTML',
                $ModulePath
            )

            foreach ($module in $modules) {
                if (-not (Get-Module -Name $module -ListAvailable) -and $module -ne $ModulePath) {
                    Write-Host "Installing module: $module"
                    Install-Module -Name $module -Force -AllowClobber -Scope CurrentUser
                }
            }

            Import-Module -Name $ModulePath
            Import-Module PSWriteHTML
            Connect-AADCloudSyncTools
            return $true
        }
        catch {
            Write-Error "Failed to initialize required modules: $_"
            return $false
        }
    }

    function Get-FormattedJobStatus {
        $jobs = Get-AADCloudSyncToolsJobStatus
        
        $jobs | ForEach-Object {
            [PSCustomObject]@{
                'Job ID' = $_.id
                'Status' = $_.lastRun_state
                'Code' = $_.code
                'Last Run Start' = $_.lastRun_timeBegan
                'Last Run End' = $_.lastRun_timeEnded
                'Entities Processed' = $_.lastRun_countEntitled
                'Imported Count' = $_.lastRun_countImported
                'Exported Count' = $_.lastRun_countExported
                'Error Message' = $_.lastRun_error.message
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

        # Create summary data
        $summaryData = [PSCustomObject]@{
            'Operation Start' = $StartTime
            'Operation End' = Get-Date
            'Duration' = "{0:hh\:mm\:ss}" -f ((Get-Date) - $StartTime)
        }

        # Define status colors
        $statusColors = @{
            Succeeded = '#28a745'
            Failed = '#dc3545'
            Active = '#007bff'
            NotRun = '#6c757d'
        }

        New-HTML -TitleText 'Entra Cloud Sync Report' -FilePath $reportFile {
            New-HTMLSection -HeaderText 'Operation Summary' {
                New-HTMLTable -DataTable $summaryData -HideFooter
            }

            New-HTMLSection -HeaderText 'Status Before Sync' {
                New-HTMLTable -DataTable $BeforeStatus -HideFooter -SearchBuilder {
                    foreach ($status in $statusColors.Keys) {
                        New-HTMLTableCondition -Name 'Status' -Value $status -BackgroundColor $statusColors[$status] -Color White
                    }
                    New-HTMLTableCondition -Name 'Error Message' -Value '' -BackgroundColor '' -Color Black
                    New-HTMLTableCondition -Name 'Error Message' -Value '.*' -Operator Match -BackgroundColor '#fff3cd' -Color '#856404'
                }
            }

            New-HTMLSection -HeaderText 'Status After Sync' {
                New-HTMLTable -DataTable $AfterStatus -HideFooter -SearchBuilder {
                    foreach ($status in $statusColors.Keys) {
                        New-HTMLTableCondition -Name 'Status' -Value $status -BackgroundColor $statusColors[$status] -Color White
                    }
                    New-HTMLTableCondition -Name 'Error Message' -Value '' -BackgroundColor '' -Color Black
                    New-HTMLTableCondition -Name 'Error Message' -Value '.*' -Operator Match -BackgroundColor '#fff3cd' -Color '#856404'
                }
            }
        }

        return $reportFile
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




# Basic usage
Start-EntraCloudSyncWithReport

# Custom output path
# Start-EntraCloudSyncWithReport -OutputPath "C:\Reports\EntraSync"