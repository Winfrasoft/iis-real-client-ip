# Detecting the legacy F5 X-Forwarded-For components

F5 published **two** IIS components on DevCentral, and they get conflated constantly:

| Component | Era | Installed as |
| --- | --- | --- |
| X-Forwarded-For **ISAPI filter** | The original, IIS 6 and IIS 7 | An ISAPI filter registration. Native code, no configuration. |
| **HTTP module** (`F5XFFHttpModule`) | Later, for IIS 7, once Microsoft steered people away from ISAPI filters | A module entry. Reads an optional `F5XFFHttpModule.ini` beside the DLL. |

`F5XFFHttpModule` names the HTTP module specifically. It is not another name for the ISAPI filter, though it is widely used as one.

Both were community tools rather than supported F5 products. F5 put the source on GitHub at [f5devcentral/f5-xforwarded-for](https://github.com/f5devcentral/f5-xforwarded-for) in October 2015 and **archived that repository in May 2016**, before Windows Server 2016 (which ships IIS 10) was generally available. It has not changed since.

Neither works on IIS 10. They still rank well in search results and forum answers, so estates keep acquiring them, and older estates keep carrying them through Windows upgrades without anyone noticing they stopped working.

None of this is a criticism of F5 or the engineers who wrote them. Publishing the source and archiving it is the right way to retire a community tool: it is a clear public signal and it leaves the code forkable. The problem is purely that search engines still present the original articles as the current answer.

## Is it installed?

Depending on how it was deployed it may appear as an ISAPI filter, a module, or both. From an elevated prompt:

```
cd %windir%\system32\inetsrv

appcmd list config /section:isapiFilters
appcmd list modules
```

In IIS Manager, the same information is under **ISAPI Filters** (at both server and site level) and **Modules**.

**Check the DLL's file version and timestamp rather than trying to recognise the name**, which varies depending on how each estate deployed it. An `F5XFFHttpModule.ini` sitting beside the DLL identifies the HTTP module rather than the older ISAPI filter:

```powershell
Get-ChildItem C:\Windows\System32\inetsrv -Filter *.dll |
    Where-Object LastWriteTime -lt '2017-01-01' |
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
