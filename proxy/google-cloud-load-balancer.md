# Google Cloud load balancer in front of IIS

**Short answer.** Google's documentation says the Application Load Balancer appends two addresses to `X-Forwarded-For`, the client then the load balancer, after any value the caller supplied, and that it does not verify anything before them. So the client is the **second address from the right**, not the first. IIS reads none of it, and `c-ip` records a Google front end address (Google documents 130.211.0.0/22 and 35.191.0.0/16 as the request source ranges for instance group backends). Log the header as a column to see the visitor, as below, or validate the chain to correct `c-ip` itself.

## Check what actually arrives

Log the header as a custom field on a test site and make one request through the proxy, with and without a made-up `X-Forwarded-For` of your own. Where this guide says the vendor documentation does not settle a point, that is the way to settle it.

```powershell
Add-WebConfigurationProperty -pspath 'MACHINE/WEBROOT/APPHOST' `
  -filter "system.applicationHost/sites/siteDefaults/logFile/customFields" `
  -name "." `
  -value @{logFieldName='X-Forwarded-For';sourceName='X-Forwarded-For';sourceType='RequestHeader'}
```

That adds a `cs(X-Forwarded-For)` column to the W3C log. It does not change `c-ip`.

## Then fix the IIS side

IIS reads none of these headers natively and the custom field leaves `c-ip` unchanged. See [`../README.md`](../README.md).

Full guide, with the sources for every vendor statement: <https://winfrasoft.com/kb/iis-real-client-ip-behind-google-cloud-load-balancer/>
