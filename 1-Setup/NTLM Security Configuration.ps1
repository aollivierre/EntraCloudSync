function Set-NTLMSecurity {
    param(
        [Parameter(Mandatory=$true)]
        [ValidateSet(0,1,2,3,4,5)]
        [int]$Level,
        
        [Parameter()]
        [switch]$DisableCompletely
    )
    
    $levelDescriptions = @{
        0 = "Least Secure - Sends LM and NTLM responses"
        1 = "Sends LM & NTLM - use NTLMv2 session security if negotiated"
        2 = "Sends NTLM response only"
        3 = "Sends NTLMv2 response only"
        4 = "Sends NTLMv2 response only/refuse LM"
        5 = "Sends NTLMv2 response only/refuse LM & NTLM (Most Secure)"
    }
    
    Write-Host "NTLM Security Configuration`n" -ForegroundColor Cyan
    Write-Host "Current Configuration:"
    
    # Get current setting
    $currentLevel = (Get-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\Lsa" -Name "LmCompatibilityLevel" -ErrorAction SilentlyContinue).LmCompatibilityLevel
    Write-Host "Current Level: $currentLevel - $($levelDescriptions[$currentLevel])`n"
    
    # Set new level
    Write-Host "Setting new security level..."
    Write-Host "Level $Level - $($levelDescriptions[$Level])"
    Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\Lsa" -Name "LmCompatibilityLevel" -Value $Level -Type DWord
    
    if ($DisableCompletely) {
        Write-Host "`nConfiguring additional settings to disable NTLM completely..."
        
        # Network Security: Restrict NTLM
        Write-Host "Setting 'Network Security: Restrict NTLM' to 'Deny All'..."
        Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\Lsa\MSV1_0" -Name "RestrictReceivingNTLMTraffic" -Value 2 -Type DWord
        Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\Lsa\MSV1_0" -Name "RestrictSendingNTLMTraffic" -Value 2 -Type DWord
        
        # Network security: LAN Manager authentication level
        Write-Host "Setting LAN Manager authentication level to refuse LM & NTLM..."
        Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\Lsa" -Name "LmCompatibilityLevel" -Value 5 -Type DWord
        
        # Network security: Minimum session security for NTLM SSP
        Write-Host "Configuring minimum session security..."
        Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\Lsa\MSV1_0" -Name "NTLMMinClientSec" -Value 537395200 -Type DWord
        Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\Lsa\MSV1_0" -Name "NTLMMinServerSec" -Value 537395200 -Type DWord
    }
    
    Write-Host "`nVerifying new configuration..."
    $newLevel = (Get-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\Lsa" -Name "LmCompatibilityLevel").LmCompatibilityLevel
    Write-Host "New Level: $newLevel - $($levelDescriptions[$newLevel])"
    
    Write-Host "`nNote: Some changes may require a system restart to take effect."
    if ($DisableCompletely) {
        Write-Host "`nWarning: NTLM has been completely disabled. Ensure Kerberos authentication is properly configured"
        Write-Host "         before disconnecting from the system to avoid lockout."
    }
}

# Example usage:
# To set secure level (3):
# Set-NTLMSecurity -Level 3

# To completely disable NTLM:
Set-NTLMSecurity -Level 5 -DisableCompletely