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