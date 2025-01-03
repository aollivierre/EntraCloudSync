function Get-DetailedProxySettings {
    Write-Host "Checking Proxy Settings From Multiple Sources:`n" -ForegroundColor Cyan
    
    # 1. Check Internet Settings in Registry
    Write-Host "1. Windows Internet Settings (Registry):" -ForegroundColor Yellow
    $internetSettings = Get-ItemProperty -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings' -ErrorAction SilentlyContinue
    Write-Host "   ProxyEnable: $($internetSettings.ProxyEnable)"
    Write-Host "   ProxyServer: $($internetSettings.ProxyServer)"
    Write-Host "   ProxyOverride: $($internetSettings.ProxyOverride)"
    
    # 2. Check System Web Proxy
    Write-Host "`n2. System.Net WebProxy Settings:" -ForegroundColor Yellow
    $proxy = [System.Net.WebRequest]::GetSystemWebProxy()
    Write-Host "   System Proxy Detected: $($proxy -ne $null)"
    if ($proxy) {
        try {
            $testUrl = "https://login.microsoftonline.com"
            $proxyUri = $proxy.GetProxy($testUrl)
            Write-Host "   Proxy for $testUrl : $proxyUri"
        } catch {
            Write-Host "   Error getting proxy details: $($_.Exception.Message)"
        }
    }
    
    # 3. Check WinHTTP Settings
    Write-Host "`n3. WinHTTP Settings:" -ForegroundColor Yellow
    $winhttp = netsh winhttp show proxy
    Write-Host "   $($winhttp | Out-String)"
    
    # 4. Check Environment Variables
    Write-Host "4. Proxy-related Environment Variables:" -ForegroundColor Yellow
    Write-Host "   HTTP_PROXY: $($env:HTTP_PROXY)"
    Write-Host "   HTTPS_PROXY: $($env:HTTPS_PROXY)"
    Write-Host "   NO_PROXY: $($env:NO_PROXY)"
}

# Run the detailed check
Get-DetailedProxySettings