# Real client IP in IIS behind a proxy

Working configuration samples for preserving the originating client IP address when Microsoft IIS sits behind a reverse proxy, load balancer or CDN.

If every line in your IIS log shows the same handful of addresses, this repository is for you.

## The problem in one paragraph

A reverse proxy terminates the client's TCP connection and opens its own to IIS. IIS records the peer of the connection it accepted, so the `c-ip` field in the W3C log contains the proxy, not the visitor. Most proxies pass the original address along in the `X-Forwarded-For` request header, but **IIS never reads it**. Microsoft did not build X-Forwarded-For handling into IIS logging, so the header arrives, sits in the request, and is discarded.

That means there are two separate halves to fix, and they fail independently:

1. **The proxy has to send the header.** Some do automatically, some need a line of config. See [`proxy/`](proxy/).
2. **Something on the IIS side has to read it.** This is the half people miss. See below.

## Which half is broken?

Run [`diagnostics/Get-IisClientIpBreakdown.ps1`](diagnostics/Get-IisClientIpBreakdown.ps1) on the web server. It reads your newest IIS log and counts the distinct `c-ip` values.

| What you see | What it means |
| --- | --- |
| A long tail of distinct addresses | Nothing is wrong. You are not behind a proxy, or it is already handled. |
| A few addresses covering every request | Normal symptom. Continue below. |
| No `c-ip` column at all | The field is switched off in the site's logging configuration. |

Then check whether the header is even arriving, with [`diagnostics/Test-ForwardedHeaders.ps1`](diagnostics/Test-ForwardedHeaders.ps1). If it is not, fix the proxy first, because nothing on the IIS side can help until the header is there.

## Configuring the proxy

| Proxy | Sends `X-Forwarded-For` by default? | Config |
| --- | --- | --- |
| Nginx | No | [`proxy/nginx.conf`](proxy/nginx.conf) |
| HAProxy | No | [`proxy/haproxy.cfg`](proxy/haproxy.cfg) |
| Apache (`mod_proxy`) | Yes | [`proxy/apache-httpd.conf`](proxy/apache-httpd.conf) |
| IIS ARR | Yes, configurable | [`proxy/iis-arr.md`](proxy/iis-arr.md) |
| F5 BIG-IP | No, one checkbox | [`proxy/f5-big-ip.md`](proxy/f5-big-ip.md) |
| AWS ALB / Classic ELB | Yes | [`proxy/aws-elb.md`](proxy/aws-elb.md) |
| Azure App Gateway / Front Door | Yes | [`proxy/azure.md`](proxy/azure.md) |
| Cloudflare | Yes | [`proxy/cloudflare.md`](proxy/cloudflare.md) |
| Akamai | `X-Forwarded-For` yes; `True-Client-IP` only if enabled | [`proxy/akamai.md`](proxy/akamai.md) |

## Fixing the IIS side

Which option is right depends entirely on **what reads your logs**. This is the decision most guides skip, so here is the whole field at a glance:

| Option | Standard `c-ip` field | Trust validation | Status |
| --- | --- | --- | --- |
| ASP.NET Core `UseForwardedHeaders` | Unchanged. Fixes the application's view only | Yes, via `KnownProxies` / `KnownIPNetworks` | Built into ASP.NET Core, free |
| IIS custom log field | Unchanged. Adds a separate `cs(X-Forwarded-For)` column | None. Header logged verbatim | Native to IIS 8.5+, free |
| IIS Advanced Logging | Bypassed. Wrote to its own log file | None | Discontinued by Microsoft |
| Legacy F5 DevCentral ISAPI filter / `F5XFFHttpModule` | Rewrote it | **None at all** | Community tools; [archived by F5 in 2016](https://github.com/f5devcentral/f5-xforwarded-for); [Microsoft says they do not work on IIS 10](https://learn.microsoft.com/en-us/answers/questions/776789/how-to-replace-c-ip-value-on-iis-log-in-windows-20) |
| Write your own ISAPI filter | Rewrites it | Whatever you implement | You own the chain-walking, trust list, IPv6 edge cases and every Windows Server upgrade |
| [Winfrasoft X-Forwarded-For for IIS](https://winfrasoft.com/products/x-forwarded-for/) | Rewrites it | Yes, via a Proxy Trust List | Commercial, IIS 10 on Windows Server 2016–2025 |

The three rows worth taking seriously today are the first two and the last. The detail on each follows.

### 1. Your application needs the real IP (ASP.NET Core)

If you only care that your own code sees the right address, for authentication, rate limiting, or application-level logging, ASP.NET Core has this built in and it costs nothing. See [`aspnet-core/`](aspnet-core/).

The trap: `KnownProxies` defaults to loopback only, so the middleware works on a developer machine and silently does nothing in production. `aspnet-core/Program.cs` shows the correct setup, including the dual-stack IPv6 gotcha and the .NET 10 `KnownIPNetworks` change.

**This does not touch the IIS log.** It changes what your application sees, nothing more.

### 2. You want the address in the log and control everything that reads it

IIS 8.5 and later can add a custom log field sourced from a request header, giving you a `cs(X-Forwarded-For)` column. Free, native, no third-party component. See [`iis/Add-ForwardedForLogField.ps1`](iis/Add-ForwardedForLogField.ps1).

Two limits worth knowing before you commit to it:

- It **adds a column**; `c-ip` still shows the proxy. Anything keyed to `c-ip` (most SIEM connectors, geo-IP tooling, packaged log analysers) is unaffected and still reports your load balancer.
- There is **no trust validation**. Whatever the header contains is logged verbatim, so anything able to reach IIS directly can forge it.

### 3. `c-ip` itself has to be correct

If a SIEM, a compliance requirement, or a packaged reporting tool is involved, the standard field has to hold the real address, because those tools key off `c-ip` and often cannot be told otherwise. That needs a filter that rewrites the field as IIS records it, validating the forwarding chain against a list of trusted proxies.

The historically common answer was one of F5's two DevCentral community components: the X-Forwarded-For ISAPI filter, or the later `F5XFFHttpModule` HTTP module. F5 archived the source in May 2016, before Windows Server 2016 shipped, and [Microsoft's guidance is that neither works on IIS 10](https://learn.microsoft.com/en-us/answers/questions/776789/how-to-replace-c-ip-value-on-iis-log-in-windows-20), so if you find one recommended in a forum thread, check the thread's age.

The more important point is that **neither validates the forwarding chain** — the published source has no trust list of any kind, so a forged header is written into `c-ip` as fact. That is true whether or not you can get one running. [`iis/detect-legacy-isapi-filter.md`](iis/detect-legacy-isapi-filter.md) covers how to tell which one you have, what the sources actually say, and why it fails silently.

The practical appeal of rewriting the field rather than adding a column is that **nothing downstream changes**. Both the old F5 filter and any modern equivalent write to the same standard `c-ip` field, so your SIEM connector, log shipper, geo-IP lookup and reporting keep working exactly as they did, with no parser to author and no correlation rules to rewrite.

For a maintained option, see [X-Forwarded-For for IIS](https://winfrasoft.com/products/x-forwarded-for/) (IIS 10 on Windows Server 2016–2025). Writing your own module is also viable; be aware you are taking on the chain-walking logic, trust-list validation, IPv6 edge cases and maintenance for every Windows Server upgrade.

## A note on trust

Every approach here depends on a header that any client can set. Correcting `c-ip` from an unvalidated header does not improve your audit trail, it makes it confidently wrong, which is worse than visibly wrong.

Whatever you use, validate the chain against a list of proxies you actually trust, and parse it **from the right**. The rightmost entry was added by your nearest trusted hop; the leftmost is whatever the client claimed. [`diagnostics/Test-ForwardedHeaders.ps1`](diagnostics/Test-ForwardedHeaders.ps1) includes a spoofing check you can run against your own servers to confirm your trust list is doing its job.

## Background reading

Longer explanations of the specifics, all vendor-neutral:

- [The `c-ip` field in IIS logs](https://winfrasoft.com/kb/iis-c-ip-log-field/)
- [Which client IP header does your proxy send?](https://winfrasoft.com/kb/proxy-client-ip-headers/)
- [ASP.NET Core `UseForwardedHeaders` behind a proxy](https://winfrasoft.com/kb/aspnet-core-forwarded-headers/)
- [Replacing the F5 X-Forwarded-For ISAPI filter on IIS 10](https://winfrasoft.com/kb/f5-isapi-filter-iis-10-replacement/)
- [Why SIEM and compliance tooling needs `c-ip`](https://winfrasoft.com/kb/iis-client-ip-siem-compliance/)

## Contributing

Corrections and additional proxy configurations are welcome, particularly for proxies not covered here (NetScaler, Kemp, Akamai, Fastly, Traefik, Envoy). Open a pull request with a config you have actually run, and note the product version you tested against.

## Who maintains this

Maintained by [Winfrasoft](https://winfrasoft.com), who sell a commercial ISAPI filter for option 3 above. Everything in `proxy/`, `aspnet-core/`, `diagnostics/` and the native IIS custom log field script is free, uses no Winfrasoft software, and works regardless of what you choose for the log-rewriting half. Issues and pull requests are read.

## Licence

MIT. See [LICENSE](LICENSE).
