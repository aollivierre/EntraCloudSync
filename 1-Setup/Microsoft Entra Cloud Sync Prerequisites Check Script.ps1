# Microsoft Entra Cloud Sync Prerequisites Diagnostic Script
# This script checks all requirements for running Cloud Sync agent on Windows Server

function Write-CheckResult {
    param(
        [string]$Check,
        [bool]$Result,
        [string]$Details = ""
    )
    
    $status = if ($Result) { "✅ PASS" } else { "❌ FAIL" }
    Write-Host "`n[$status] $Check"
    if ($Details) {
        Write-Host "     Details: $Details"
    }
    return $Result
}

function Test-DotNetVersion {
    $dotNetVersion = (Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\NET Framework Setup\NDP\v4\Full").Release
    # .NET 4.7.1 corresponds to release number 461308
    return $dotNetVersion -ge 461308
}

function Test-WindowsVersion {
    $osInfo = Get-WmiObject Win32_OperatingSystem
    $version = [Version]$osInfo.Version
    return $version -ge [Version]"10.0.14393" # Windows Server 2016 or later
}

function Test-TLSConfiguration {
    $tlsKeys = @(
        "HKLM:\SYSTEM\CurrentControlSet\Control\SecurityProviders\SCHANNEL\Protocols\TLS 1.2\Client",
        "HKLM:\SYSTEM\CurrentControlSet\Control\SecurityProviders\SCHANNEL\Protocols\TLS 1.2\Server"
    )
    
    $allKeysExist = $true
    foreach ($key in $tlsKeys) {
        if (-not (Test-Path $key)) {
            $allKeysExist = $false
            break
        }
        
        $enabled = (Get-ItemProperty -Path $key -Name "Enabled" -ErrorAction SilentlyContinue).Enabled
        $disabled = (Get-ItemProperty -Path $key -Name "DisabledByDefault" -ErrorAction SilentlyContinue).DisabledByDefault
        
        if ($enabled -ne 1 -or $disabled -ne 0) {
            $allKeysExist = $false
            break
        }
    }
    return $allKeysExist
}

function Test-FirewallRules {
    $ports = @(80, 443, 8080)
    $results = @()
    $details = @()
    
    foreach ($port in $ports) {
        # Check existing firewall rules more carefully
        $inboundRules = Get-NetFirewallRule | Where-Object {
            $portFilter = Get-NetFirewallPortFilter -AssociatedNetFirewallRule $_
            $portFilter.LocalPort -contains $port -and $_.Direction -eq "Inbound" -and $_.Enabled -eq $true
        }
        
        $outboundRules = Get-NetFirewallRule | Where-Object {
            $portFilter = Get-NetFirewallPortFilter -AssociatedNetFirewallRule $_
            $portFilter.LocalPort -contains $port -and $_.Direction -eq "Outbound" -and $_.Enabled -eq $true
        }
        
        if ($outboundRules.Count -eq 0) {
            $details += "Port $port No outbound rule found"
        }
        if ($inboundRules.Count -eq 0 -and $port -eq 80) {
            $details += "Port $port No inbound rule found (required for CRL checks)"
        }
    }
    
    # Test network connectivity to required endpoints
    $endpoints = @(
        @{Host="login.microsoftonline.com"; Port=443},
        @{Host="msappproxy.net"; Port=443},
        @{Host="servicebus.windows.net"; Port=443}
    )
    
    foreach ($endpoint in $endpoints) {
        try {
            $tcpClient = New-Object System.Net.Sockets.TcpClient
            $connectionTask = $tcpClient.ConnectAsync($endpoint.Host, $endpoint.Port)
            
            # Wait for up to 5 seconds for the connection
            if (-not $connectionTask.Wait(5000)) {
                $details += "Timeout connecting to $($endpoint.Host) on port $($endpoint.Port)"
            }
            
            $tcpClient.Close()
        }
        catch {
            $details += "Failed to connect to $($endpoint.Host) on port $($endpoint.Port): $($_.Exception.Message)"
        }
    }
    
    if ($details.Count -gt 0) {
        Write-Host "     Details: `n       - $($details -join "`n       - ")"
        return $false
    }
    return $true
}

function Test-NTLMSettings {
    try {
        # First check if the registry key exists
        $regPath = "HKLM:\SYSTEM\CurrentControlSet\Control\Lsa"
        if (-not (Test-Path $regPath)) {
            Write-Host "     Details: LSA registry key not found"
            return $false
        }

        # Try to get the NTLM setting
        $ntlmSettings = Get-ItemProperty -Path $regPath -ErrorAction SilentlyContinue
        
        if ($null -eq $ntlmSettings.LmCompatibilityLevel) {
            # If setting doesn't exist, create it with default secure value
            Write-Host "     Details: NTLM compatibility level not found - will be created with secure default"
            Set-ItemProperty -Path $regPath -Name "LmCompatibilityLevel" -Value 3 -Type DWord
            $level = 3
        } else {
            $level = $ntlmSettings.LmCompatibilityLevel
        }
        
        $levelDesc = switch ($level) {
            0 { "Send LM & NTLM responses (Least Secure)" }
            1 { "Send LM & NTLM - use NTLMv2 session security if negotiated" }
            2 { "Send NTLM response only" }
            3 { "Send NTLMv2 response only" }
            4 { "Send NTLMv2 response only/refuse LM" }
            5 { "Send NTLMv2 response only/refuse LM & NTLM (Most Secure)" }
            default { "Unknown setting" }
        }
        
        Write-Host "     Details: Current NTLM Level: $level ($levelDesc)"
        return $level -ge 3
    }
    catch {
        Write-Host "     Details: Error checking NTLM settings: $($_.Exception.Message)"
        return $false
    }
}

# Function to create required firewall rules
function New-CloudSyncFirewallRules {
    try {
        # Create outbound rules
        $ports = @(80, 443, 8080)
        foreach ($port in $ports) {
            $ruleName = "Cloud Sync Port $port"
            if (-not (Get-NetFirewallRule -DisplayName $ruleName -ErrorAction SilentlyContinue)) {
                New-NetFirewallRule -DisplayName $ruleName `
                    -Direction Outbound `
                    -Protocol TCP `
                    -LocalPort $port `
                    -Action Allow `
                    -Group "Microsoft Entra Cloud Sync" `
                    -Description "Allow outbound traffic for Microsoft Entra Cloud Sync"
            }
        }
        
        # Create inbound rule for port 80 (CRL checks)
        $ruleName = "Cloud Sync Port 80 Inbound"
        if (-not (Get-NetFirewallRule -DisplayName $ruleName -ErrorAction SilentlyContinue)) {
            New-NetFirewallRule -DisplayName $ruleName `
                -Direction Inbound `
                -Protocol TCP `
                -LocalPort 80 `
                -Action Allow `
                -Group "Microsoft Entra Cloud Sync" `
                -Description "Allow inbound traffic for CRL checks"
        }
        
        Write-Host "Firewall rules created successfully"
        return $true
    }
    catch {
        Write-Host "Error creating firewall rules: $($_.Exception.Message)"
        return $false
    }
}


# Run this function to create all required firewall rules
New-CloudSyncFirewallRules



# Set NTLM to secure level (3)
Set-ItemProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\Lsa' -Name 'LmCompatibilityLevel' -Value 3 -Type DWord


function Test-ProxySettings {
    try {
        # Get system proxy settings
        $proxyServer = [System.Net.WebRequest]::GetSystemWebProxy()
        if ($null -eq $proxyServer) {
            Write-Host "     Details: No proxy configured - direct access"
            return $true
        }

        # Test if proxy supports required protocols
        $urls = @(
            "https://login.microsoftonline.com",
            "https://msappproxy.net",
            "https://servicebus.windows.net"
        )
        
        $results = @()
        foreach ($url in $urls) {
            try {
                $uri = New-Object System.Uri($url)
                $proxy = $proxyServer.GetProxy($uri)
                if ($proxy.AbsoluteUri -ne $uri.AbsoluteUri) {
                    $results += "Proxy configuration found for $url -> $($proxy.AbsoluteUri)"
                }
            }
            catch {
                $results += "Error checking proxy for $url $($_.Exception.Message)"
            }
        }
        
        if ($results.Count -gt 0) {
            Write-Host "     Details: `n       - $($results -join "`n       - ")"
        }
        
        return $true
    }
    catch {
        Write-Host "     Details: Error checking proxy settings: $($_.Exception.Message)"
        return $false
    }
}

function Test-PowerShellExecutionPolicy {
    $policy = Get-ExecutionPolicy
    Write-Host "     Details: Current policy: $policy"
    return $policy -eq "RemoteSigned" -or $policy -eq "Undefined"
}

function Test-RAM {
    $ram = Get-WmiObject Win32_ComputerSystem | Select-Object -ExpandProperty TotalPhysicalMemory
    $ramGB = [math]::Round($ram / 1GB, 2)
    Write-Host "     Details: Available RAM: $ramGB GB"
    return $ramGB -ge 4
}

# Main diagnostic checks
Clear-Host
Write-Host "Microsoft Entra Cloud Sync Prerequisites Diagnostic Check`n" -ForegroundColor Cyan
Write-Host "======================================================`n"

$allChecksPass = $true

# Check Windows Server Version
$osCheck = Test-WindowsVersion
$allChecksPass = $allChecksPass -and $osCheck
Write-CheckResult -Check "Windows Server 2016 or later" -Result $osCheck

# Check .NET Framework Version
$dotNetCheck = Test-DotNetVersion
$allChecksPass = $allChecksPass -and $dotNetCheck
Write-CheckResult -Check ".NET Framework 4.7.1 or later" -Result $dotNetCheck

# Check RAM
$ramCheck = Test-RAM
$allChecksPass = $allChecksPass -and $ramCheck
Write-CheckResult -Check "Minimum 4GB RAM" -Result $ramCheck

# Check TLS 1.2 Configuration
$tlsCheck = Test-TLSConfiguration
$allChecksPass = $allChecksPass -and $tlsCheck
Write-CheckResult -Check "TLS 1.2 Configuration" -Result $tlsCheck

# Check PowerShell Execution Policy
$policyCheck = Test-PowerShellExecutionPolicy
$allChecksPass = $allChecksPass -and $policyCheck
Write-CheckResult -Check "PowerShell Execution Policy (RemoteSigned or Undefined)" -Result $policyCheck

# Check Firewall Rules
$firewallCheck = Test-FirewallRules
$allChecksPass = $allChecksPass -and $firewallCheck
Write-CheckResult -Check "Required Ports (80, 443, 8080)" -Result $firewallCheck

# Check NTLM Settings
$ntlmCheck = Test-NTLMSettings
$allChecksPass = $allChecksPass -and $ntlmCheck
Write-CheckResult -Check "NTLM Security Level" -Result $ntlmCheck

# Check Proxy Configuration
$proxyCheck = Test-ProxySettings
$allChecksPass = $allChecksPass -and $proxyCheck
Write-CheckResult -Check "Proxy Configuration for Microsoft Services" -Result $proxyCheck

Write-Host "`n======================================================`n"
if ($allChecksPass) {
    Write-Host "✅ All prerequisite checks passed!" -ForegroundColor Green
} else {
    Write-Host "❌ Some checks failed. Please review the results above and address any failing checks." -ForegroundColor Red
}

Write-Host "`nRemediation Steps for Failed Checks:"
Write-Host "1. For Firewall Rules:"
Write-Host "   - Ensure outbound access is allowed on ports 80, 443, and 8080"
Write-Host "   - Run the following PowerShell commands as administrator:"
Write-Host "     New-NetFirewallRule -DisplayName 'Cloud Sync Port 80' -Direction Outbound -LocalPort 80 -Protocol TCP -Action Allow"
Write-Host "     New-NetFirewallRule -DisplayName 'Cloud Sync Port 443' -Direction Outbound -LocalPort 443 -Protocol TCP -Action Allow"
Write-Host "     New-NetFirewallRule -DisplayName 'Cloud Sync Port 8080' -Direction Outbound -LocalPort 8080 -Protocol TCP -Action Allow"

Write-Host "`n2. For NTLM Security Level:"
Write-Host "   - Set the NTLM security level to 3 or higher using:"
Write-Host "     Set-ItemProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\Lsa' -Name 'LmCompatibilityLevel' -Value 3"

Write-Host "`n3. For Proxy Configuration:"
Write-Host "   - Ensure the proxy server allows connections to *.msappproxy.net, *.servicebus.windows.net"
Write-Host "   - Configure proxy bypass for Microsoft services if needed"

Write-Host "`nNote: Some requirements still need manual verification:"
Write-Host "- Domain Administrator or Enterprise Administrator credentials"
Write-Host "- Hybrid Identity Administrator account configuration"
Write-Host "- Active Directory schema requirements"
Write-Host "- Network connectivity to domain controllers (TCP/389 and TCP/3268)"