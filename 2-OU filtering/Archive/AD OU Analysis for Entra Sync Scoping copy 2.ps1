# Get current domain name
$domainName = (Get-ADDomain).DNSRoot

# Get all OUs and Containers in the domain
$allOUsAndContainers = @()
$allOUsAndContainers += Get-ADOrganizationalUnit -Filter * -Properties CanonicalName, DistinguishedName
$allOUsAndContainers += Get-ADObject -Filter {ObjectClass -eq "container"} -Properties CanonicalName, DistinguishedName

# Define default AD/Exchange containers and OUs
$defaultContainers = @(
    "CN=Computers",
    "CN=Users",
    "CN=System",
    "CN=Program Data",
    "CN=Microsoft Exchange System Objects",
    "CN=LostAndFound",
    "CN=Infrastructure",
    "CN=ForeignSecurityPrincipals",
    "CN=Deleted Objects",
    "OU=Microsoft Exchange Security Groups",
    "OU=Domain Controllers"
)

# Initialize arrays to store results
$OUsWithComputers = @()
$OUsWithoutComputers = @()
$DefaultContainersAndOUs = @()

# Check each OU/Container for computer objects
foreach ($object in $allOUsAndContainers) {
    # Try to find any computer objects in the current location
    $computerCount = @(Get-ADComputer -Filter * -SearchBase $object.DistinguishedName -SearchScope OneLevel -ErrorAction SilentlyContinue).Count
    
    # Create custom object with details
    $objectInfo = [PSCustomObject]@{
        Name = $object.Name
        Type = if ($object.ObjectClass -eq "container") { "Container" } else { "OU" }
        CanonicalName = $object.CanonicalName
        DistinguishedName = $object.DistinguishedName
        ComputerCount = $computerCount
        ObjectCount = @(Get-ADObject -Filter * -SearchBase $object.DistinguishedName -SearchScope OneLevel -ErrorAction SilentlyContinue).Count
    }
    
    # Check if this is a default container/OU
    $isDefault = $false
    foreach ($defaultContainer in $defaultContainers) {
        if ($object.DistinguishedName -match [regex]::Escape($defaultContainer)) {
            $isDefault = $true
            break
        }
    }
    
    # Categorize based on computer presence and default status
    if ($isDefault) {
        $DefaultContainersAndOUs += $objectInfo
    }
    elseif ($computerCount -gt 0) {
        $OUsWithComputers += $objectInfo
    }
    else {
        $OUsWithoutComputers += $objectInfo
    }
}

# Generate timestamp for files
$timestamp = Get-Date -Format "yyyyMMdd-HHmm"

# Export to CSV
$OUsWithComputers | Export-Csv -Path "OUs_With_Computers_$domainName`_$timestamp.csv" -NoTypeInformation
$OUsWithoutComputers | Export-Csv -Path "OUs_Without_Computers_$domainName`_$timestamp.csv" -NoTypeInformation
$DefaultContainersAndOUs | Export-Csv -Path "Default_Containers_and_OUs_$domainName`_$timestamp.csv" -NoTypeInformation

# Create and display HTML reports using Out-HTMLView
$OUsWithComputers | Sort-Object Name | Select-Object Name, Type, CanonicalName, DistinguishedName, ComputerCount, ObjectCount | 
    Out-HtmlView -Title "$domainName - Custom OUs/Containers With Computer Objects - Traditional Entra Connect Sync ($timestamp)" -FilePath "OUs_With_Computers_$domainName`_$timestamp.html"

$OUsWithoutComputers | Sort-Object Name | Select-Object Name, Type, CanonicalName, DistinguishedName, ObjectCount | 
    Out-HtmlView -Title "$domainName - Custom OUs/Containers Without Computer Objects - Modern Cloud Sync ($timestamp)" -FilePath "OUs_Without_Computers_$domainName`_$timestamp.html"

$DefaultContainersAndOUs | Sort-Object Name | Select-Object Name, Type, CanonicalName, DistinguishedName, ComputerCount, ObjectCount | 
    Out-HtmlView -Title "$domainName - Default AD/Exchange Containers and OUs ($timestamp)" -FilePath "Default_Containers_and_OUs_$domainName`_$timestamp.html"

# Display summary in console
Write-Host "`nDomain: $domainName" -ForegroundColor Yellow
Write-Host "`nSummary:" -ForegroundColor Yellow
Write-Host "Total OUs and Containers: $($allOUsAndContainers.Count)"
Write-Host "Custom OUs/Containers with computers: $($OUsWithComputers.Count)"
Write-Host "Custom OUs/Containers without computers: $($OUsWithoutComputers.Count)"
Write-Host "Default AD/Exchange Containers and OUs: $($DefaultContainersAndOUs.Count)"
Write-Host "`nReports have been exported to CSV and HTML files in the current directory."