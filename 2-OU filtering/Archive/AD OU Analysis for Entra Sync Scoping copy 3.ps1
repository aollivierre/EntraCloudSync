# Get current domain name
$domainName = (Get-ADDomain).DNSRoot

# Define AAD Connect sync configuration
$containerInclusions = @(
    "DC=ott,DC=nti,DC=local",
    "OU=Staff,OU=NTIOTT,DC=ott,DC=nti,DC=local"
)
$containerExclusions = @(
    "CN=LostAndFound,DC=ott,DC=nti,DC=local",
    "CN=Configuration,DC=ott,DC=nti,DC=local",
    "OU=NTIOTT,DC=ott,DC=nti,DC=local",
    "CN=Program Data,DC=ott,DC=nti,DC=local",
    "CN=System,DC=ott,DC=nti,DC=local",
    "CN=Microsoft Exchange System Objects,DC=ott,DC=nti,DC=local",
    "OU=Microsoft Exchange Security Groups,DC=ott,DC=nti,DC=local",
    "CN=Managed Service Accounts,DC=ott,DC=nti,DC=local",
    "CN=Infrastructure,DC=ott,DC=nti,DC=local",
    "CN=ForeignSecurityPrincipals,DC=ott,DC=nti,DC=local",
    "CN=Builtin,DC=ott,DC=nti,DC=local",
    "OU=NotSyncedtoEID,DC=ott,DC=nti,DC=local"
)

# Get all OUs and Containers in the domain
$allOUsAndContainers = @()
$allOUsAndContainers += Get-ADOrganizationalUnit -Filter * -Properties CanonicalName, DistinguishedName, Created
$allOUsAndContainers += Get-ADObject -Filter {ObjectClass -eq "container"} -Properties CanonicalName, DistinguishedName, Created

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
    "CN=Builtin",
    "OU=Microsoft Exchange Security Groups",
    "OU=Domain Controllers",
    "Managed Service Accounts"
)

# Function to determine sync status
function Get-SyncStatus {
    param (
        [string]$dn
    )
    
    if ($containerInclusions -contains $dn) {
        return "Explicitly Included"
    }
    elseif ($containerExclusions -contains $dn) {
        return "Explicitly Excluded"
    }
    
    # Check if the DN is under any included container
    foreach ($inclusion in $containerInclusions) {
        if ($dn.EndsWith($inclusion)) {
            # Check if it's not under any exclusion
            $isExcluded = $false
            foreach ($exclusion in $containerExclusions) {
                if ($dn.EndsWith($exclusion)) {
                    $isExcluded = $true
                    break
                }
            }
            if (-not $isExcluded) {
                return "Included (Inherited)"
            }
        }
    }
    
    foreach ($exclusion in $containerExclusions) {
        if ($dn.EndsWith($exclusion)) {
            return "Excluded (Inherited)"
        }
    }
    
    return "Not Configured"
}

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
        Created = $object.Created
        CanonicalName = $object.CanonicalName
        DistinguishedName = $object.DistinguishedName
        ComputerCount = $computerCount
        ObjectCount = @(Get-ADObject -Filter * -SearchBase $object.DistinguishedName -SearchScope OneLevel -ErrorAction SilentlyContinue).Count
        SyncStatus = Get-SyncStatus -dn $object.DistinguishedName
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
$OUsWithComputers | Sort-Object Name | 
    Select-Object Name, Type, Created, CanonicalName, DistinguishedName, ComputerCount, ObjectCount, SyncStatus | 
    Out-HtmlView -Title "$domainName - Custom OUs/Containers With Computer Objects - Traditional Entra Connect Sync ($timestamp)" -FilePath "OUs_With_Computers_$domainName`_$timestamp.html"

$OUsWithoutComputers | Sort-Object Name | 
    Select-Object Name, Type, Created, CanonicalName, DistinguishedName, ObjectCount, SyncStatus | 
    Out-HtmlView -Title "$domainName - Custom OUs/Containers Without Computer Objects - Modern Cloud Sync ($timestamp)" -FilePath "OUs_Without_Computers_$domainName`_$timestamp.html"

$DefaultContainersAndOUs | Sort-Object Name | 
    Select-Object Name, Type, Created, CanonicalName, DistinguishedName, ComputerCount, ObjectCount, SyncStatus | 
    Out-HtmlView -Title "$domainName - Default AD/Exchange Containers and OUs ($timestamp)" -FilePath "Default_Containers_and_OUs_$domainName`_$timestamp.html"

# Display summary in console
Write-Host "`nDomain: $domainName" -ForegroundColor Yellow
Write-Host "`nSummary:" -ForegroundColor Yellow
Write-Host "Total OUs and Containers: $($allOUsAndContainers.Count)"
Write-Host "Custom OUs/Containers with computers: $($OUsWithComputers.Count)"
Write-Host "Custom OUs/Containers without computers: $($OUsWithoutComputers.Count)"
Write-Host "Default AD/Exchange Containers and OUs: $($DefaultContainersAndOUs.Count)"
Write-Host "`nSync Status Summary:"
Write-Host "Explicitly Included: $(($allOUsAndContainers | Where-Object {$_.SyncStatus -eq 'Explicitly Included'}).Count)"
Write-Host "Explicitly Excluded: $(($allOUsAndContainers | Where-Object {$_.SyncStatus -eq 'Explicitly Excluded'}).Count)"
Write-Host "Included (Inherited): $(($allOUsAndContainers | Where-Object {$_.SyncStatus -eq 'Included (Inherited)'}).Count)"
Write-Host "Excluded (Inherited): $(($allOUsAndContainers | Where-Object {$_.SyncStatus -eq 'Excluded (Inherited)'}).Count)"
Write-Host "Not Configured: $(($allOUsAndContainers | Where-Object {$_.SyncStatus -eq 'Not Configured'}).Count)"
Write-Host "`nReports have been exported to CSV and HTML files in the current directory."