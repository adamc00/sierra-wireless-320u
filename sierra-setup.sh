#!/bin/bash

apt-get -y install gpsd gpsd-clients chrony ppp

if [[ ! -e /etc/sierra ]]; then 
  mkdir /etc/sierra
fi

sed -ri 's/^DEVICES=".*"/DEVICES="\/dev\/ttyUSB2"/' /etc/default/gpsd 
sed -ri 's/^GPSD_OPTIONS=".*"/GPSD_OPTIONS="-n"/' /etc/default/gpsd 

echo "options sierra nmea=1" > /etc/modprobe.d/sierra.conf
echo "KERNEL==\"ttyUSB?\", DRIVERS==\"usb\", SUBSYSTEMS==\"usb\", ATTRS{idVendor}==\"1199\", ATTRS{idProduct}==\"68aa\", SYMLINK+=\"sierra.wwan.%n\"" > /etc/udev/rules.d/93-sierra.rules

cat > /usr/local/bin/sierra-state << sierra-state
#!/bin/bash

SIERRA_DEV_PREFIX=/dev/sierra.wwan

declare -a SIERRA_PORTS=(\$( ls \$SIERRA_DEV_PREFIX.* ))

SIERRA_PORT_COUNT=\${#SIERRA_PORTS[@]}
echo "export SIERRA_CMD_PORT=\${SIERRA_PORTS[-2]}"

if [[ "\$SIERRA_PORT_COUNT" == "4" ]]; then
  echo "export SIERRA_GPS=0"
else
  echo "export SIERRA_GPS=1"
fi
sierra-state

chmod o+x /usr/local/bin/sierra-state

cat > /usr/local/bin/sierra-gps << sierra-gps
#!/bin/bash

if [[ "\$1" != "enable" && "\$1" != "disable" ]]; then
  echo "usage: \$0 [enable|disable]"
  exit 1
fi

\$(sierra-state)

if [[ "\$SIERRA_GPS" == "0" && "\$1" == "enable" ]]; then
  chat -f /etc/sierra/gps-enable.chat < \$SIERRA_CMD_PORT > \$SIERRA_CMD_PORT
fi

if [[ "\$SIERRA_GPS" == "1" && "\$1" == "disable" ]]; then
  chat -f /etc/sierra/gps-disable.chat < \$SIERRA_CMD_PORT > \$SIERRA_CMD_PORT
fi
sierra-gps

chmod o+x /usr/local/bin/sierra-gps

cat > /etc/sierra/start.chat << start.chat
""
ATI5 AirCard
AT+CGDCONT=1,"IP","Telstra.datapack" OK
AT+CFUN=1 OK
AT!SCDFTPROF=1 OK
AT!SCACT=1,1 OK
AT!SCPROF=1,"",1,0,0,0 OK
start.chat

cat > /etc/sierra/stop.chat << stop.chat
""
ATI5 AirCard
AT!SCACT=0,1 OK
stop.chat

cat > /usr/local/bin/sierra << sierra
#!/bin/bash

\$(sierra-state)

stty -F \$SIERRA_CMD_PORT 9600 raw
chat -f /etc/sierra/\$MODE.chat < \$SIERRA_CMD_PORT > \$SIERRA_CMD_PORT
ERR_CODE=\$?
if [[ "\$ERR_CODE" != "0" ]]; then
  echo "Failed to init sierra wireless device. Got code \$ERR_CODE."
  exit \$ERR_CODE
fi
sierra

chmod a+x /usr/local/bin/sierra


cat > /etc/network/interfaces.d/wwan0 << wwan0
allow-hotplug wwan0
iface wwan0 inet dhcp
    pre-up /usr/local/bin/sierra
    post-down /usr/local/bin/sierra
wwan0

cat > /etc/sierra/gps-enable.chat << gps-enable.chat
""
ATI5 AirCard
AT!ENTERCND="A710" OK
AT!CUSTOM="GPSENABLE",1 OK
AT!CUSTOM="GPSREFLOC",1 OK
AT!GPSAUTOSTART=1 OK
gps-enable.chat

cat > /etc/sierra/gps-disable.chat << gps-disable.chat
""
ATI5 Model: AirCard 320U
AT!ENTERCND="A710" OK
AT!CUSTOM="GPSENABLE",0 OK
AT!CUSTOM="GPSREFLOC",0 OK
AT!GPSAUTOSTART=0 OK
gps-disable.chat

# shutdown -r now



