# Security

This is the most important page. Read it before you enable anything.

## What you are exposing

- **Root access with no authentication that we could see.** In our tests `adb connect DEVICE_IP:5555` gave a root shell with no password or pairing step. Verify this on your unit. Anyone who can reach that port can read and change everything on the device, including your Wi-Fi credentials (probably stored in plain text in `/data/cfg/wpa_supplicant.conf`; we did not open the file).
- **The microphone and speaker.** With root, anyone can record from the microphone or play sounds. This matters more if you build voice features.
- **Old software.** The kernel is the 4.19 series and OpenSSL 1.1.1 is in the image. The firmware is a single image with no package manager, so you cannot update individual parts, and no newer firmware was offered when we checked.
- **Secrets in `setting.ini`.** The MQTT password and `miio_key` are in plain text. Do not post the file.
- **An MQTT broker that accepts anonymous clients** (as in our test setup) lets any machine on your network publish to your topics.

## What the device still sends to Xiaomi's cloud

The device runs a Xiaomi "miio" cloud client (`miio_client`) alongside the
app's own Qingping/Cleargrass cloud connection. These are two different
vendors' services, not one. We confirmed this with a packet capture
(`tcpdump` or an equivalent, then opened in Wireshark) on a unit that was
never paired with any app or account, Qingping's or Xiaomi's, and that had
only had its Wi-Fi configured on the device's own screen.

The diagram below summarizes what we confirmed on the wire. Gray steps happen
locally, coral steps send something identifying in the clear, and the dashed
purple step is the one we could not read: we have a confirmed, negotiated TLS
session, but not its contents.

![Flow diagram: vendor_storage feeds device.conf, which is used in a plaintext gslb lookup to dns.io.mi.com, returning three IP addresses, followed by a TLS 1.2 handshake that sends the device ID in the clear, leading to an encrypted session whose contents were not recovered](images/xiaomi-cloud-dataflow.svg)

The first step shown, `vendor_storage` to `device.conf`, is the boot-time
recovery path, used only if `device.conf` is missing or incomplete; on a
working device it does not run. The factory process goes the other
direction first. See [how-it-works.md](how-it-works.md) for both
directions and for the factory tool that revealed this.

What we saw, in order:

1. **A plaintext lookup.** At startup the device sends an unencrypted HTTP
   request to `dns.io.mi.com` (Xiaomi's "GSLB" service), something like
   `GET /gslb?tver=2&id=YOUR_DEVICE_ID&dm=cn.ots.io.mi.com&model=cgllc.airm.cgs2&...`.
   This exposes your Mi Home device ID and the device model to anyone who
   can see the traffic. The reply is a short, signed JSON list of three
   server IP addresses to use next, all on Chinese cloud hosting (we saw
   addresses on Kingsoft Cloud and China Telecom ranges). The `dm=` value
   requests the mainland China ("cn") cluster, even for a device on a US
   network; we do not know whether that is fixed by model or set by
   something in the device's configuration.
2. **An encrypted session to one of those addresses**, over TLS 1.2 using
   `TLS_PSK_WITH_AES_128_GCM_SHA256`, a pre-shared-key cipher suite with no
   certificates involved. The device offers PSK suites first in its Client
   Hello, and the server picks one.
3. **The PSK identity, sent in cleartext as part of the handshake**, is the
   literal string `DID=YOUR_DEVICE_ID`. So even though the session content
   is encrypted, your device ID is visible on the wire twice: once in the
   step 1 lookup, and again in the step 2 handshake.

What we could not determine: the pre-shared key itself is not simply the
`key=` value from `device.conf` used as-is (we tried decrypting a capture
in Wireshark with that value as the PSK and it did not work), so some
derivation is involved that we did not reverse-engineer, and we cannot read
what is actually sent once the session is encrypted. Strings in the
`miio_client` binary (`local.status`, `local.time`, `local.country`,
`_internal.info`, and similar) suggest routine provisioning and status
traffic rather than anything unusual, and a companion script on the device
answers requests for the device's identity and current Wi-Fi details (SSID,
BSSID, signal strength, local IP) when asked over a local pipe, but we do
not know which of that, if any, leaves the device, since we could not read
the encrypted payload. Treat this as an open question, not a clean bill of
health.

Practical takeaways:

- The device identifies itself to Xiaomi's cloud on every boot or
  reconnect, with no pairing and no account, simply by being on a network
  with internet access.
- Blocking this by IP address is not reliable, since the three server
  addresses are handed out dynamically and can change. The one stable
  point is the DNS name `dns.io.mi.com`; a DNS-level block (Pi-hole,
  AdGuard Home, or similar) is more likely to stop it than a firewall rule
  on the changing IPs, though we have not tested that it is the only name
  involved.
- We do not know what, if anything, breaks if this connection is blocked.
  The device's own app and alarm features come from the Qingping/Cleargrass
  side, so we would not expect those to depend on Xiaomi's cloud, but we
  have not tested a device with this connection blocked.

If you want to look into this yourself: a packet capture is the direct way
in (see whether your router or an intermediate switch can mirror the
device's traffic, or capture on the device itself if a capture tool is
present). In Wireshark, filter on the device's IP and look at the TLS
Client Hello's cipher suites, and the identity field inside the Client Key
Exchange message for a PSK suite.

## Reducing the risk

- Put the device on an **IoT VLAN or separate SSID** if your router supports it.
- Allow it to reach only what it needs: your MQTT broker, DNS, and NTP (it runs `ntpd`, and blocking time sync lets the clock drift). Allow port 5555 only from your admin PC.
- Optionally block its other internet access, including the Xiaomi miio
  cloud connection described above. We left it running and did not test
  what stops working without it, so add this rule last and make it easy to
  undo.
- Turn debugging off when you are finished (the `is_adbd_enabled` switch). You will lose your way in; we have not tested how that interacts with our boot hooks.
- Give the broker logins and per-device users instead of `allow_anonymous true`.
- Do not expose the device or the broker to the internet.
- Check what is listening: `netstat -ltn` on the device.
