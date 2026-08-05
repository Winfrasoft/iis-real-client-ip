<#
.SYNOPSIS
    Counts distinct c-ip values in an IIS W3C log to show whether the
    log is recording real visitors or your proxy.

.DESCRIPTION
    Reads the most recently written log file for a site, locates the
    c-ip column from the #Fields: header rather than assuming a fixed
    position, and reports the most common values.

    A healthy internet-facing site returns a long tail of distinct
    addresses. A handful of values covering every request means c-ip
    is recording your infrastructure, not your visitors.

.PARAMETER LogPath
    Folder holding the log files. Defaults to the W3SVC1 site.

.PARAMETER Top
    How many of the most common addresses to show. Default 10.

.EXAMPLE
    .\Get-IisClientIpBreakdown.ps1

.EXAMPLE
    .\Get-IisClientIpBreakdown.ps1 -LogPath C:\inetpub\logs\LogFiles\W3SVC2 -Top 20
#>
[CmdletBinding()]
param(
    [string] $LogPath = 'C:\inetpub\logs\LogFiles\W3SVC1',
    [int]    $Top     = 10
)

if (-not (Test-Path $LogPath)) {
    throw "Log folder not found: $LogPath. Check the site ID in IIS Manager; the number after W3SVC is the site ID."
}

$log = Get-ChildItem -Path $LogPath -Filter *.log -File |
       Sort-Object LastWriteTime | Select-Object -Last 1

if (-not $log) { throw "No .log files in $LogPath." }

Write-Host "Reading $($log.FullName)" -ForegroundColor Cyan

# The #Fields: line names the columns in order. Read it rather than
# assuming a position: a server with custom fields enabled will not
# match the default layout.
$fieldLine = Select-String -Path $log.FullName -Pattern '^#Fields:' |
             Select-Object -Last 1

if (-not $fieldLine) { throw "No #Fields: line found. Is this a W3C-format log?" }

$fields = ($fieldLine.Line -replace '^#Fields:\s*') -split '\s+'
$index  = [Array]::IndexOf($fields, 'c-ip')

if ($index -lt 0) {
    throw "No c-ip field in this log. It has been switched off in the site's logging configuration (IIS Manager > Logging > Select Fields)."
}

$values = Get-Content -Path $log.FullName |
          Where-Object { $_ -and $_[0] -ne '#' } |
          ForEach-Object { ($_ -split '\s+')[$index] }

$total    = @($values).Count
$distinct = ($values | Sort-Object -Unique).Count

if ($total -eq 0) { throw "No request lines in the log yet." }

Write-Host ""
Write-Host "Requests:          $total"
Write-Host "Distinct c-ip:     $distinct"
Write-Host ""

$values | Group-Object | Sort-Object Count -Descending |
    Select-Object -First $Top @{N='Count';E={$_.Count}},
                              @{N='Percent';E={'{0,5:N1}%' -f (100 * $_.Count / $total)}},
                              @{N='c-ip';E={$_.Name}} |
    Format-Table -AutoSize

# A crude but useful signal: if the top few addresses account for
# almost everything, you are looking at infrastructure.
$topShare = 100 * (($values | Group-Object |
             Sort-Object Count -Descending |
             Select-Object -First 3 |
             Measure-Object Count -Sum).Sum) / $total

Write-Host ""
if ($topShare -gt 90 -and $distinct -lt 20) {
    Write-Host ("Top 3 addresses account for {0:N1}% of requests across only {1} distinct values." -f $topShare, $distinct) -ForegroundColor Yellow
    Write-Host "That is the signature of a reverse proxy. c-ip is recording your infrastructure." -ForegroundColor Yellow
    Write-Host "See https://winfrasoft.com/kb/iis-c-ip-log-field/" -ForegroundColor Yellow
} else {
    Write-Host ("Top 3 addresses account for {0:N1}% of requests across {1} distinct values." -f $topShare, $distinct) -ForegroundColor Green
    Write-Host "That distribution looks like real client traffic." -ForegroundColor Green
}
