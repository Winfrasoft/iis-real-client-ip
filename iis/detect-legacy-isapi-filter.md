# Detecting the legacy F5 X-Forwarded-For ISAPI filter

The F5 DevCentral community filter, commonly referred to as `F5XFFHttpModule`, was published as a community tool rather than a supported F5 product. It was last updated in **2009**, targeting the IIS 6 and IIS 7 era, and does not work on IIS 10 (Windows Server 2016 and later).

It still ranks well in search results and forum answers, so estates keep acquiring it, and older estates keep carrying it through Windows upgrades without anyone noticing it stopped working.

None of this is a criticism of F5 or the engineer who wrote it. A free tool maintained until 2009 owes nobody IIS 10 compatibility in 2026. The problem is purely that search engines still present it as the current answer.

## Is it installed?

Depending on how it was deployed it may appear as an ISAPI filter, a module, or both. From an elevated prompt:

```
cd %windir%\system32\inetsrv

appcmd list config /section:isapiFilters
appcmd list modules
```

In IIS Manager, the same information is under **ISAPI Filters** (at both server and site level) and **Modules**.

You are looking for an entry pointing at a DLL dated 2009 or earlier. **Check the file version and timestamp rather than trying to recognise the name**, which varies depending on how each estate deployed it:

```powershell
Get-ChildItem C:\Windows\System32\inetsrv -Filter *.dll |
    Where-Object LastWriteTime -lt '2012-01-01' |
    Select-Object Name, LastWriteTime,
                  @{N='FileVersion';E={$_.VersionInfo.FileVersion}} |
    Sort-Object LastWriteTime
```

Widen the path if your estate installed it elsewhere.

## How it fails

Rarely with a clean error. Expect one of:

**Nothing happens at all.** The filter is registered, IIS starts normally, and `c-ip` still shows the load balancer on every request. The most common outcome and the most confusing, because there is nothing in the event log to look at. This is routinely misdiagnosed as a proxy misconfiguration, sending people to re-check the BIG-IP where the setting was correct all along.

**The filter never loads.** ISAPI filters are native code, so a 32-bit build cannot load into a 64-bit IIS worker process. If the application pool has **Enable 32-Bit Applications** set to `False`, which is the default, an old 32-bit filter is simply never loaded.

Watch for the fix people reach for here: flipping **Enable 32-Bit Applications** to `True` so the filter loads. That changes the bitness of *every* application in that pool to accommodate an abandoned component. Not a good trade.

**The worker process is unstable.** Less common, but a native filter written against a much older IIS runs in-process, and a crash takes the application pool with it.

## Removing it

1. Remove both the ISAPI filter registration and the module entry, if both exist, at whichever level they were added (server or site).
2. Recycle the application pool.
3. If someone previously enabled **Enable 32-Bit Applications** solely for this filter, consider setting it back, after checking nothing else in the pool now depends on it.
4. Confirm the BIG-IP is still inserting the header. That side is unchanged and supported; see [`../proxy/f5-big-ip.md`](../proxy/f5-big-ip.md).
5. Deploy whichever replacement you have chosen from [`../README.md`](../README.md), and confirm `c-ip` shows real client addresses with [`../diagnostics/Get-IisClientIpBreakdown.ps1`](../diagnostics/Get-IisClientIpBreakdown.ps1).

## One thing the old filter did not do

It did not validate the forwarding chain against a trust list. Whatever replacement you pick, make sure it does, and add your BIG-IP's SNAT addresses to it. Without that check, correcting `c-ip` means anything able to reach IIS can write a chosen address into your audit trail.

Full guide: <https://winfrasoft.com/kb/f5-isapi-filter-iis-10-replacement/>
