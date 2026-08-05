# IIS Application Request Routing (ARR)

ARR acting as a reverse proxy means your backend content servers log the ARR server's address instead of your visitors. ARR does forward the client address, and the header name is configurable.

## Check the setting

1. In IIS Manager on the **ARR server**, select the server node.
2. Open **Application Request Routing Cache**.
3. In the Actions pane, choose **Server Proxy Settings**.
4. Confirm **Preserve client IP in the following header** is set to `X-Forwarded-For`.

If someone has changed that field to a custom name, whatever reads the header on the backend has to be told the same name.

## Which server gets what

This trips people up often enough to be worth stating plainly:

| Server | What goes here |
| --- | --- |
| The **ARR** server | The proxy setting above. Nothing else. |
| Each **backend content** server | Whatever reads the header and fixes the IIS log. |

Installing the IIS-side component on the ARR server instead of the content servers is a common mistake and produces no visible change on the servers whose logs you were trying to fix.

## Trust

The ARR server's address is what the backend sees as the connection peer, so that is the address to put in your trust list on each content server. Because backend servers usually sit on a private network reachable only through ARR, this is a straightforward list: the ARR server or servers, and nothing else.

If a backend content server is also reachable directly, anything that can reach it can forge the header, so the trust list is doing real work rather than being a formality.

Full guide: <https://winfrasoft.com/kb/iis-real-client-ip-behind-arr/>
