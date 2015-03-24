#!/bin/bash

grep -q max_usb_current /boot/config.txt || echo "max_usb_current=1" >> /boot/config.txt
sed -ri 's/max_usb_current=.*/max_usb_current=1\n/' /boot/config.txt

SIERRA_DEV_PREFIX=sierra.wwan

apt-get -y install gpsd gpsd-clients chrony ppp

[[ ! -e /etc/sierra ]] && mkdir /etc/sierra

#sed_cmd="s#^DEVICES=\".*\"#DEVICES=\"/dev/$SIERRA_DEV_PREFIX.nmea\"#"
#sed -ri "$sed_cmd" /etc/default/gpsd 
sed -ri 's/^GPSD_OPTIONS=".*"/GPSD_OPTIONS="-n"/' /etc/default/gpsd

echo "options sierra nmea=1" > /etc/modprobe.d/sierra.conf
rm -f /etc/udev/rules.d/*-sierra.rules
echo "KERNEL==\"ttyUSB?\", DRIVERS==\"usb\", SUBSYSTEMS==\"usb\", ATTRS{idVendor}==\"1199\", ATTRS{idProduct}==\"68aa\", SYMLINK+=\"$SIERRA_DEV_PREFIX.%n\"" > /etc/udev/rules.d/93-sierra.rules
echo "KERNEL==\"ttyUSB?\", DRIVERS==\"usb\", SUBSYSTEMS==\"usb\", ATTRS{idVendor}==\"1199\", ATTRS{idProduct}==\"68aa\", RUN+=\"/usr/local/bin/sierra-state\"" > /etc/udev/rules.d/94-sierra.rules

cat > /usr/local/bin/sierra-state << sierra-state
#!/bin/bash

declare -a SIERRA_PORTS=(\$( ls /dev/$SIERRA_DEV_PREFIX.[0-9]* ))
SIERRA_PORT_COUNT=\${#SIERRA_PORTS[@]}

[[ "\$SIERRA_PORT_COUNT" -lt 4 ]] && exit
sleep 2

rm -f /dev/$SIERRA_DEV_PREFIX.nmea
rm -f /dev/$SIERRA_DEV_PREFIX.cmd

SIERRA_CMD_PORT=\${SIERRA_PORTS[-2]}

if [[ "\$SIERRA_PORT_COUNT" == "4" ]]; then
  gpsdctl remove /dev/$SIERRA_DEV_PREFIX.nmea
else
  SIERRA_NMEA_PORT=\${SIERRA_PORTS[-3]}
  ln -s \$SIERRA_NMEA_PORT /dev/$SIERRA_DEV_PREFIX.nmea
  ln -s \$SIERRA_CMD_PORT /dev/$SIERRA_DEV_PREFIX.cmd
  /etc/init.d/gpsd start
  gpsdctl add /dev/$SIERRA_DEV_PREFIX.nmea
fi
sierra-state

chmod o+x /usr/local/bin/sierra-state

cat > /usr/local/bin/sierra-gps << sierra-gps
#!/bin/bash

if [[ "\$1" != "enable" && "\$1" != "disable" ]]; then
  echo "usage: \$0 [enable|disable]"
  exit 1
fi

stty -F /dev/$SIERRA_DEV_PREFIX.cmd 9600 raw
if [[ "\$SIERRA_GPS" == "0" && "\$1" == "enable" ]]; then
  chat -f /etc/sierra/gps-enable.chat < /dev/$SIERRA_DEV_PREFIX.cmd > /dev/$SIERRA_DEV_PREFIX.cmd
fi

if [[ "\$SIERRA_GPS" == "1" && "\$1" == "disable" ]]; then
  chat -f /etc/sierra/gps-disable.chat < /dev/$SIERRA_DEV_PREFIX.cmd > /dev/$SIERRA_DEV_PREFIX.cmd
fi
sierra-gps

chmod o+x /usr/local/bin/sierra-gps

# ATI5 "Model: AirCard 320U"-ATI5 "Model: AirCard 320U"
cat > /etc/sierra/start.chat << start.chat
""
ATE0V1&F&D2&C1S0=0 OK-ATE0V1&F&D2&C1S0=0 OK
""
ATZ OK-ATZ OK
""
AT+CGDCONT=1,"IP","Telstra.datapack" OK-AT+CGDCONT=1,"IP","Telstra.datapack" OK
""
AT+CFUN=1 OK-AT+CFUN=1 OK
""
AT!SCDFTPROF=1 OK-AT!SCDFTPROF=1 OK
""
AT!SCACT=1,1 OK-AT!SCACT=1,1 OK
""
AT!SCPROF=1,"",1,0,0,0 OK-AT!SCPROF=1,"",1,0,0,0 OK
start.chat

cat > /etc/sierra/stop.chat << stop.chat
""
ATZ OK-ATZ OK
""
AT!SCACT=0,1 OK
stop.chat

cat > /usr/local/bin/sierra << sierra
#!/bin/bash

while [[ ! -e /dev/$SIERRA_DEV_PREFIX.cmd ]]; do
  sleep 1
done
sleep 1

stty -F /dev/$SIERRA_DEV_PREFIX.cmd 9600 raw
chat -f /etc/sierra/\$MODE.chat < /dev/$SIERRA_DEV_PREFIX.cmd > /dev/$SIERRA_DEV_PREFIX.cmd
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
AT!ENTERCND="A710" OK
""
AT!CUSTOM="GPSENABLE",1 OK
""
AT!CUSTOM="GPSREFLOC",1 OK
""
AT!GPSAUTOSTART=1 OK
gps-enable.chat

cat > /etc/sierra/gps-disable.chat << gps-disable.chat
""
AT!ENTERCND="A710" OK
""
AT!CUSTOM="GPSENABLE",0 OK
""
AT!CUSTOM="GPSREFLOC",0 OK
""
AT!GPSAUTOSTART=0 OK
gps-disable.chat

# shutdown -r now

