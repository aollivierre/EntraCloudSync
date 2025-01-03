# Script to restore NTLM settings and RDP access
function Restore-NTLMAndRDP {
    Write-Host "Restoring NTLM and RDP Security Settings..." -ForegroundColor Yellow
    
    try {
        # Restore NTLM to default secure settings
        Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\Lsa" -Name "LmCompatibilityLevel" -Value 2 -Type DWord
        
        # Ensure NTLM is not restricted
        Remove-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\Lsa\MSV1_0" -Name "RestrictReceivingNTLMTraffic" -ErrorAction SilentlyContinue
        Remove-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\Lsa\MSV1_0" -Name "RestrictSendingNTLMTraffic" -ErrorAction SilentlyContinue
        
        # Reset NTLMMinClientSec and NTLMMinServerSec to default values
        Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\Lsa\MSV1_0" -Name "NTLMMinClientSec" -Value 536870912 -Type DWord
        Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\Lsa\MSV1_0" -Name "NTLMMinServerSec" -Value 536870912 -Type DWord
        
        # Ensure RDP authentication is properly configured
        Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server\WinStations\RDP-Tcp" -Name "SecurityLayer" -Value 1
        Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server\WinStations\RDP-Tcp" -Name "UserAuthentication" -Value 1
        
        Write-Host "Settings restored successfully. Please restart the server." -ForegroundColor Green
        Write-Host "After restart, RDP access should be restored." -ForegroundColor Green
        
        $restart = Read-Host "Would you like to restart the server now? (Y/N)"
        if ($restart -eq "Y") {
            Restart-Computer -Force
        }
    }
    catch {
        Write-Host "Error restoring settings: $($_.Exception.Message)" -ForegroundColor Red
    }
}

# Run the restoration
Restore-NTLMAndRDP