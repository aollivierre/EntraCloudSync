# Get current domain name
$domainName = (Get-ADDomain).DNSRoot

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

# Generate timestamp for files
$timestamp = Get-Date -Format "yyyyMMdd-HHmm"

# Export to CSV
$OUsWithComputers | Export-Csv -Path "OUs_With_Computers_$domainName`_$timestamp.csv" -NoTypeInformation
$OUsWithoutComputers | Export-Csv -Path "OUs_Without_Computers_$domainName`_$timestamp.csv" -NoTypeInformation

# Create and display HTML reports using Out-HTMLView
$OUsWithComputers | Sort-Object Name | Select-Object Name, CanonicalName, DistinguishedName, ComputerCount, ObjectCount | 
    Out-HtmlView -Title "$domainName - OUs With Computer Objects - Traditional Entra Connect Sync ($timestamp)" -FilePath "OUs_With_Computers_$domainName`_$timestamp.html"

$OUsWithoutComputers | Sort-Object Name | Select-Object Name, CanonicalName, DistinguishedName, ObjectCount | 
    Out-HtmlView -Title "$domainName - OUs Without Computer Objects - Modern Cloud Sync ($timestamp)" -FilePath "OUs_Without_Computers_$domainName`_$timestamp.html"

# Display summary in console
Write-Host "`nDomain: $domainName" -ForegroundColor Yellow
Write-Host "`nSummary:" -ForegroundColor Yellow
Write-Host "Total OUs: $($allOUs.Count)"
Write-Host "OUs with computers: $($OUsWithComputers.Count)"
Write-Host "OUs without computers: $($OUsWithoutComputers.Count)"
Write-Host "`nReports have been exported to CSV and HTML files in the current directory."