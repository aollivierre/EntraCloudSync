function Get-ServiceBusStatus {
    Write-Host "Azure Service Bus Endpoint Status Check`n" -ForegroundColor Cyan
    Write-Host "============================================`n"
    
    # List of public DNS servers to test resolution
    $dnsServers = @(
        @{Name="Google DNS"; IP="8.8.8.8"},
        @{Name="Cloudflare"; IP="1.1.1.1"},
        @{Name="OpenDNS"; IP="208.67.222.222"}
    )
    
    Write-Host "1. Testing DNS Resolution from Multiple Public DNS Servers:" -ForegroundColor Yellow
    foreach ($dns in $dnsServers) {
        try {
            $result = Resolve-DnsName -Name "servicebus.windows.net" -Server $dns.IP -Type A -ErrorAction Stop
            Write-Host "   $($dns.Name) ($($dns.IP)): SUCCESS - IP(s): $($result.IPAddress -join ', ')" -ForegroundColor Green
        }
        catch {
            Write-Host "   $($dns.Name) ($($dns.IP)): FAILED - $($_.Exception.Message)" -ForegroundColor Red
        }
    }

    Write-Host "`n2. Online Service Status Check Tools:" -ForegroundColor Yellow
    Write-Host "   You can verify the endpoint status using these online tools:"
    Write-Host "   - Down Detector: https://downdetector.com/status/azure"
    Write-Host "   - Azure Status: https://status.azure.com"
    Write-Host "   - Global DNS Checker: https://www.whatsmydns.net/#A/servicebus.windows.net"
    Write-Host "   - SSL Certificate Check: https://www.sslshopper.com/ssl-checker.html"
    
    Write-Host "`n3. Azure Service Bus Namespace Test:" -ForegroundColor Yellow
    Write-Host "   Try these alternative endpoints to test connectivity:"
    Write-Host "   - region.servicebus.windows.net"
    Write-Host "   Examples:"
    $regions = @("westus", "eastus", "westeurope", "northeurope", "southeastasia")
    foreach ($region in $regions) {
        $endpoint = "$region.servicebus.windows.net"
        try {
            $dns = Resolve-DnsName -Name $endpoint -Type A -ErrorAction Stop
            Write-Host "   - $endpoint : Resolves to $($dns.IPAddress -join ', ')" -ForegroundColor Green
        }
        catch {
            Write-Host "   - $endpoint : DNS resolution failed" -ForegroundColor Red
        }
    }

    Write-Host "`n4. Alternative Test Methods:" -ForegroundColor Yellow
    Write-Host "   Run these commands from a PowerShell prompt to test different aspects:"
    Write-Host "   Test DNS Resolution:"
    Write-Host "   nslookup servicebus.windows.net"
    Write-Host "`n   Test HTTPS Connection:"
    Write-Host "   Invoke-WebRequest -Uri https://servicebus.windows.net -UseBasicParsing"
    Write-Host "`n   Test TCP Connection:"
    Write-Host "   Test-NetConnection -ComputerName servicebus.windows.net -Port 443"
    
    Write-Host "`nNote: If all online tools show the service is available but you still can't connect,"
    Write-Host "      the issue is likely in your local network or firewall configuration."
}

# Run the status check
Get-ServiceBusStatus