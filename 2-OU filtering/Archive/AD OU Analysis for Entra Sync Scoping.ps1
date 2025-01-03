# Get all OUs in the domain
$allOUs = Get-ADOrganizationalUnit -Filter * -Properties CanonicalName, DistinguishedName

# Initialize arrays to store results
$OUsWithComputers = @()
$OUsWithoutComputers = @()

# Check each OU for computer objects
foreach ($ou in $allOUs) {
    # Try to find any computer objects in the current OU
    $computerCount = @(Get-ADComputer -Filter * -SearchBase $ou.DistinguishedName -SearchScope OneLevel -ErrorAction SilentlyContinue).Count
    
    # Create custom object with OU details
    $ouInfo = [PSCustomObject]@{
        Name = $ou.Name
        CanonicalName = $ou.CanonicalName
        DistinguishedName = $ou.DistinguishedName
        ComputerCount = $computerCount
        ObjectCount = @(Get-ADObject -Filter * -SearchBase $ou.DistinguishedName -SearchScope OneLevel -ErrorAction SilentlyContinue).Count
    }
    
    # Categorize based on computer presence
    if ($computerCount -gt 0) {
        $OUsWithComputers += $ouInfo
    } else {
        $OUsWithoutComputers += $ouInfo
    }
}

# Output results to CSV files
$timestamp = Get-Date -Format "yyyyMMdd-HHmm"
$OUsWithComputers | Export-Csv -Path "OUs_With_Computers_$timestamp.csv" -NoTypeInformation
$OUsWithoutComputers | Export-Csv -Path "OUs_Without_Computers_$timestamp.csv" -NoTypeInformation

# Display summary
Write-Host "`nOUs containing computer objects (Traditional Entra Connect Sync):" -ForegroundColor Green
$OUsWithComputers | Format-Table Name, ComputerCount, ObjectCount, CanonicalName -AutoSize

Write-Host "`nOUs without computer objects (Modern Cloud Sync):" -ForegroundColor Cyan
$OUsWithoutComputers | Format-Table Name, ObjectCount, CanonicalName -AutoSize

Write-Host "`nSummary:" -ForegroundColor Yellow
Write-Host "Total OUs: $($allOUs.Count)"
Write-Host "OUs with computers: $($OUsWithComputers.Count)"
Write-Host "OUs without computers: $($OUsWithoutComputers.Count)"
Write-Host "`nResults have been exported to CSV files in the current directory."