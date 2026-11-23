# 01. Local MQTT: point the device at your own broker

The device publishes its readings to your MQTT broker instead of the vendor cloud, and the sensors show up in Home Assistant.

## How it works

`/userdata/etc/setting.ini` has a `[host]` section. On our unit the factory values pointed at the vendor's cloud broker (`mqtt.bj.cleargrass.com`, port `11883`, no `tls` key), with per-device credentials already filled in. The app reads this file at startup. Change `host` and `port` to your broker and the device connects there instead. The device keeps its stock username, password, client ID and topics.

This only redirects the air-quality MQTT stream described in this guide. The device separately runs a Xiaomi miio cloud client that keeps talking to Xiaomi's own servers regardless of this change; see [security.md](security.md).

## Prerequisites

- A shell on the device ([00-getting-a-shell.md](00-getting-a-shell.md)) and a backup of `setting.ini`.
- An MQTT broker the device can reach. Ours was Mosquitto with `listener 1883` and `allow_anonymous true`. If your broker requires logins, see "Broker logins" below.
- Home Assistant with the MQTT integration connected to the same broker.

## Why editing the file alone does not work

The running app keeps its settings in memory and rewrites `setting.ini` itself (brightness and a heartbeat timestamp change constantly). If you edit the file while it runs, your edit is overwritten, which looks like the settings "revert on reboot". And if you only kill the app, `watchdog.sh` restarts it within about five seconds. So: **stop the watchdog first, then the app, then edit.**

## Steps

1. Look at the current values (this masks the secrets):
   ```
   sed -E 's/^(password|miio_key)=.*/\1=REDACTED/' /userdata/etc/setting.ini | grep -A9 '^\[host\]'
   ```
   Note the original `host` and `port` in case you want to undo this.

2. Stop the watchdog and the app, edit, and reboot. The screen goes blank when the app dies; that is expected.
   ```
   pkill -9 -f watchdog.sh
   pkill -9 QingSnow2App
   sleep 2
   ps w | grep -E "watchdog|QingSnow2App" | grep -v grep
   ```
   The last command must print nothing. If it prints a process, stop and investigate. Then:
   ```
   cd /userdata/etc
   sed -i 's/^host=.*/host=YOUR_BROKER_IP/; s/^port=.*/port=1883/' setting.ini
   sync
   grep -E '^(host|port)=' setting.ini
   reboot -f
   ```

3. After it boots, check the values stuck:
   ```
   grep -E '^(host|port)=' /userdata/etc/setting.ini
   ```

4. The device's own Developer Options screen ([00](00-getting-a-shell.md)) also shows the MQTT status, host and topics it is using. That is a quick way to confirm the host change took effect.

5. Check the broker sees the device. With Mosquitto's default `notice` logging, a new client from the device's IP appears in the log. To see the messages, subscribe to the device's topics, which are in your own `[host]` section as `pub_topic` and `sub_topic` (they look like `/<productkey>/<MAC>/user/update` and `.../user/get`):
   ```
   mosquitto_sub -h YOUR_BROKER_IP -t '/<productkey>/#' -v
   ```

## What the device publishes

Messages arrive on the `pub_topic`. Types we saw:

| `type` | Meaning |
|---|---|
| `12` | Live reading, roughly once a minute |
| `17` | History dump (about 50 older readings, newest first), sent after the device was offline |
| `40`, `32` | Alarm and scene sync, no sensor data |

A trimmed live message (MAC replaced):

```json
{"mac":"AABBCCDDEEFF","sensorData":[{"battery":{"status":0,"value":48},"co2":{"status":0,"value":908},"humidity":{"status":0,"value":56.8},"noise":{"status":0,"value":36},"pm10":{"sn":"","status":4,"value":99999},"pm25":{"sn":"","status":4,"value":99999},"temperature":{"status":0,"value":21.9},"timestamp":{"value":1794776221},"tvoc_index":{"status":2,"status_duration":50,"status_start_time":1794776189,"value":0}}],"third_state":0,"timestamp":1794776221,"type":"12","version":"4.5.6_0167"}
```

## Home Assistant sensors (no YAML needed)

Settings, Devices & services, MQTT, **Add MQTT device**. Give it a name (and optionally manufacturer `Qingping`, model `CGS2`). Then use the device's gear icon and **Add another entity** for each sensor below. All use the device's `pub_topic` as the state topic and state class **Measurement**. **Click "Save changes" at the very end of the wizard for each entity; closing the dialog discards it.**

| Entity | Device class | Unit | Value template |
|---|---|---|---|
| Temperature | Temperature | °C | `{{ value_json.sensorData[0].temperature.value \| round(1) }}` |
| Humidity | Humidity | % | `{{ value_json.sensorData[0].humidity.value \| round(1) }}` |
| CO2 | Carbon dioxide | ppm | `{{ value_json.sensorData[0].co2.value }}` |
| Noise | Sound pressure | dB | `{{ value_json.sensorData[0].noise.value }}` |
| Battery | Battery | % | `{{ value_json.sensorData[0].battery.value }}` |
| VOC Index | (none) | (none) | `{% set t = value_json.sensorData[0].tvoc_index %}{{ none if t.status == 2 else t.value }}` |

Type the `|` in `round` as a plain pipe (the backslash is only there for the table). Entities show "Unknown" until the next message arrives, because nothing is retained on the broker.

Notes:
- **PM2.5 / PM10:** the value `99999` means "no data". Our unit's About screen says the PM sensor is not installed, so we did not create these entities. If yours has the sensor, add them with device classes PM2.5 / PM10 and unit `µg/m³`, and a template like `{% set v = value_json.sensorData[0].pm25.value %}{{ none if v == 99999 else v }}`.
- **VOC Index** is Sensirion's unitless 0 to 500 index, relative to a baseline the sensor learns over time, so no Home Assistant device class fits. The device's own screen rates it Excellent (0 to 3), Good (3 to 37), Slightly high (37 to 120), High (120 to 293) and Very high (above 293). We believe `status: 2` is a warm-up flag after boot, which is why the template ignores it (inferred from timing, not documented).
- The templates read `sensorData[0]`, the newest reading, which also works for `type 17` messages. Messages without `sensorData` (types 40 and 32) did not cause any template warnings or errors in the Home Assistant log when we checked. In our capture they arrived once, right after the device connected, so we do not know how often they come.

## Broker logins

The device sends the `username` and `password` from its `[host]` section as its MQTT credentials. If your broker requires authentication, create a user matching those. Changing the credentials in `setting.ini` is untested here; the app rewrote `client_id` on its own once, so do not assume your edits persist.

## What we changed, and what we did not prove

The successful run changed only `host` and `port`. Our file also still contained `tls=0` and an extra section named after the broker IP with `save_history_interval` and `sync_history_interval`, left over from the article's earlier attempt. We never tested without them, so we cannot say whether they matter. We did **not** need to change the username, password, client ID or topics.

## Open risk: the "Refresh MQTT Info" button

The Developer Options screen has a **Refresh MQTT Info** button. We never pressed it, and we do not know what it does. If it fetches fresh connection details from the vendor cloud, it could overwrite your `host`. The same goes for any automatic refresh we have not seen. If your host ever reverts to `mqtt.bj.cleargrass.com`, repeat the steps above, and please report when it happened.

## Undo

Stop the watchdog and the app as above, then set the values you noted in step 1 (ours were `host=mqtt.bj.cleargrass.com` and `port=11883`), `sync`, and reboot.