# AWS load balancers in front of IIS

What you need to do depends on which load balancer you are using, and for one of them the answer is genuinely "nothing".

## Application Load Balancer (ALB)

Adds `X-Forwarded-For` containing the client IP on HTTP and HTTPS listeners **by default**. No configuration needed at the AWS end.

The ALB also sends `X-Forwarded-Proto` and `X-Forwarded-Port`, which matter if your application generates absolute URLs or redirects, since it would otherwise see plain HTTP.

## Classic Load Balancer (ELB)

Same behaviour for HTTP and HTTPS listeners: `X-Forwarded-For` is added automatically.

For **TCP** listeners there is no HTTP layer to add a header to. Either move to an HTTP listener or use Proxy Protocol, which is a different mechanism that whatever reads it must explicitly support.

## Network Load Balancer (NLB)

An NLB operates at layer 4 and supports **client IP preservation**, which keeps the original source address at the network level. When that is on, the client address reaches IIS as the actual TCP peer, so `c-ip` is already correct and there is nothing to fix.

This is worth checking before you change anything. If you are behind an NLB with client IP preservation enabled and `c-ip` still shows a private address, the problem is somewhere else in your path, likely another proxy between the NLB and IIS.

Note the defaults differ by target type and how the NLB was created, so confirm the setting on your target group rather than assuming.

## Trust list

Use the load balancer's **private** addresses, the ones in your VPC subnets, not the public-facing address. That is what IIS sees as the connection peer.

ALB addresses are not static; they move within the subnets assigned to the load balancer. Trusting the relevant VPC subnet CIDR is usually more robust than listing individual addresses, which will eventually go stale.

## Then fix the IIS side

The header arriving is only half of it. IIS does not read `X-Forwarded-For`, so `c-ip` still shows the load balancer. See [`../README.md`](../README.md).

Full guide: <https://winfrasoft.com/kb/iis-real-client-ip-behind-aws-load-balancer/>
