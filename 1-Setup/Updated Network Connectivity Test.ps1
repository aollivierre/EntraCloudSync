function Test-CloudSyncNetworkAccess {
    Write-Host "`nMicrosoft Entra Cloud Sync Network Connectivity Test`n" -ForegroundColor Cyan
    Write-Host "==================================================="

    # Test network adapter and DNS configuration first
    Write-Host "`nChecking Network Configuration:" -ForegroundColor Yellow
    $networkAdapters = Get-NetAdapter | Where-Object { $_.Status -eq 'Up' }
    foreach ($adapter in $networkAdapters) {
        $ipConfig = Get-NetIPConfiguration -InterfaceIndex $adapter.ifIndex
        Write-Host "`nAdapter: $($adapter.Name)"
        Write-Host "Status: $($adapter.Status)"
        Write-Host "IP Address: $($ipConfig.IPv4Address.IPAddress)"
        Write-Host "DNS Servers: $($ipConfig.DNSServer.ServerAddresses -join ', ')"
    }

    # Required endpoints
    $endpoints = @(
        @{
            Host = "login.microsoftonline.com"
            Port = 443
            Description = "Authentication endpoint"
            Required = $true
        },
        @{
            Host = "graph.windows.net"
            Port = 443
            Description = "Graph API endpoint"
            Required = $true
        },
        @{
            Host = "servicebus.windows.net"
            Port = 443
            Description = "Service Bus endpoint"
            Required = $true
        }
    )

    Write-Host "`nTesting Required Endpoints:" -ForegroundColor Yellow
    foreach ($endpoint in $endpoints) {
        Write-Host "`nTesting $($endpoint.Host):$($endpoint.Port) ($($endpoint.Description))"
        
        # Test DNS resolution
        try {
            $dns = Resolve-DnsName -Name $endpoint.Host -Type A -ErrorAction Stop
            Write-Host "DNS Resolution : SUCCESS" -ForegroundColor Green
            Write-Host "IP Addresses  : $($dns.IP4Address -join ', ')"
            
            # Try traceroute to see network path
            Write-Host "Network Path  :"
            $trace = Test-NetConnection -ComputerName $endpoint.Host -TraceRoute
            $trace.TraceRoute | ForEach-Object { Write-Host "              $_" }
        }
        catch {
            Write-Host "DNS Resolution : FAILED - $($_.Exception.Message)" -ForegroundColor Red
            continue
        }

        # Test TCP connection with timeout
        try {
            $tcp = New-Object System.Net.Sockets.TcpClient
            $connect = $tcp.BeginConnect($endpoint.Host, $endpoint.Port, $null, $null)
            $wait = $connect.AsyncWaitHandle.WaitOne(3000, $false)
            
            if ($wait) {
                try {
                    $tcp.EndConnect($connect)
                    Write-Host "TCP Connection: SUCCESS" -ForegroundColor Green
                }
                catch {
                    Write-Host "TCP Connection: FAILED - $($_.Exception.Message)" -ForegroundColor Red
                }
            }
            else {
                Write-Host "TCP Connection: FAILED - Connection timed out" -ForegroundColor Red
            }
        }
        catch {
            Write-Host "TCP Connection: FAILED - $($_.Exception.Message)" -ForegroundColor Red
        }
        finally {
            if ($tcp) {
                $tcp.Close()
            }
        }
    }

    # Check Windows Firewall
    Write-Host "`nChecking Windows Firewall:" -ForegroundColor Yellow
    $ports = @(80, 443, 8080)
    foreach ($port in $ports) {
        $outboundRules = Get-NetFirewallRule -Direction Outbound -Enabled True -ErrorAction SilentlyContinue | 
            Get-NetFirewallPortFilter -ErrorAction SilentlyContinue | 
            Where-Object { $_.LocalPort -eq $port -or $_.LocalPort -eq "Any" }
        
        if ($outboundRules) {
            Write-Host "Port $port : Outbound rules found" -ForegroundColor Green
        }
        else {
            Write-Host "Port $port : No outbound rules found" -ForegroundColor Red
        }
    }

    Write-Host "`nRecommendations:" -ForegroundColor Yellow
    Write-Host "1. If DNS resolution fails:"
    Write-Host "   - Verify DNS servers are accessible and can resolve external domains"
    Write-Host "   - Try adding 8.8.8.8 as a secondary DNS server temporarily for testing"
    
    Write-Host "`n2. If TCP connection fails:"
    Write-Host "   - Check if there's a network firewall blocking outbound HTTPS traffic"
    Write-Host "   - Verify no security software is blocking outbound connections"
    Write-Host "   - Review network routing to ensure traffic can reach Microsoft endpoints"
    
    Write-Host "`n3. Required ports:"
    Write-Host "   - Ensure outbound access is allowed for ports 80, 443, and 8080"
    Write-Host "   - Run the following commands to create firewall rules if needed:"
    Write-Host "     New-NetFirewallRule -DisplayName 'Cloud Sync 443' -Direction Outbound -LocalPort 443 -Protocol TCP -Action Allow"
    Write-Host "     New-NetFirewallRule -DisplayName 'Cloud Sync 80' -Direction Outbound -LocalPort 80 -Protocol TCP -Action Allow"
    Write-Host "     New-NetFirewallRule -DisplayName 'Cloud Sync 8080' -Direction Outbound -LocalPort 8080 -Protocol TCP -Action Allow"
}

# Run the network test
Test-CloudSyncNetworkAccess