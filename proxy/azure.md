# Azure Application Gateway and Front Door in front of IIS

Both services forward the client address automatically. Neither needs switching on. The catch is that they do not agree on which header to use.

## Application Gateway

Adds `X-Forwarded-For` containing the client IP, and appends the source port, so entries look like:

```
X-Forwarded-For: 203.0.113.45:52310
```

**That port suffix is the thing that breaks naive parsing.** Code that splits on `:` to strip it will mangle every IPv6 address, which contains colons of its own. Split on the last colon only, or parse properly.

Application Gateway also sends `X-Forwarded-Proto` and `X-Original-Host`.

## Front Door

Sends `X-Forwarded-For`, and also `X-Azure-ClientIP`, which holds a single address with no chain and no port. If you are only ever behind Front Door, `X-Azure-ClientIP` is the simpler value to consume.

`X-Azure-SocketIP` also exists and holds the address of the socket Front Door accepted, which differs from `X-Azure-ClientIP` when an upstream proxy is involved. For "who is the visitor", `X-Azure-ClientIP` is the one you want.

## Lock down the origin

Both services are reachable only over the public internet unless you restrict the origin. If your IIS servers have public addresses, anyone who finds them can bypass Azure entirely and set whatever headers they like.

- **Application Gateway**: place the backends in a VNet with an NSG permitting traffic only from the gateway subnet.
- **Front Door**: restrict to the `AzureFrontDoor.Backend` service tag, and validate the `X-Azure-FDID` header against your own Front Door ID. The service tag alone permits *any* Front Door instance, including one an attacker creates pointing at your origin, so the FDID check is what makes it specific to you.

## Trust list

Use the address range IIS actually sees as the connection peer: the Application Gateway subnet, or the Front Door backend range. As with AWS, a subnet CIDR ages better than individual addresses.

## Then fix the IIS side

IIS reads none of these headers natively. See [`../README.md`](../README.md).

Full guide: <https://winfrasoft.com/kb/iis-real-client-ip-behind-azure/>
