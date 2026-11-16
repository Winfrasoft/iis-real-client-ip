# FortiWeb in front of IIS

**Short answer.** In reverse proxy mode FortiWeb opens its own connection to IIS, so `c-ip` records the FortiWeb address. Fortinet's CLI reference lists `x-forwarded-for-support` and `x-real-ip` for FortiWeb, both disabled by default, and its Administration Guide says FortiWeb adds the source IP of the connection to `X-Forwarded-For`, appending to any existing list. Turn on *Add X-Forwarded-For*, then log the header as a column, as below, or validate it to correct `c-ip` itself.

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

Full guide, with the sources for every vendor statement: <https://winfrasoft.com/kb/iis-real-client-ip-behind-fortiweb/>
