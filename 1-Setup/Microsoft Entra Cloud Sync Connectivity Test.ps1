function Test-CloudSyncConnectivity {
    Write-Host "Microsoft Entra Cloud Sync Connectivity Test`n" -ForegroundColor Cyan
    Write-Host "============================================`n"
    
    # Required ports and their purposes
    $ports = @(
        @{Port = 80; Description = "CRL Downloads and Certificate Validation"; Required = $true},
        @{Port = 443; Description = "Primary Service Communication"; Required = $true},
        @{Port = 8080; Description = "Agent Status Reporting (Optional)"; Required = $false}
    )
    
    # Required URLs and their purposes
    $urls = @(
        # Cloud Service Communication
        @{
            Category = "Cloud Service Communication"
            Endpoints = @(
                @{URL = "*.msappproxy.net"; TestURL = "msappproxy.net"; Port = 443},
                @{URL = "*.servicebus.windows.net"; TestURL = "servicebus.windows.net"; Port = 443}
            )
        },
        # Microsoft Services
        @{
            Category = "Microsoft Services"
            Endpoints = @(
                @{URL = "*.microsoftonline.com"; TestURL = "login.microsoftonline.com"; Port = 443},
                @{URL = "*.microsoft.com"; TestURL = "www.microsoft.com"; Port = 443},
                @{URL = "*.msappproxy.com"; TestURL = "msappproxy.com"; Port = 443},
                @{URL = "*.windowsazure.com"; TestURL = "management.windowsazure.com"; Port = 443}
            )
        },
        # Certificate Validation
        @{
            Category = "Certificate Validation"
            Endpoints = @(
                @{URL = "mscrl.microsoft.com"; TestURL = "mscrl.microsoft.com"; Port = 80},
                @{URL = "crl.microsoft.com"; TestURL = "crl.microsoft.com"; Port = 80},
                @{URL = "ocsp.msocsp.com"; TestURL = "ocsp.msocsp.com"; Port = 80},
                @{URL = "www.microsoft.com"; TestURL = "www.microsoft.com"; Port = 80}
            )
        },
        # Registration
        @{
            Category = "Registration"
            Endpoints = @(
                @{URL = "login.windows.net"; TestURL = "login.windows.net"; Port = 443}
            )
        }
    )

    # Test HTTP 1.1 and chunked encoding support
    function Test-ProxyCapabilities {
        Write-Host "Testing Proxy Capabilities:" -ForegroundColor Yellow
        try {
            $request = [System.Net.HttpWebRequest]::Create("https://login.microsoftonline.com")
            $request.Method = "GET"
            $request.ProtocolVersion = [System.Version]"1.1"
            
            Write-Host "HTTP 1.1 Support: " -NoNewline
            $response = $request.GetResponse()
            Write-Host "YES" -ForegroundColor Green
            
            Write-Host "Chunked Encoding: " -NoNewline
            if ($response.Headers["Transfer-Encoding"] -eq "chunked") {
                Write-Host "YES" -ForegroundColor Green
            } else {
                Write-Host "NOT DETECTED" -ForegroundColor Yellow
            }
            
            $response.Close()
        }
        catch {
            Write-Host "FAILED - $($_.Exception.Message)" -ForegroundColor Red
        }
        Write-Host ""
    }

    # Test port connectivity
    function Test-PortConnectivity {
        param($Endpoint, $Port, $Required = $true)
        
        try {
            $tcp = New-Object System.Net.Sockets.TcpClient
            $connect = $tcp.BeginConnect($Endpoint, $Port, $null, $null)
            $wait = $connect.AsyncWaitHandle.WaitOne(3000, $false)
            
            if ($wait) {
                try {
                    $tcp.EndConnect($connect)
                    Write-Host "SUCCESS" -ForegroundColor Green
                    return $true
                }
                catch {
                    Write-Host "FAILED - Connection error" -ForegroundColor Red
                    return $false
                }
            }
            else {
                Write-Host "FAILED - Timeout" -ForegroundColor Red
                return $false
            }
        }
        catch {
            Write-Host "FAILED - $($_.Exception.Message)" -ForegroundColor Red
            return $false
        }
        finally {
            if ($tcp) { $tcp.Close() }
        }
    }

    # Test DNS resolution
    function Test-DNSResolution {
        param($Hostname)
        
        try {
            $dns = Resolve-DnsName -Name $Hostname -ErrorAction Stop
            Write-Host "SUCCESS - $($dns.IP4Address -join ', ')" -ForegroundColor Green
            return $true
        }
        catch {
            Write-Host "FAILED - $($_.Exception.Message)" -ForegroundColor Red
            return $false
        }
    }

    # Main testing sequence
    Write-Host "1. Testing Required Ports:`n" -ForegroundColor Yellow
    foreach ($port in $ports) {
        Write-Host "Port $($port.Port) ($($port.Description)):"
        Write-Host "  Testing outbound connectivity to login.microsoftonline.com... " -NoNewline
        $result = Test-PortConnectivity "login.microsoftonline.com" $port.Port
        if (-not $result -and $port.Required) {
            $global:testsFailed = $true
        }
    }

    Write-Host "`n2. Testing URL Categories:`n" -ForegroundColor Yellow
    foreach ($category in $urls) {
        Write-Host "$($category.Category):" -ForegroundColor Cyan
        foreach ($endpoint in $category.Endpoints) {
            Write-Host "`n$($endpoint.URL):"
            Write-Host "  DNS Resolution... " -NoNewline
            $dnsResult = Test-DNSResolution $endpoint.TestURL
            
            Write-Host "  Port $($endpoint.Port) Connectivity... " -NoNewline
            $portResult = Test-PortConnectivity $endpoint.TestURL $endpoint.Port
            
            if (-not ($dnsResult -and $portResult)) {
                $global:testsFailed = $true
            }
        }
    }

    Write-Host "`n3. Testing Proxy Configuration:" -ForegroundColor Yellow
    Test-ProxyCapabilities

    # Generate summary and recommendations
    Write-Host "`nSummary and Recommendations:" -ForegroundColor Yellow
    if ($global:testsFailed) {
        Write-Host "`nSome tests failed. Recommended actions:"
        Write-Host "1. Verify firewall rules allow outbound traffic to:"
        Write-Host "   - Ports 80, 443, and 8080"
        Write-Host "   - All Microsoft Entra endpoints listed above"
        Write-Host "2. Check DNS resolution for failed endpoints"
        Write-Host "3. Verify network service account has necessary permissions"
        Write-Host "4. If using a proxy:"
        Write-Host "   - Ensure HTTP 1.1 support is enabled"
        Write-Host "   - Verify chunked encoding is supported"
        Write-Host "   - Add required URLs to bypass list or allowed destinations"
    }
    else {
        Write-Host "`nAll connectivity tests passed successfully!" -ForegroundColor Green
    }
}

# Run the test
Test-CloudSyncConnectivity