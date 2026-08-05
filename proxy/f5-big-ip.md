# F5 BIG-IP in front of IIS

A BIG-IP applies SNAT by default, so IIS sees the connection coming from the F5's SNAT or self IP and logs that in `c-ip`. The client address is not lost, it just needs to be inserted into a header.

## The supported way: the HTTP profile

This is one checkbox and it is fully supported by F5. Prefer it over an iRule.

1. In the BIG-IP configuration utility, go to **Local Traffic → Profiles → Services → HTTP**.
2. Open the HTTP profile attached to your virtual server. If it is the parent `http` profile, create a child profile first rather than editing the parent, so the change does not apply estate-wide.
3. Tick **Insert X-Forwarded-For**.
4. Apply, and confirm the profile is the one assigned to the virtual server under **Local Traffic → Virtual Servers**.

There is a `tmsh` equivalent, but it is deliberately not reproduced here: attaching a profile from the command line means restating the virtual server's entire profile list, and a copy-pasted example that omits an APM, ASM or persistence profile you happen to have will silently detach it. The GUI path above is unambiguous and cannot do that. If you work in `tmsh` routinely, you already know the command.

## The iRule alternative

Only if you need conditional behaviour the profile setting cannot express:

```tcl
when HTTP_REQUEST {
    HTTP::header insert X-Forwarded-For [IP::client_addr]
}
```

Note this **inserts** unconditionally, so a request that already carries an `X-Forwarded-For` ends up with two. Use `HTTP::header replace` if you intend to discard whatever arrived, and be deliberate about which you want: replacing throws away upstream hops, inserting preserves a chain you may not trust.

## Verifying

From a client, request a page and check the header actually arrives at IIS. `../diagnostics/Test-ForwardedHeaders.ps1` does this against a URL of your choosing.

## Then fix the IIS side

Inserting the header is only half the job. IIS does not read it, so `c-ip` still shows the F5 until something on the IIS side acts on the header. See [`../README.md`](../README.md).

**If you are looking for the old DevCentral ISAPI filter** (`F5XFFHttpModule`), it was last updated in 2009 and does not work on IIS 10. See [`../iis/detect-legacy-isapi-filter.md`](../iis/detect-legacy-isapi-filter.md).

Full guide: <https://winfrasoft.com/kb/iis-real-client-ip-behind-f5-big-ip/>
