# Known issue: the main app slowly leaks memory

The device's main app (QingSnow2App) grows in memory over time. When free
memory drops below 45 MB, the vendor's watchdog kills the app and restarts it
five seconds later. Nothing breaks, but you will see occasional restarts in
the logs, and probably short gaps in your readings.

This is what we measured on one unit (firmware 4.5.6_0167, local MQTT,
the light script, and a memory logger running). It is not a diagnosis.


## What the watchdog does

watchdog.sh checks the "free" column of `free -m` on every pass (about every
5 seconds). If it is below 45 MB, it kills QingSnow2App and logs:

    [2026-11-16 12:03:06][watchdog.sh] free memory is less than 45M, kill QingSnow2App

On its next pass the watchdog notices the app is gone and starts it again.
(If the app is restarted more than four times with less than 60 seconds
between restarts, the watchdog reboots the device instead. Our restarts were
hours apart, so that never triggered.)

The watchdog logs to the file named for the day it started, not the current
day. After a boot on Nov 15, all its later lines went into 2026-11-15.log.
To list every low-memory kill:

    grep -h "free memory" /userdata/etc/log/*.log


## What we saw

Three kills between Nov 16 and Nov 17:

    2026-11-16 12:03:06
    2026-11-16 23:00:56   (11.0 hours later)
    2026-11-17 16:17:55   (17.3 hours later)

We then logged free memory and the app's resident size every 10 minutes for
14.5 hours (88 samples, Nov 18, 00:18 to 14:48), starting about 8 hours after
the last restart:

- The app grew from 197.0 to 254.9 MB (+57.9 MB). Free memory fell by the
  same amount, from 183 to 125 MB, so the app accounts for all of the decline.
- The growth is steady but not constant. It averaged 3.29 MB per hour over the
  first 8 hours (overnight) and 4.79 MB per hour over the next 6.5 hours
  (daytime). Three-hour windows ranged from 3.1 to 3.7 MB per hour overnight
  and about 4.5 MB per hour from mid-morning on.
- Projected forward at the daytime rate, free memory reaches the 45 MB floor
  about 16 hours after the last sample (around 06:40 the next morning). An
  earlier projection from the overnight rate alone said 33 hours and was too
  optimistic: free memory was already 8 MB below that line by 14:48.

Right after a boot we measured about 224 MB free, and 125 MB at the end of the
log, so the headroom above the 45 MB floor shrinks from about 180 MB to under
80 MB between restarts.


## What we do not know

- The cause. The growth is inside the app's own process, so the short-lived
  processes of the light script cannot explain it.
- Whether stock firmware talking to the vendor cloud behaves the same way. The
  kill rule is vendor code, which suggests the vendor knows about it, but we
  never measured a stock unit.
- Why the rate changes. In our log the daytime rate was about 45 percent
  higher than the overnight rate. The two earlier intervals (11.0 and 17.3
  hours) would need a leak of roughly 10 to 15 MB per hour if each cycle began
  with about 210 MB free, which is two to three times even the daytime rate.
  Activity such as screen use or message volume may matter; we did not test it.
- How long the gap in your readings lasts. We have not measured it. The
  screen goes blank for a few seconds and the MQTT connection is re-made.


## What it means

You can ignore it. The watchdog handles it, and we saw no lasting effect. If
you want restarts at a time of your choosing, a scheduled kill of
QingSnow2App at a quiet hour would do the same thing the watchdog does, but
we have not tried it and it only hides the growth.

Anything you add to the device uses part of the same headroom, so a small
player or script brings the next restart a little sooner.


## Measure it on your unit

This temporary logger writes one line every 10 minutes. It does not survive a
reboot. Stop it with `pkill -f memlog.sh`.

    cat > /userdata/memlog.sh << 'EOF'
    #!/bin/sh
    while true; do
      pid=$(pgrep QingSnow2App | head -n 1)
      rss=$(grep VmRSS /proc/$pid/status 2>/dev/null | tr -s ' ' | cut -d' ' -f2)
      fr=$(free -m | awk '/Mem/{print $4}')
      echo "$(date '+%Y-%m-%d %H:%M:%S') free_mb=$fr app_rss_kb=$rss" >> /userdata/memlog.txt
      sleep 600
    done
    EOF
    ( trap '' HUP; sh /userdata/memlog.sh >/dev/null 2>&1 & )

The `trap '' HUP` matters: a background job started by a one-shot
`adb shell "..."` command normally stops the moment that command's session
ends (see [troubleshooting.md](troubleshooting.md)), which would silently
end the logger within seconds of you typing the line above. The trap, the
same one [scripts/S90pub](../scripts/S90pub) uses, keeps it running either
way; an interactive `adb shell` session works too, trap or not.

Let it run for at least a full day, since in our log the rate was higher
during the day. If app_rss_kb climbs steadily and free_mb falls by the same
amount, you are seeing the same thing. A sudden jump just before a kill would
be something different, so please report it.

Limits of this write-up: one unit, one 14.5-hour window, and straight-line fits
to 88 points.
