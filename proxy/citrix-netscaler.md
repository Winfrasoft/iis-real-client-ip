# Citrix NetScaler in front of IIS

**Short answer.** By default NetScaler connects to your servers from one of its own addresses, a subnet IP (SNIP), so IIS logs that in `c-ip`. NetScaler's *Insert Client IP Address* option adds the real client to a request header; per service it is `set service <name> -CIP ENABLED X-Forwarded-For`. Name the header explicitly, because the NetScaler page we read does not state a default. IIS still ignores it, so log it as a column, as below, or validate it to correct `c-ip`.

## On the NetScaler

Insert the client address into a header you name, per service. Name the header explicitly; the page we read does not state a default.

```
set service svc-iis-01 -CIP ENABLED X-Forwarded-For
```

USIP is the alternative that makes the connection itself come from the client, so `c-ip` is correct without a header. Citrix documents that it requires the server gateway to be a NetScaler-owned SNIP and that, in current releases, HTTP connections are not reused while it is on.

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

Full guide, with the sources for every vendor statement: <https://winfrasoft.com/kb/iis-real-client-ip-behind-citrix-netscaler/>
