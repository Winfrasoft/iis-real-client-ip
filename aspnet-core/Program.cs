// ASP.NET Core behind a reverse proxy: recovering the real client IP.
//
// This fixes what your APPLICATION sees. It does not change the c-ip
// field in the IIS W3C log, which IIS writes from the TCP connection
// before your application runs. If you need the log itself correct,
// see ../README.md.
//
// Tested shape: .NET 6 through .NET 10 minimal hosting.

using System.Net;
using Microsoft.AspNetCore.HttpOverrides;

var builder = WebApplication.CreateBuilder(args);

builder.Services.Configure<ForwardedHeadersOptions>(options =>
{
    options.ForwardedHeaders =
        ForwardedHeaders.XForwardedFor | ForwardedHeaders.XForwardedProto;

    // ---------------------------------------------------------------
    // THE ONE THAT CATCHES EVERYONE
    //
    // The defaults are:
    //     KnownProxies  = [ ::1 ]           (IPv6 loopback)
    //     KnownNetworks = [ 127.0.0.0/8 ]   (IPv4 loopback)
    //
    // So the middleware works on a dev machine, where the proxy is
    // local, and silently does nothing in production, where it is a
    // different host. No error, no warning: the middleware sees an
    // untrusted forwarder and declines to rewrite anything.
    //
    // Load these from configuration rather than hard-coding them; see
    // appsettings.json in this folder for the pattern.
    //
    // Parse them explicitly, as below. Binding a section straight onto
    // the options, e.g.
    //     builder.Services.Configure<ForwardedHeadersOptions>(
    //         builder.Configuration.GetSection("ForwardedHeaders"));
    // with ForwardedHeaders__KnownProxies__0=10.0.0.5 in the environment
    // binds ForwardLimit and ForwardedHeaders but leaves KnownProxies,
    // KnownNetworks and KnownIPNetworks at their loopback defaults, with
    // no error. Tested on .NET 8.0.31 and 10.0.12. The loop below reads
    // the same values from any source, so TrustedProxies__0=10.0.0.5 as
    // an environment variable works.
    // ---------------------------------------------------------------

    foreach (var ip in builder.Configuration
                 .GetSection("TrustedProxies").Get<string[]>() ?? [])
    {
        options.KnownProxies.Add(IPAddress.Parse(ip));
    }

    // A subnet instead of individual addresses, for proxy pools whose
    // membership changes. Pick the form matching your .NET version:
    //
    //   .NET 10+   options.KnownIPNetworks.Add(
    //                  System.Net.IPNetwork.Parse("10.0.0.0/24"));
    //
    //   .NET 9 and earlier
    //              options.KnownNetworks.Add(
    //                  new IPNetwork(IPAddress.Parse("10.0.0.0"), 24));
    //
    // In .NET 10 both KnownNetworks and the old
    // Microsoft.AspNetCore.HttpOverrides.IPNetwork are obsolete and
    // raise warning ASPDEPR005. If your editor reports IPNetwork as an
    // ambiguous reference, that is System.Net.IPNetwork colliding with
    // the HttpOverrides one: qualify it, or move to KnownIPNetworks
    // and drop the HttpOverrides using directive.

    // Number of trusted hops to walk back through. Default is 1, so
    // only the rightmost entry is processed. Behind a CDN in front of
    // a load balancer you resolve to the intermediate proxy unless you
    // raise this AND trust every hop explicitly.
    options.ForwardLimit = 1;

    // If your proxy sends something other than X-Forwarded-For:
    //     options.ForwardedForHeaderName = "CF-Connecting-IP";
    // Only one header name is read at a time.

    // DO NOT do this, however many forum answers suggest it:
    //     options.KnownProxies.Clear();
    //     options.KnownNetworks.Clear();
    // It "works" by trusting any forwarder, so anyone who can reach
    // the app can forge a client address and your logs, rate limits
    // and audit trail will believe them. It converts a silent no-op
    // into a silent spoofing hole.
});

var app = builder.Build();

// Must run BEFORE anything that reads the client IP or the scheme.
// Placed after UseAuthentication, UseHttpsRedirection or your request
// logging, those components have already decided using the proxy's
// address.
app.UseForwardedHeaders();

app.UseAuthentication();
app.UseAuthorization();

// Diagnostic endpoint. Remove before production, or protect it.
//
// Hit this through the proxy and compare the two values. If they are
// identical, the middleware is not rewriting: the connection address
// is not matching anything in KnownProxies/KnownNetworks.
//
// If RemoteIpAddress reads as ::ffff:10.0.0.5, that is the IPv4
// proxy 10.0.0.5 arriving on a dual-stack socket. Trust it as plain
// 10.0.0.5: since ASP.NET Core 2.2 the middleware maps IPv4-mapped
// addresses back to IPv4 before checking KnownProxies and the network
// lists (aspnet/BasicMiddleware#358). The reverse does not hold, so an
// entry added as ::ffff:10.0.0.5 will not match a plain IPv4 connection.
app.MapGet("/_whoami", (HttpContext ctx) => Results.Json(new
{
    RemoteIpAddress = ctx.Connection.RemoteIpAddress?.ToString(),
    Scheme          = ctx.Request.Scheme,
    XForwardedFor   = ctx.Request.Headers["X-Forwarded-For"].ToString(),
    XOriginalFor    = ctx.Request.Headers["X-Original-For"].ToString(),
}));

app.Run();
