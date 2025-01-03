function Test-ServiceBusRegionalEndpoints {
    Write-Host "Testing Azure Service Bus Regional Endpoints`n" -ForegroundColor Cyan
    Write-Host "============================================`n"
    
    $endpoints = @(
        @{
            Region = "East US"
            Endpoint = "eastus.servicebus.windows.net"
            IP = "137.116.48.46"
        },
        @{
            Region = "West Europe"
            Endpoint = "westeurope.servicebus.windows.net"
            IP = "40.68.39.15"
        },
        @{
            Region = "Global"
            Endpoint = "servicebus.windows.net"
            IP = "65.55.54.16"
        }
    )
    
    foreach ($endpoint in $endpoints) {
        Write-Host "Testing $($endpoint.Region) ($($endpoint.Endpoint))" -ForegroundColor Yellow
        Write-Host "IP Address: $($endpoint.IP)"
        
        # Test TCP connection
        Write-Host "TCP Test (443):"
        try {
            $tcpClient = New-Object System.Net.Sockets.TcpClient
            $connection = $tcpClient.BeginConnect($endpoint.IP, 443, $null, $null)
            $success = $connection.AsyncWaitHandle.WaitOne(3000, $true)
            
            if ($success) {
                Write-Host "  Direct IP Connection: SUCCESS" -ForegroundColor Green
            } else {
                Write-Host "  Direct IP Connection: FAILED (Timeout)" -ForegroundColor Red
            }
        }
        catch {
            Write-Host "  Direct IP Connection: FAILED - $($_.Exception.Message)" -ForegroundColor Red
        }
        finally {
            if ($tcpClient) { $tcpClient.Close() }
        }
        
        # Test HTTPS
        Write-Host "HTTPS Test:"
        try {
            $result = Invoke-WebRequest -Uri "https://$($endpoint.Endpoint)" -UseBasicParsing -TimeoutSec 5
            Write-Host "  HTTPS Connection: SUCCESS (Status: $($result.StatusCode))" -ForegroundColor Green
        }
        catch {
            Write-Host "  HTTPS Connection: FAILED - $($_.Exception.Message)" -ForegroundColor Red
        }
        
        # Try traceroute
        Write-Host "Network Path:"
        $trace = Test-NetConnection -ComputerName $endpoint.IP -TraceRoute
        $trace.TraceRoute | ForEach-Object { 
            if ($_ -eq "0.0.0.0") {
                Write-Host "  * * *"
            } else {
                Write-Host "  $_" 
            }
        }
        Write-Host ""
    }
    
    Write-Host "`nRecommendations:"
    Write-Host "1. If all endpoints fail:"
    Write-Host "   - Check if your network firewall is blocking HTTPS (443) to Azure IP ranges"
    Write-Host "   - Try adding these specific IPs to your firewall allowlist:"
    Write-Host "     * 65.55.54.16 (Global)"
    Write-Host "     * 137.116.48.46 (East US)"
    Write-Host "     * 40.68.39.15 (West Europe)"
    
    Write-Host "`n2. If some endpoints work but others don't:"
    Write-Host "   - Configure your Azure Service Bus to use the working region"
    Write-Host "   - Contact your network team to allow access to all Azure Service Bus IP ranges"
}

# Run the test
Test-ServiceBusRegionalEndpoints