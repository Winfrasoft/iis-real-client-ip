<#
.SYNOPSIS
    Adds X-Forwarded-For as a custom W3C log field on an IIS site.

.DESCRIPTION
    Native IIS 8.5+ feature. Free, no third-party component. Adds a
    cs(X-Forwarded-For) column to the site's W3C log.

    READ THIS BEFORE USING IT. Two limits decide whether this is the
    right answer for you:

    1. It ADDS A COLUMN. c-ip still shows the proxy. Every SIEM
       connector, geo-IP lookup and compliance parser keyed to c-ip is
       unaffected and continues reporting your load balancer. The new
       column sits at the end of the line, outside their field
       mappings, and many cannot be reconfigured at all.

    2. There is NO TRUST VALIDATION. Whatever the header contains is
       logged verbatim. Anything able to reach IIS directly can forge
       it, and a forged entry is indistinguishable from a real one.

    If you own the log analysis end to end and can repoint it, this may
    be all you need. If a SIEM or a compliance requirement is involved,
    it usually is not. See ../README.md for the alternative.

.PARAMETER SiteName
    The IIS site. Defaults to 'Default Web Site'.

.PARAMETER FieldName
    Column name in the log. Defaults to 'X-Forwarded-For'.

.PARAMETER HeaderName
    Request header to read. Change this for CF-Connecting-IP,
    True-Client-IP, X-Azure-ClientIP and so on.

.EXAMPLE
    .\Add-ForwardedForLogField.ps1

.EXAMPLE
    .\Add-ForwardedForLogField.ps1 -SiteName 'Contoso' -HeaderName 'CF-Connecting-IP'

.NOTES
    Run elevated. Requires the WebAdministration module (IIS
    Management Scripts and Tools).
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [string] $SiteName   = 'Default Web Site',
    [string] $FieldName  = 'X-Forwarded-For',
    [string] $HeaderName = 'X-Forwarded-For'
)

$ErrorActionPreference = 'Stop'

if (-not ([Security.Principal.WindowsPrincipal] `
          [Security.Principal.WindowsIdentity]::GetCurrent()
         ).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    throw "Run this elevated."
}

Import-Module WebAdministration

if (-not (Test-Path "IIS:\Sites\$SiteName")) {
    throw "Site not found: $SiteName. Available: $((Get-ChildItem IIS:\Sites).Name -join ', ')"
}

$filter = "system.applicationHost/sites/site[@name='$SiteName']/logFile/customFields"

# The site must be logging in W3C format for custom fields to apply.
$format = (Get-ItemProperty "IIS:\Sites\$SiteName" -Name logFile.logFormat).Value
if ($format -ne 'W3C') {
    throw "Site '$SiteName' is logging in $format format. Custom fields require W3C. Change it in IIS Manager > Logging."
}

$existing = @(Get-WebConfigurationProperty -PSPath 'MACHINE/WEBROOT/APPHOST' `
                -Filter $filter -Name 'Collection' -ErrorAction SilentlyContinue)

if ($existing | Where-Object { $_.logFieldName -eq $FieldName }) {
    Write-Host "Field '$FieldName' already present on '$SiteName'. Nothing to do." -ForegroundColor Yellow
    return
}

if ($PSCmdlet.ShouldProcess($SiteName, "Add custom log field '$FieldName' from header '$HeaderName'")) {

    Add-WebConfigurationProperty -PSPath 'MACHINE/WEBROOT/APPHOST' `
        -Filter $filter -Name '.' -Value @{
            logFieldName = $FieldName
            sourceName   = $HeaderName
            sourceType   = 'RequestHeader'
        }

    Write-Host "Added cs($FieldName) to '$SiteName', sourced from the $HeaderName header." -ForegroundColor Green
    Write-Host ""
    Write-Host "The column applies to NEW log files. Recycle the application pool," -ForegroundColor Cyan
    Write-Host "or wait for the next log rollover, then check the #Fields: line."   -ForegroundColor Cyan
    Write-Host ""
    Write-Host "Remember: c-ip is UNCHANGED and still shows your proxy."            -ForegroundColor Yellow
    Write-Host "https://winfrasoft.com/kb/iis-c-ip-log-field/"                      -ForegroundColor Yellow
}

<#
    appcmd equivalent, if you prefer it:

    appcmd.exe set config /section:sites ^
      /+"[name='Default Web Site'].logFile.customFields.[logFieldName='X-Forwarded-For',sourceName='X-Forwarded-For',sourceType='RequestHeader']" ^
      /commit:apphost

    To remove:

    Remove-WebConfigurationProperty -PSPath 'MACHINE/WEBROOT/APPHOST' `
      -Filter "system.applicationHost/sites/site[@name='Default Web Site']/logFile/customFields" `
      -Name '.' -AtElement @{logFieldName='X-Forwarded-For'}
#>
