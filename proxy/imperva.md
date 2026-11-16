# Imperva Cloud WAF in front of IIS

**Short answer.** Imperva's Customer Setup Checklist says that by default Imperva inserts the original client IP into two request headers, `X-Forwarded-For` and `Incap-Client-IP`. IIS reads neither, and its `c-ip` field is filled from the TCP connection, so it records an Imperva address. Log the header as a column to see the visitor, as below, or use something that validates the header against Imperva's published ranges to put the visitor into `c-ip` itself.

## Check what actually arrives

Log the header as a custom field on a test site and make one request through the proxy, with and without a made-up `X-Forwarded-For` of your own. Where this guide says the vendor documentation does not settle a point, that is the way to settle it.

```powershell
Add-WebConfigurationProperty -pspath 'MACHINE/WEBROOT/APPHOST' `
  -filter "system.applicationHost/sites/siteDefaults/logFile/customFields" `
  -name "." `
  -value @{logFieldName='Incap-Client-IP';sourceName='Incap-Client-IP';sourceType='RequestHeader'}
```

That adds a `cs(Incap-Client-IP)` column to the W3C log. It does not change `c-ip`.

## Then fix the IIS side

IIS reads none of these headers natively and the custom field leaves `c-ip` unchanged. See [`../README.md`](../README.md).

Full guide, with the sources for every vendor statement: <https://winfrasoft.com/kb/iis-real-client-ip-behind-imperva/>
