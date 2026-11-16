# Fastly in front of IIS

**Short answer.** Fastly's X-Forwarded-For reference says an existing value is preserved, so Fastly appends to the chain and anything the caller sent stays at the left. Fastly also documents a proprietary `Fastly-Client-IP` header, which its page says is not protected from modification at the edge. IIS reads neither, and `c-ip` records a Fastly address. Log the header as a column to see the visitor, as below, or validate the chain against Fastly's published ranges to correct `c-ip` itself.

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

Full guide, with the sources for every vendor statement: <https://winfrasoft.com/kb/iis-real-client-ip-behind-fastly/>
