# qingping-cgs2-local

The **Qingping Air Monitor Gen 2** can do more than the stock firmware exposes.

This project enables:

- Local Home Assistant integration
- MQTT on your own broker - no cloud or app.
- The hidden ambient light sensor
- Music Assistant speaker playback

> **Read this first.** Everything here uses root access to a device the vendor does not support. You can lose features, break the device, or open a security hole on your network. Read the [Security Guide](docs/security.md) before you start. This is hobby documentation from one person's unit; it comes with no warranty.

**Short on time?** See [Quick Start](QUICKSTART.md) for just the steps, without the explanations.

This project grew out of an article by John Lose (in German), which showed that the device can be pointed at a local MQTT broker:
<https://www.johnlose.de/2026/02/quingping-air-monitor-gen-2-cgs2-an-homeassistant/>
Thank you to the author for the starting point. (The vendor's name is spelled "Qingping"; the article's URL has a typo, so search for both.)

## The parts

Do [Getting a Shell](docs/00-getting-a-shell.md) first. After that the parts are independent, so pick the ones you want.

| Part | Guide | What you get | Status |
|---|---|---|---|
| 1 | [01 Local MQTT](docs/01-local-mqtt.md) | The device publishes its readings to **your** MQTT broker instead of the vendor cloud; sensors appear in Home Assistant | Verified on one unit |
| 2 | [02 Light Sensor](docs/02-light-sensor.md) | The ambient-light reading in lux (not published by the device) pushed to MQTT on change, plus a boot hook | Verified on one unit |
| 3 | [03 Music Assistant](docs/03-music-assistant.md) | Use the speaker as a Music Assistant player | Verified on one unit, including starting at boot |

Background and reference:
- [docs/how-it-works.md](docs/how-it-works.md): what runs on the device, the boot sequence, the gotchas
- [docs/security.md](docs/security.md): what you are exposing and how to limit it
- [docs/troubleshooting.md](docs/troubleshooting.md): symptoms and causes
- [docs/known-issue-memory-leak.md](docs/known-issue-memory-leak.md): the main app slowly leaks memory and the watchdog restarts it

## Tested on

| | |
|---|---|
| Device | Qingping Air Monitor Gen 2 (CGS2), one unit, not paired with the Qingping app or an account |
| Firmware | 4.5.6_0167 (the latest offered at the time of writing) |
| Platform | Linux 4.19.232 aarch64, Buildroot userland, glibc 2.29 (this is **not** Android) |
| Broker / Home Assistant | Mosquitto and Home Assistant in Docker containers on Unraid |

Other firmware versions or hardware revisions may differ. If you try this, please report what worked, with your firmware version and hardware details.

## Things we learned the hard way

- Editing `setting.ini` while the app is running does nothing: the app rewrites the file from memory, and a watchdog restarts the app within seconds if you kill it. Stop the **watchdog first**, then the app. ([docs/01](docs/01-local-mqtt.md))
- The device runs `chmod 666` over `/userdata` at every boot, which strips execute bits. Run your scripts with `sh script`, or keep binaries in `/userdata/bin`, which gets its execute bit back. ([docs/how-it-works.md](docs/how-it-works.md))
- Shell scripts must have Unix (LF) line endings. This repo includes a `.gitattributes` for that. ([docs/troubleshooting.md](docs/troubleshooting.md))

## Secrets

Never publish your `setting.ini`. It contains the device's MQTT password and a `miio_key`. Replace MAC addresses, product keys and IP addresses with placeholders in anything you post.

## Disclaimer

This project is not affiliated with Qingping, Cleargrass, Xiaomi, Logitech, Lyrion Music Server, Home Assistant, or Squeezelite.

Use at your own risk. Modifying device firmware or configuration may void warranties or render a device inoperable.

## License

The scripts and documentation in this repository are released under the [MIT License](LICENSE). Third-party software that the build script downloads (Squeezelite, alsa-lib, libFLAC, libogg, libvorbis, and the C library) keeps its own licenses; see [docs/03-music-assistant.md](docs/03-music-assistant.md).
