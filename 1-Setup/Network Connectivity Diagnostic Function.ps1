function Test-CloudSyncConnectivity {
    Write-Host "`nMicrosoft Entra Cloud Sync Network Connectivity Test`n" -ForegroundColor Cyan
    Write-Host "==================================================="

    # Required endpoints to test
    $endpoints = @(
        @{
            Host = "login.microsoftonline.com"
            Port = 443
            Description = "Authentication endpoint"
        },
        @{
            Host = "msappproxy.net"
            Port = 443
            Description = "App Proxy endpoint"
        },
        @{
            Host = "servicebus.windows.net"
            Port = 443
            Description = "Service Bus endpoint"
        }
    )

    foreach ($endpoint in $endpoints) {
        Write-Host "`nTesting connection to $($endpoint.Host):$($endpoint.Port) ($($endpoint.Description))..."
        
        # Test DNS resolution first
        try {
            $dnsResult = Resolve-DnsName -Name $endpoint.Host -ErrorAction Stop
            Write-Host "  DNS Resolution: SUCCESS" -ForegroundColor Green
            Write-Host "  IP Address(es): $($dnsResult.IP4Address -join ', ')"
        }
        catch {
            Write-Host "  DNS Resolution: FAILED" -ForegroundColor Red
            Write-Host "  Error: $($_.Exception.Message)"
            continue
        }

        # Test ICMP (ping)
        try {
            $pingResult = Test-Connection -ComputerName $endpoint.Host -Count 1 -ErrorAction Stop
            Write-Host "  ICMP Test: SUCCESS" -ForegroundColor Green
            Write-Host "  Response time: $($pingResult.ResponseTime)ms"
        }
        catch {
            Write-Host "  ICMP Test: FAILED (Note: This may be blocked by firewall)" -ForegroundColor Yellow
        }

        # Test TCP connection
        $tcpClient = $null
        try {
            $tcpClient = New-Object System.Net.Sockets.TcpClient
            $connectTask = $tcpClient.ConnectAsync($endpoint.Host, $endpoint.Port)
            
            if ($connectTask.Wait(5000)) {
                Write-Host "  TCP Connection: SUCCESS" -ForegroundColor Green
            } else {
                Write-Host "  TCP Connection: FAILED (Timeout)" -ForegroundColor Red
            }
        }
        catch {
            Write-Host "  TCP Connection: FAILED" -ForegroundColor Red
            Write-Host "  Error: $($_.Exception.Message)"
        }
        finally {
            if ($tcpClient) {
                $tcpClient.Close()
            }
        }

        # Test SSL/TLS connection
        try {
            $req = [System.Net.HttpWebRequest]::Create("https://$($endpoint.Host)")
            $req.Timeout = 5000
            $req.AllowAutoRedirect = $false
            $response = $req.GetResponse()
            Write-Host "  SSL/TLS Connection: SUCCESS" -ForegroundColor Green
            $response.Close()
        }
        catch {
            Write-Host "  SSL/TLS Connection: FAILED" -ForegroundColor Red
            Write-Host "  Error: $($_.Exception.Message)"
        }
    }

    Write-Host "`nChecking proxy configuration..."
    $proxy = [System.Net.WebRequest]::GetSystemWebProxy()
    if ($proxy) {
        Write-Host "System proxy detected:"
        Write-Host "  Checking if proxy is bypassed for required endpoints..."
        foreach ($endpoint in $endpoints) {
            $uri = "https://$($endpoint.Host)"
            $proxyUri = $proxy.GetProxy($uri)
            if ($proxyUri.ToString() -eq $uri) {
                Write-Host "  $($endpoint.Host) - Direct connection" -ForegroundColor Green
            } else {
                Write-Host "  $($endpoint.Host) - Via proxy: $proxyUri" -ForegroundColor Yellow
            }
        }
    } else {
        Write-Host "No system proxy configured - using direct connection" -ForegroundColor Green
    }

    Write-Host "`nRecommended actions:"
    Write-Host "1. If DNS resolution fails:"
    Write-Host "   - Verify DNS server configuration"
    Write-Host "   - Check if the server can resolve other public domains"
    
    Write-Host "2. If TCP/SSL connection fails:"
    Write-Host "   - Verify outbound firewall rules allow traffic to these endpoints"
    Write-Host "   - Check if a proxy server is required and properly configured"
    Write-Host "   - Verify no SSL inspection is blocking the connections"
    
    Write-Host "3. For proxy environments:"
    Write-Host "   - Add these domains to proxy bypass list: *.msappproxy.net, *.servicebus.windows.net"
    Write-Host "   - Verify proxy server supports TLS 1.2"
}

# Run the connectivity test
Test-CloudSyncConnectivity