# Akamai in front of IIS

Akamai terminates the visitor's connection at the edge and your origin sees an Akamai server. Two headers can carry the original address, and only one of them is on by default.

## Which header to read

| Header | Default | Contents |
| --- | --- | --- |
| `X-Forwarded-For` | On | The de facto standard chain. Akamai passes an inbound value through and appends rather than replacing it, so anything the caller sent survives to your origin. |
| `True-Client-IP` | **Off** | A single address. Added only when **Send True Client IP Header** is enabled in the **Origin Server** behavior in Property Manager. |

In Property Manager the relevant settings are `enableTrueClientIp`, `trueClientIpHeader` and `trueClientIpClientSetting`.

## True-Client-IP is not automatically the safer choice

A single clean address reads as more authoritative than a comma-separated chain. In practice it is the chain you can validate and the single value you have to take on trust.

- **The name is configurable.** Akamai's documentation notes the default name is used "unless you set a custom name for the header in the **True Client IP Header Name** field". Anything that hardcodes `True-Client-IP` breaks silently on a property where someone renamed it.
- **Clients may be allowed to set it.** A separate **Allow Clients To Set True Client IP Header** toggle determines, in Akamai's words, "if the client name for this header is passed through and accepted, or whether to apply the value you defined in the True Client IP Header Name field instead". Where that is on, a caller can send the header and have it reach your origin. Akamai's page describes the behaviour without drawing out the consequence, so it is easy to leave in a state nobody has reviewed.
- **There is no chain to check.** With `X-Forwarded-For` you can read from the right and stop at the first address that is not a proxy you control. One value gives you nothing to evaluate.

Use whichever your property actually sends. If both arrive they should agree, and `X-Forwarded-For` is the more portable choice.

## The part that actually matters

Both headers are trivially forgeable, so **restrict your origin to the addresses Akamai connects from**. Otherwise anyone who finds your origin can connect directly, set either header to anything, and your logs record it as fact.

Akamai's mechanism for this is **Site Shield**, which its documentation describes as leveraging "a defined set of IP subnet ranges to route traffic to the origin", so that allowlisting those ranges at the perimeter "helps prevent attackers from bypassing cloud-based defenses and directly targeting the application origin". Site Shield Stable CIDRs uses larger, more static blocks so the firewall ACL needs updating less often.

Whatever reads the header on the IIS side should validate against the same set rather than trusting any sender. Locking the origin down and validating the chain are complementary: the first stops the connection, the second stops a bad value being believed if one gets through.

## If Akamai is not the only hop

Akamai in front of an on-premises load balancer or WAF, then IIS, is common and fine. Each hop appends the address it received the connection from, so `X-Forwarded-For` arrives with several entries. Every internal hop needs to be in whatever trust list you validate against, not just the edge, otherwise the walk stops at your own equipment and logs that instead.

## Then fix the IIS side

IIS reads none of these headers natively. See [`../README.md`](../README.md).

Full guide: <https://winfrasoft.com/kb/iis-real-client-ip-behind-akamai/>
