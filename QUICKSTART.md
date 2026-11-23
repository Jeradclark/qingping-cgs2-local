# Quick start

The short version of parts 1 and 2: just the steps. The guides in docs/ have
the same steps with the reasons, the checks, and how to undo each one.

Before you start: this gives you root access to the device. Read
docs/security.md first. Step 3 makes a backup.


## Part 1: send the readings to your own MQTT broker

You need a PC with adb, an MQTT broker the device can reach, and Home
Assistant connected to that broker.

1. Enable debugging. On the device, open the About screen and tap the Device
   Name row seven times. In Developer Options, turn on "Adbd Debugging" and
   "Enable Wifi Debug Mode".

2. Connect from your PC:

       adb connect DEVICE_IP:5555
       adb -s DEVICE_IP:5555 shell

3. Back up the settings file:

       cp /userdata/etc/setting.ini /userdata/etc/setting.ini.original

4. Stop the watchdog first, then the app. If you stop only the app, the
   watchdog restarts it, and the running app overwrites any edit you make.
   The screen goes blank; that is expected.

       pkill -9 -f watchdog.sh
       pkill -9 QingSnow2App
       sleep 2
       ps w | grep -E "watchdog|QingSnow2App" | grep -v grep

   The last command must print nothing.

5. Change the MQTT host and port, save, and reboot:

       sed -i 's/^host=.*/host=YOUR_BROKER_IP/; s/^port=.*/port=1883/' /userdata/etc/setting.ini
       sync
       reboot -f

6. Check it worked. After a minute or two, reconnect and run:

       grep -E '^(host|port)=' /userdata/etc/setting.ini
       grep pub_topic /userdata/etc/setting.ini

   Then watch your broker. A message should arrive about once a minute:

       mosquitto_sub -h YOUR_BROKER_IP -t '#' -v

7. Add the sensors in Home Assistant. Go to Settings, Devices & services,
   MQTT, "Add MQTT device". Then, for each sensor below, use "Add another
   entity" and choose Sensor. For all of them the state topic is the
   pub_topic value from step 6 and the state class is Measurement. The
   device class and unit are from this list:

       Temperature  class: Temperature       unit: °C
         {{ value_json.sensorData[0].temperature.value | round(1) }}

       Humidity     class: Humidity          unit: %
         {{ value_json.sensorData[0].humidity.value | round(1) }}

       CO2          class: Carbon dioxide    unit: ppm
         {{ value_json.sensorData[0].co2.value }}

       Noise        class: Sound pressure    unit: dB
         {{ value_json.sensorData[0].noise.value }}

       Battery      class: Battery           unit: %
         {{ value_json.sensorData[0].battery.value }}

       VOC Index    class: (none)            unit: (none)
         {% set t = value_json.sensorData[0].tvoc_index %}{{ none if t.status == 2 else t.value }}

   Click "Save changes" on the last page of the wizard. If you close the
   dialog instead, the entity is thrown away. Entities show "Unknown" until
   the next message arrives.

That is all of part 1. Details: docs/00-getting-a-shell.md and
docs/01-local-mqtt.md.

To undo it, repeat steps 4 and 5 with the values from the backup (on our
unit, host=mqtt.bj.cleargrass.com and port=11883).


## Part 2: add the light sensor

You need part 1's step 1 and 2 (a shell) and a broker. The light sensor is
not published by the device, so a small script reads it and sends it.

1. In scripts/pub.sh, set BROKER (host:port) and TOPIC. Keep the file's Unix
   (LF) line endings.

2. Copy the script and the boot hook to the device:

       adb -s DEVICE_IP:5555 push scripts/pub.sh /userdata/pub.sh
       adb -s DEVICE_IP:5555 push scripts/S90pub /etc/init.d/S90pub
       adb -s DEVICE_IP:5555 shell "chmod +x /etc/init.d/S90pub"

   Then start it from an interactive shell (a one-shot adb command may stop
   it when the command ends), and leave the shell open while you test:

       adb -s DEVICE_IP:5555 shell
       /etc/init.d/S90pub start

   It also starts by itself after every reboot.

3. Watch for messages on your TOPIC, and switch the room light on and off:

       mosquitto_sub -h YOUR_BROKER_IP -t 'YOUR_TOPIC' -v

4. In Home Assistant, add one more sensor to the same device: state topic is
   your TOPIC, state class Measurement, device class Illuminance, unit lx, no
   template. Click "Save changes".

Details: docs/02-light-sensor.md.
