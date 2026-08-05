# Detecting the legacy F5 X-Forwarded-For components

F5 published **two** IIS components on DevCentral, and they get conflated constantly:

| Component | Era | Installed as |
| --- | --- | --- |
| X-Forwarded-For **ISAPI filter** | The original, IIS 6 and IIS 7 | An ISAPI filter registration. Native code, no configuration. |
| **HTTP module** (`F5XFFHttpModule`) | Later, for IIS 7, once Microsoft steered people away from ISAPI filters | A module entry. Reads an optional `F5XFFHttpModule.ini` beside the DLL. |

`F5XFFHttpModule` names the HTTP module specifically. It is not another name for the ISAPI filter, though it is widely used as one.

Both were community tools rather than supported F5 products. F5 put the source on GitHub at [f5devcentral/f5-xforwarded-for](https://github.com/f5devcentral/f5-xforwarded-for) in October 2015 and **archived that repository in May 2016**, before Windows Server 2016 (which ships IIS 10) was generally available. It has not changed since.

Microsoft's guidance is that [neither works on IIS 10](https://learn.microsoft.com/en-us/answers/questions/776789/how-to-replace-c-ip-value-on-iis-log-in-windows-20). They still rank well in search results and forum answers, so estates keep acquiring them, and older estates keep carrying them through Windows upgrades without anyone noticing they stopped working.

## What the record actually says

Rather than assert it, here are the sources, including the one that cuts the other way:

- **Microsoft**, on Microsoft Q&A in March 2022: ["neither the unofficial F5XFFHttpModule nor the Advanced Logging Module for IIS7 will work in IIS10"](https://learn.microsoft.com/en-us/answers/questions/776789/how-to-replace-c-ip-value-on-iis-log-in-windows-20).
- **A field report**: an administrator running Exchange 2016 on Windows Server 2016 [reported in 2019](https://community.spiceworks.com/t/x-forwarded-for-iis-10-and-exchange-2016/723211) that the ISAPI filter caused IIS 10 to crash. One unreplicated report, so treat it as a caution rather than a certainty. The same post correctly notes that Advanced Logging was removed from IIS 10 and the ARR Helper was never released for it.
- **A counter-report**: in that same Microsoft thread, the original asker says they resolved their problem by installing an F5 module. No detail on which component or build, so it is hard to weigh, but it exists.

Whichever way that goes, the next point is not affected by it.

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

**The worker process crashes.** A native filter written against a much older IIS runs in-process, so a fault takes the application pool with it. This is the failure [reported on IIS 10 in 2019](https://community.spiceworks.com/t/x-forwarded-for-iis-10-and-exchange-2016/723211). One report, so not a certainty, but the most damaging of the three if it happens to you.

## Removing it

1. Remove both the ISAPI filter registration and the module entry, if both exist, at whichever level they were added (server or site).
2. Recycle the application pool.
3. If someone previously enabled **Enable 32-Bit Applications** solely for this filter, consider setting it back, after checking nothing else in the pool now depends on it.
4. Confirm the BIG-IP is still inserting the header. That side is unchanged and supported; see [`../proxy/f5-big-ip.md`](../proxy/f5-big-ip.md).
5. Deploy whichever replacement you have chosen from [`../README.md`](../README.md), and confirm `c-ip` shows real client addresses with [`../diagnostics/Get-IisClientIpBreakdown.ps1`](../diagnostics/Get-IisClientIpBreakdown.ps1).

## The problem that survives the compatibility question

**Neither component validates anything.** Both simply read the header and write it into the log. The [published source](https://github.com/f5devcentral/f5-xforwarded-for) contains no trust list, no allow-list, no notion of a known proxy and no chain validation of any kind, in either the ISAPI filter or the HTTP module.

That matters more than whether it loads. `X-Forwarded-For` is client-supplied. If anything can reach IIS directly, bypassing the BIG-IP, it can set the header to any value and the filter writes it into `c-ip` as fact. A forged entry then sits in your audit trail indistinguishable from a real one.

An audit trail that is confidently wrong is worse than one that is visibly wrong: a log full of load balancer addresses is obviously unhelpful and everyone works around it, whereas a log full of plausible client addresses is trusted. So whatever replacement you pick, make sure it validates the chain against proxies you have explicitly named, and add your BIG-IP's SNAT addresses to that list.

Full guide: <https://winfrasoft.com/kb/f5-isapi-filter-iis-10-replacement/>
