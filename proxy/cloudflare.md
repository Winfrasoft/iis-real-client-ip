# Cloudflare in front of IIS

Cloudflare terminates the visitor's connection and passes the original address to your origin automatically. There is nothing to switch on at the Cloudflare end.

## Which header to read

| Header | Contents |
| --- | --- |
| `CF-Connecting-IP` | A single address: the visitor Cloudflare accepted the connection from. Cloudflare-specific. |
| `X-Forwarded-For` | The de facto standard chain. Contains the visitor plus any further hops. |
| `True-Client-IP` | Same value as `CF-Connecting-IP`. Historically an Enterprise-plan feature; the name originates with Akamai. |

`CF-Connecting-IP` and `True-Client-IP` carry the same thing in practice. Prefer `CF-Connecting-IP` if you are certain traffic can only arrive via Cloudflare, and `X-Forwarded-For` if you want a header your tooling already understands and a chain you can validate.

## The part that actually matters

Because these headers are trivially forgeable, **restrict your origin to Cloudflare's IP ranges**. Otherwise anyone who discovers your origin address can connect directly, set `CF-Connecting-IP` to anything, and your logs will record it as fact.

Cloudflare publish their ranges at <https://www.cloudflare.com/ips/>. Enforce them at the firewall, or with IIS IP Address and Domain Restrictions, or by using Cloudflare Tunnel so the origin has no public address at all.

Whatever reads the header on the IIS side should also validate against those ranges rather than trusting any sender. Locking the origin down and validating the chain are complementary; the first stops the connection, the second stops a bad value being believed if one gets through.

## A caution on IP ranges

Cloudflare's published ranges change. Whatever mechanism you use to enforce them needs refreshing, or you will eventually block legitimate traffic after an expansion. Automate the refresh or diary it.

## Then fix the IIS side

IIS reads none of these headers natively. See [`../README.md`](../README.md).

Full guide: <https://winfrasoft.com/kb/iis-real-client-ip-behind-cloudflare/>
