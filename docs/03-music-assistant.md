# 03. Music Assistant: use the speaker as a player

Status: music plays from Music Assistant through the device's speaker on one
unit (firmware 4.5.6_0167), and the boot hook starts the player after a
reboot. See "Tested, and not tested" for what has and has not been tried.

The device becomes a Squeezelite player. Squeezelite is an open-source
player for the Slimproto protocol, which Music Assistant supports. It makes an
outgoing connection to Music Assistant (port 3483) and fetches the audio over
HTTP (Music Assistant's stream port, 8097 by default). It plays through the
device's normal ALSA speaker route. This guide is independent of parts 1 and
2: it needs a shell ([00](00-getting-a-shell.md)) and a Music Assistant
server.


## What you need

- A shell on the device (guide 00).
- A Music Assistant server the device can reach, and its IP address.
- A static aarch64 build of Squeezelite (step 2). A prebuilt binary will not
  load on this firmware; see "Why a custom build".


## Install

1. In Music Assistant, add the Squeezelite player provider (in the settings,
   under Providers) and keep its defaults. It listens on port 3483 (TCP and
   UDP), with a command line on 9090 and JSON-RPC on 9000. Do not run Home
   Assistant's own "slimproto" or Squeezebox integration at the same time; it
   uses the same ports. If Music Assistant runs in a Docker container with
   bridge networking, publish those ports and the stream port; with host
   networking there is nothing to do.

   Check that the device can reach it. A number above 0 means a connection
   was made; 0.000000 means it was not. These commands change nothing:

       adb -s DEVICE_IP:5555 shell "curl -s -m 3 -o /dev/null -w '3483: %{time_connect}\n' telnet://MA_IP:3483"
       adb -s DEVICE_IP:5555 shell "curl -s -m 3 -o /dev/null -w '8097: %{time_connect}\n' telnet://MA_IP:8097"

   (The ports only answer once the provider is enabled.)

2. Build Squeezelite. On any x86 Linux machine with Docker, put
   build/build.sh in a folder and run:

       docker run --rm -v /path/to/folder:/out ubuntu:24.04 bash /out/build.sh

   The result is a file called squeezelite next to the script. Put it in
   build/ in this repository; .gitignore keeps it out of git. Do not commit
   or publish it; see "Licensing".

3. Create the settings file. Copy scripts/squeezelite.conf.example to
   squeezelite.conf (also ignored by git) and set MA_SERVER to your Music
   Assistant server's IP address. The other settings have working defaults;
   see "Settings".

4. Copy the files to the device:

       adb -s DEVICE_IP:5555 shell "mkdir -p /userdata/bin"
       adb -s DEVICE_IP:5555 push build/squeezelite /userdata/bin/squeezelite
       adb -s DEVICE_IP:5555 shell "chmod +x /userdata/bin/squeezelite"
       adb -s DEVICE_IP:5555 push squeezelite.conf /userdata/squeezelite.conf
       adb -s DEVICE_IP:5555 push scripts/S91squeezelite /etc/init.d/S91squeezelite
       adb -s DEVICE_IP:5555 shell "chmod +x /etc/init.d/S91squeezelite"

   Keep the binary in /userdata/bin: the device's start.sh gives that folder
   its execute bits back at every boot ([how-it-works.md](how-it-works.md)).

5. Start it and check. Use an interactive shell for this, not a one-shot
   adb command, and leave the shell open while you test:

       adb -s DEVICE_IP:5555 shell
       /etc/init.d/S91squeezelite start
       /etc/init.d/S91squeezelite status

   A player with your PLAYER_NAME should appear in Music Assistant within a
   few seconds. Turn the volume down first (see "What to expect"), then play
   something short.

   Why not a one-shot command? In our test, starting it with
   adb shell "/etc/init.d/S91squeezelite start" left no player running a
   moment later, while the same command typed in an interactive shell kept
   running. We suspect that the session hanging up when a one-shot command ends
   stops the player, but we did not confirm the cause on the device. We also
   did not check whether closing the interactive shell stops a player started
   this way. At boot there is no session, and the hook works (step 6).

6. Reboot the device normally (`reboot`) and check that the player comes back
   by itself.


## Settings

The hook reads /userdata/squeezelite.conf. The file is plain shell syntax,
NAME="value". After editing it, run /etc/init.d/S91squeezelite restart.

- MA_SERVER (required): the Music Assistant server's IP address. Use an
  address, not a host name; host names may not resolve in this static build.
  If it is empty, the hook prints a message and does not start the player.
- PLAYER_NAME (default Qingping): the name shown in Music Assistant.
- PLAYER_MAC (default empty): the player's ID in Music Assistant. Empty means
  the device's Wi-Fi MAC address is used. If it changes, Music Assistant
  treats the player as a new one.
- OUTPUT_DEVICE (default "default"): the ALSA device. "default" is the
  device's own speaker route, the same one aplay uses. The player's output
  list (squeezelite -l) shows only the sound card and a null device, but the
  default route can still be opened by name.
- ALSA_PARAMS (default 150:4): ALSA buffer in milliseconds, then the number
  of periods. See "What to expect".
- MAX_RATE (default 48000): the highest sample rate offered to Music
  Assistant. The speaker hardware runs at 48 kHz.
- IDLE_CLOSE (default 5): seconds of silence before the speaker is released.
- LOG_FILE (default empty): write a log to this file, for example
  /userdata/squeezelite.log. It grows without limit while the player runs.

The settings file may have Windows (CRLF) line endings; the hook strips the
carriage returns. Scripts you push should still use Unix (LF) endings.


## Turning it on and off

    /etc/init.d/S91squeezelite start      start now
    /etc/init.d/S91squeezelite stop       stop now
    /etc/init.d/S91squeezelite restart    after changing the settings
    /etc/init.d/S91squeezelite status     running or not running

To keep it from starting at boot without deleting it, rename the hook so
that it no longer matches the S??* pattern the device's boot script runs:

    mv /etc/init.d/S91squeezelite /etc/init.d/off-S91squeezelite

Rename it back to turn it on again. To remove it completely:

    /etc/init.d/S91squeezelite stop
    rm /etc/init.d/S91squeezelite /userdata/bin/squeezelite /userdata/squeezelite.conf


## What to expect

Sound. The speaker is small and mono. In Music Assistant, 20 percent was
barely audible, 60 percent was quiet, and 80 percent was usable but on the
quiet side. The device has no hardware volume control (see "About the audio
hardware"), so the slider only turns the digital signal down, and 100 percent
is the loudest the player can be.

Skips. With the built-in default buffer of 40 ms we heard occasional skips.
With ALSA_PARAMS="150:4" and MAX_RATE="48000" we heard none in about eight
minutes of playback. We changed the two settings together, so we do not know
which one made the difference. A 40 ms buffer leaves little margin on a device
that also runs the vendor app and a noise-measurement loop that records from
the microphone every second. If you still hear skips, raise the first number
of ALSA_PARAMS.

The stream. Music Assistant sent 24-bit, 44.1 kHz FLAC (about 1.6 Mbps) to the
device, which plays it at 44.1 kHz. The device resamples to the hardware's
48 kHz in software.

Resources. In one sample while playing, the player used about 8.4 MB of memory
and 4.5 percent of one core; idle it used no measurable CPU. That is small
next to the device's roughly 100 MB of headroom, but the main app leaks memory
slowly and the watchdog restarts it when free memory runs low, so anything
you add brings that point a little sooner
([known-issue-memory-leak.md](known-issue-memory-leak.md)). The player is a
separate process and keeps running when the watchdog restarts the app.

The player connects out to Music Assistant. As far as we know it opens no
listening port.


## Tested, and not tested

Tested:

- Connecting to Music Assistant and registering as a player.
- Playing music through the speaker, with the output closing after the idle
  timeout and reopening for the next track.
- The settings in the example file, with no audible skips in a short session.
- The boot hook and the settings file: after a normal reboot the player
  started by itself, and music played again with no manual step.
- Starting the hook with a one-shot adb shell command: the player was not
  running a moment later (see step 5). Started from an interactive shell, it
  ran.

Not tested:

- Whether the player reconnects after Music Assistant restarts.
- How the device's own alarm and alert sounds behave while the player is idle
  or playing. The player releases the speaker after IDLE_CLOSE seconds, but
  the device's audio route does not mix, so only one program can use the
  speaker at a time.
- Long runs, and the effect on the main app's memory use over days.
- Volume at 100 percent, and what the microphone and the noise sensor do
  while music plays.


## If something is wrong

- No player appears in Music Assistant: check that the Squeezelite provider is
  enabled, that the two connection checks in step 1 show a number above 0, and
  that status says running. For details, set LOG_FILE, restart, and read the
  log.
- The connection checks show 0.000000: the provider is not enabled yet, a
  firewall is in the way, or the container does not publish port 3483 or the
  stream port.
- The player appears but there is no sound: set LOG_FILE and look for an error
  when it opens the output device. Make sure nothing else is using the
  speaker.
- Skips: raise the first number of ALSA_PARAMS (for example 200:4), restart,
  and listen again.
- It is too quiet: see "What to expect". Also look at the volume normalization
  setting for the player in Music Assistant; we did not change it.
- Status says "not running" right after you started it with a one-shot adb
  command: start it from an interactive shell instead (step 5), or reboot.
- Nothing starts after a reboot: run /etc/init.d/S91squeezelite status and
  start. Check that the hook is executable and that MA_SERVER is set.


## Why a custom build

The device's C library is glibc 2.29 and its libstdc++ is 6.0.28. Binaries
built on current distributions ask for newer versions, and the loader refuses
them before any code runs (nothing on the device is affected):

- Squeezelite 2.0.0.1612, the plain aarch64 build from the maintainer's
  download page, needs glibc up to 2.35.
- sendspin-cli 0.4.0 (the arm64 release) needs glibc up to 2.38, libstdc++ up
  to GLIBCXX 3.4.32, and libraries (libdns_sd, PortAudio, PulseAudio,
  PipeWire) that are not on the device.

To check a binary before pushing it, read the symbol versions it asks for.
This only reads strings and runs nothing:

    grep -a -o 'GLIBC_[0-9][0-9.]*' /path/to/binary | sort -u

Anything above GLIBC_2.29 will not load on this firmware.

build/build.sh builds Squeezelite as a fully static aarch64 binary, so the
device's glibc does not matter. It uses a cross-compiler, builds static copies
of libogg, libvorbis, libFLAC and alsa-lib (with alsa-lib's config path set to
the device's /usr/share/alsa), and pins the upstream Squeezelite commit. It
includes FLAC, Vorbis and PCM support and ALSA output. A different compiler
version can give a different hash.

Sendspin, the newer Open Home Foundation protocol, remains untried. Its CLI
player advertises itself over mDNS and we saw no mDNS responder on the device;
two pages of the project's wiki disagreed about whether it can be pointed at a
server address; and building it would mean C++20 against an old glibc.


## Licensing

This repository's own files are MIT licensed (see LICENSE). The software that
build.sh downloads and builds keeps its own licenses: Squeezelite is GPL
software, alsa-lib is LGPL, and the static binary also contains glibc. The MIT
license does not cover the built binary. If you distribute a built binary you
take on source-offer obligations, so this repository ships the build script and
not a binary. Build it yourself.


## About the audio hardware

- Both aplay and arecord work on the device.
- /etc/asound.conf sends playback through a plug device straight onto hw:0,0.
  Despite its name (dmixer) it does not mix, so only one program can play at a
  time.
- Capture goes through dsnoop, which shares the microphone between programs: a
  4-channel, 48 kHz array, with channels selected and a gain of 16 applied.
- There is no hardware volume control. amixer controls lists only two path
  selectors, Playback Path and Capture MIC Path, which start.sh sets to the
  speaker and the main microphone at every boot.
- The noise sensor is the microphone. analyze_noise.sh records one second
  through arecord in a loop, takes the level with sox, and applies a vendor
  calibration curve. watchdog.sh starts it and restarts it if it dies, which
  is why top shows it under the watchdog; top cuts its name to
  analyze_noise.s. Each second it briefly runs arecord, sox and awk.


## Microphone and voice assistants: ideas only

The microphone is shared through dsnoop, so a voice satellite could record
alongside the noise sensor. Open questions: far-field quality (the array is
tuned for a noise level, and the firmware applies a gain of 16), echo while the
speaker plays, and the fact that the satellite projects we looked at are Python
programs and the device has no interpreter, so the satellite would run on
another machine and stream audio from the device. Because the device's
debugging port is unauthenticated root access, a live microphone makes the
network-isolation advice in [security.md](security.md) more important.
