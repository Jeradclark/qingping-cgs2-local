# Troubleshooting

| Symptom | Likely cause | What to do |
|---|---|---|
| Your `setting.ini` edit is gone after a reboot | The app was running and wrote its in-memory settings over your edit | Stop `watchdog.sh` first, then `QingSnow2App`, then edit, `sync`, `reboot -f` ([01](01-local-mqtt.md)) |
| Killing the app brings it back a few seconds later | `watchdog.sh` restarts it | Kill the watchdog first (`pkill -9 -f watchdog.sh`) |
| A script or binary in `/userdata` "does not run" after a reboot | `start.sh` strips execute bits in `/userdata` at boot | Start scripts with `sh script`, or keep binaries in `/userdata/bin` |
| `error while loading shared libraries` or `version 'GLIBC_2.xx' not found` | The binary needs a newer glibc or libraries than the device has | See [03](03-music-assistant.md): check symbol versions first, or build static |
| A script behaves strangely or says `not found` on a line that looks right | Windows (CRLF) line endings | Convert to LF; this repo's `.gitattributes` forces LF for scripts |
| A long pasted command does odd things in the adb shell | The terminal wrapped and mangled it | Push a script file instead, or paste shorter commands; check created files with `sh -n` and `cat` |
| Home Assistant entities are "Unknown" | Nothing is retained on the broker, so they stay Unknown until the next message | Wait for the next publish (about a minute for the readings, up to about a minute for the light sensor) |
| An MQTT entity you created in the UI is missing | You closed the wizard instead of clicking **Save changes** | Re-create it and click **Save changes** on the last page |
| The device connects to the broker but nothing shows in Home Assistant | The state topic or template does not match | Subscribe to the device's topic and compare; the topic is `pub_topic` in `[host]` |
| PM2.5 and PM10 read `99999` | The unit has no PM sensor (the About screen says so on ours) | Skip those entities |
| The screen goes blank | You killed the app | Expected; the reboot brings it back, or the watchdog restarts it if it is still running |
| The device reboots itself repeatedly | `watchdog.sh` reboots after more than four app restarts under 60 seconds apart | Find why the app is crashing; undo your last change |
| The light script is running twice | The hook and a manual run overlap | `pkill -f '/userdata/pub\.sh'`, then run `/etc/init.d/S90pub start` once |
| The screen goes blank for a few seconds every day or so, or the readings show a short gap | The main app leaks memory slowly, and the watchdog restarts it when free memory drops below 45 MB | Nothing is wrong; see [known-issue-memory-leak.md](known-issue-memory-leak.md) |
| A script or the player you started with a one-shot "adb shell" command is gone a moment later | The session hangs up when the command ends, and that seems to stop what it started | Start it from an interactive adb shell (type adb shell, then the command), or reboot: the hooks start it at boot |
