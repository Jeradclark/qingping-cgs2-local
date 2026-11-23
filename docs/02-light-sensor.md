# 02. Light sensor to MQTT and Home Assistant

The ambient-light reading, which the device does not publish, arrives on an MQTT topic whenever it changes. This is verified on one unit: the script, the boot hook and the Home Assistant entity work, and the value matches a phone light meter in lux.

This guide is independent of [01-local-mqtt.md](01-local-mqtt.md): it only needs a shell and a broker.

## Findings

- The device has an OPT3004 light sensor (named in the driver), used for auto brightness. The app writes its value to `/userdata/etc/debug/light`, along with other debug files: `battery`, `co2`, `etvoc`, `humidity`, `light`, `noise`, `pmv`, `temperature`, `tvoc`.
- The app rewrites those files only about every **4 seconds** (we measured 4.1 s on average over two minutes). The writes often come in pairs 0.1 to 0.45 s apart, and the file is briefly empty during a rewrite.
- The sensor can be read directly, faster than the app's file:
  ```
  /sys/devices/platform/ff190000.i2c/i2c-1/1-0045/light_opt3004_read
  ```
  It returns text like `light=134`. In one comparison the direct read led the app's file by about 3 seconds. **Only read this file; never write to anything under `/sys`.**
- Values: `0` in a dark room (the door open or closed made no difference), about `134` to `150` with the room light on, and intermediate numbers (such as 104 or 70) for a moment while the light changes. It is **lux**: we compared it with a phone light-meter app at indoor light levels and the two agreed within about 3 to 4 lx. Phone sensors are imprecise, and we did not test bright daylight, so we do not know whether the value tops out.
- **How we found the node:** the app opens it briefly on each read, so one snapshot of `/proc/<pid>/fd` misses it. Sampling repeatedly catches it:
  ```
  for i in $(seq 1 50); do ls -l /proc/$(pgrep QingSnow2App)/fd 2>/dev/null | grep -E "/sys|/dev"; sleep 0.2; done | awk '{print $9, $10, $11}' | sort | uniq -c
  ```
  It showed up in 3 of 50 samples. Other hardware revisions may use a different address.
- Do not store anything in `/userdata/etc/debug/`: strings in the app binary show it runs `rm -r` on that folder in some routine.

## Install

Requirements: `curl` with MQTT support (`curl --version` lists `mqtt` on firmware 4.5.6_0167), a broker, and a shell.

1. In `scripts/pub.sh`, set `BROKER` (host:port) and `TOPIC` (for example `qingping/AABBCCDDEEFF/light`). Make sure the file has Unix (LF) line endings.
2. Check that curl can publish. In one terminal run `mosquitto_sub -h YOUR_BROKER_IP -t 'qingping/#' -v`, then on the device:
   ```
   curl -s -m 5 -d "test" mqtt://YOUR_BROKER_IP:1883/qingping/test
   ```
3. Push the script and run it in the foreground first:
   ```
   adb -s DEVICE_IP:5555 push scripts/pub.sh /userdata/pub.sh
   adb -s DEVICE_IP:5555 shell sh /userdata/pub.sh
   ```
   You should see one message immediately, then a message within about a second of covering the sensor or switching the room light, and a repeat of the current value roughly every minute. Stop it with Ctrl-C.
4. Install the boot hook. Push it and make it executable:
   ```
   adb -s DEVICE_IP:5555 push scripts/S90pub /etc/init.d/S90pub
   adb -s DEVICE_IP:5555 shell "chmod +x /etc/init.d/S90pub && sh -n /etc/init.d/S90pub && echo syntax ok"
   ```
   Then start it from an interactive shell, not from a one-shot `adb shell "..."` command, and leave the shell open while you check:
   ```
   adb -s DEVICE_IP:5555 shell
   /etc/init.d/S90pub start; echo exit: $?
   ps w | grep '[p]ub.sh'
   ```
   The hook should return immediately with exit `0`, and `ps` should show exactly one `pub.sh`. **Note:** a one-shot adb command ends its session when it finishes, and that seems to stop what it started in the background. We saw this with the Squeezelite player ([03](03-music-assistant.md)); we did not test it with this hook, but the same pattern applies. A reboot starts the hook with no session involved.
5. Do a normal `reboot`, reconnect, and repeat the `ps` check and the subscriber check. The script is started through `sh` because the device's boot script strips execute bits in `/userdata` (see [how-it-works.md](how-it-works.md)).

## Home Assistant

Settings, Devices & services, MQTT, the gear icon on your device, **Add another entity**, type **Sensor**:

- Name: `Light level`
- State topic: your `TOPIC`
- State class: Measurement
- Device class: **Illuminance**
- Unit of measurement: `lx`
- Click **Save changes** at the end.

If you created the entity earlier without a device class and unit, use the gear icon, **Update entity properties**, set both, and **Save changes**. Home Assistant may then flag the unit change against the statistics it already recorded; if it does, Developer Tools, Statistics offers a fix.

For automations use a threshold in lux (for example "above 50 means a light is on"). In our room the sensor reads about 135 to 150 with the light on and 0 in the dark, and it reads 0 with the door open or closed, so it does not resolve very dim light.

## Tuning

These are edited directly in `pub.sh`:

- `MINDIFF=5` (near the top): publish only if the value moved by at least
  this much since the last publish. The value flickers by a few points under
  artificial light, so a small dead band keeps the broker quiet. Set it to 1
  to see every change.
- `sleep 1` (last line of the loop): seconds between sensor reads. A state
  shorter than this can be missed. Lower it (for example to 0.3) for a faster
  response; we did not measure the extra CPU cost. Each pass also takes a few
  milliseconds of its own.
- The `60` in `[ $n -ge 60 ]`: the refresh. After this many passes with
  nothing published, the current value is sent anyway. Passes are counted, not
  timed, so at 1 s per pass this is a little over a minute, and if you
  change the sleep the refresh interval changes with it. Messages are not
  retained, so this is how Home Assistant gets a value back after it restarts.

In a steady room the script sends about one message a minute.