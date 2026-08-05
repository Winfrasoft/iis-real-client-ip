<#
.SYNOPSIS
    Checks which forwarded-client-IP headers reach a server, and
    whether a forged header is accepted.

.DESCRIPTION
    Two checks against a URL you control:

    1. Sends a normal request and reports which forwarded headers the
       response path suggests are in play. Use alongside a diagnostic
       endpoint on the server (see ../aspnet-core/Program.cs) that
       echoes back what it received.

    2. Sends a deliberately forged X-Forwarded-For and reports what the
       server did with it. If a request arriving directly at your
       origin, bypassing the proxy, has its forged header believed and
       written to your logs, your trust list is not doing its job.

    Run this against your OWN servers only. Check 2 is a configuration
    test of infrastructure you operate.

.PARAMETER Url
    The URL to test. Use a diagnostic endpoint that echoes headers if
    you have one, otherwise any page will do for check 2.

.PARAMETER SpoofedIp
    The address to forge. Defaults to a TEST-NET-1 address from
    RFC 5737, which is reserved for documentation and will never be a
    real client, so it is unmistakable in a log.

.EXAMPLE
    .\Test-ForwardedHeaders.ps1 -Url https://www.example.com/_whoami

.EXAMPLE
    # Against the origin directly, bypassing the CDN, to test trust:
    .\Test-ForwardedHeaders.ps1 -Url http://10.0.0.11/_whoami
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string] $Url,

    [string] $SpoofedIp = '192.0.2.111'
)

function Show-Response {
    param([string] $Label, $Response)
    Write-Host ""
    Write-Host $Label -ForegroundColor Cyan
    Write-Host ('-' * $Label.Length) -ForegroundColor Cyan
    Write-Host "HTTP $([int]$Response.StatusCode)"
    if ($Response.Content -and $Response.Content.Length -lt 2000) {
        Write-Host $Response.Content
    }
}

Write-Host "Testing $Url" -ForegroundColor White

# --- Check 1: a normal request -------------------------------------
try {
    $normal = Invoke-WebRequest -Uri $Url -UseBasicParsing -TimeoutSec 20
    Show-Response "1. Normal request" $normal
} catch {
    Write-Host "Normal request failed: $($_.Exception.Message)" -ForegroundColor Red
    return
}

# --- Check 2: a forged X-Forwarded-For -----------------------------
$headers = @{
    'X-Forwarded-For'  = $SpoofedIp
    'CF-Connecting-IP' = $SpoofedIp
    'True-Client-IP'   = $SpoofedIp
}

try {
    $spoofed = Invoke-WebRequest -Uri $Url -Headers $headers -UseBasicParsing -TimeoutSec 20
    Show-Response "2. Forged headers claiming $SpoofedIp" $spoofed
} catch {
    Write-Host "Forged request failed: $($_.Exception.Message)" -ForegroundColor Red
    return
}

Write-Host ""
Write-Host "Now check the server's IIS log for $SpoofedIp." -ForegroundColor Yellow
Write-Host ""
Write-Host "  If it appears in c-ip:" -ForegroundColor Yellow
Write-Host "    Your trust list is not being enforced. Anything able to reach"
Write-Host "    this server can write whatever address it likes into your logs."
Write-Host "    That is worse than logging the proxy, because a forged value is"
Write-Host "    indistinguishable from a real one after the fact."
Write-Host ""
Write-Host "  If it does not appear:" -ForegroundColor Yellow
Write-Host "    The header was correctly ignored from an untrusted source."
Write-Host ""
Write-Host "Run this from OUTSIDE the proxy path (straight at the origin) for"
Write-Host "the test to mean anything. Through the proxy, your proxy will"
Write-Host "usually overwrite the header and the check proves nothing."
Write-Host ""
Write-Host "Background: https://winfrasoft.com/kb/proxy-client-ip-headers/"
