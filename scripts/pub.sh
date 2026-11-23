#!/bin/sh
BROKER="YOUR_BROKER_IP:1883"
TOPIC="qingping/YOUR_DEVICE_MAC/light"
NODE="/sys/devices/platform/ff190000.i2c/i2c-1/1-0045/light_opt3004_read"
MINDIFF=5
last=""
n=0
while true; do
  raw=$(cat "$NODE" 2>/dev/null)
  v=${raw#light=}
  case "$v" in
    ''|*[!0-9]*) ;;
    *)
      send=0
      if [ -z "$last" ] || [ $n -ge 60 ]; then
        send=1
      else
        d=$((v-last))
        [ $d -lt 0 ] && d=$((0-d))
        [ $d -ge $MINDIFF ] && send=1
      fi
      if [ $send -eq 1 ]; then
        curl -s -m 5 -d "$v" "mqtt://$BROKER/$TOPIC" >/dev/null
        last=$v
        n=0
      fi
      ;;
  esac
  n=$((n+1))
  sleep 1
done
