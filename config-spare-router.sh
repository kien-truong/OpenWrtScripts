#!/bin/sh
# Configure a "spare router" to a known-good state.

# This script configures the factory default settings of OpenWrt
#   to make it easy to swap it in when a new router is needed.
# It also creates a label showing the configuration and credentials.
#   You can print the label and tape it to the router so
#   the next person will know how to access the router.
#   The label format is:
#
# ======= Printed with: print-router-label.sh =======
#      Device: Linksys E8450 (UBI)
#     OpenWrt: OpenWrt 23.05.5 r24106-10cc5fcd00
#  Connect to: http://Belkin-RT3200.local
#          or: ssh root@Belkin-RT3200.local
#         LAN: 192.168.253.1
#        User: root
#    Login PW: root-password
#   Wifi SSID: My Wifi SSID
#     Wifi PW: abcd9876
#  Configured: 2024-11-28
# === See github.com/richb-hanover/OpenWrtScripts ===
#
# Label for Power Brick: Linksys E8450 (UBI)

# ***** To run this script *****
#
# 0. (Optional) Make a backup of the current router config.
#    It'll be easy to restore if necessary.
# 1. Connect your laptop on a wired LAN port (Ethernet):
#    some of these changes can reset the wireless network.
# 2. Connect the router's WAN port to the internet: this
#    script needs to install certain packages. (Perhaps
#    plug its WAN port into your new router's LAN port 
#    while running this script.)
# 3. Flash the router with factory firmware.
#    Do NOT keep the settings.
# 4. SSH in and execute the statements below. 
# 
#    ssh root@192.168.1.1    # the default OpenWrt LAN address
#    cd /tmp
#    cat > config.sh 
#    [paste in the entire contents of this file, then hit ^D]
#    sh config.sh
#    Presto! (The router reboots when the script completes.)
#
# The script sets generic settings and credentials.
# You could make a copy of this script, customize it to your needs,
# then use the "To run this script" procedure (below).
#

# === print_router_label() ===
# This function is copy/pasted from "print-router-label.sh"
# to keep the "config-spare-router.sh" script a single file.
# THIS IS A MAINTENANCE HASSLE: 
# Changes to the printing must be updated in both places
print_router_label() {
	local ROOTPASSWD="${1:-"?"}" 
	TODAY=$(date +"%Y-%m-%d")
	DEVICE=$(cat /tmp/sysinfo/model)
	OPENWRTVERSION=$(grep "DISTRIB_DESCRIPTION" /etc/openwrt_release | cut -d"=" -f2 | tr -d '"' | tr -d "'")
	HOSTNAME=$(uci get system.@system[0].hostname)
	LANIPADDRESS=$(uci get network.lan.ipaddr)
	LOCALDNSTLD=$(uci get dhcp.@dnsmasq[0].domain) # top level domain for local names

	# Create temporary file for both SSID and password
	TMPFILE=$(mktemp /tmp/wifi_creds.XXXXXX)

	# Get wifi credentials
	uci show wireless |\
	egrep =wifi-iface$ |\
	cut -d= -f1 |\
	while read s;
	    do uci -q get $s.disabled |\
	    grep -q 1 && continue;
	    id=$(uci -q get $s.ssid);
	    key=$(uci -q get $s.key);
	    # Write both SSID and password to temporary file
	    echo "$id:$key" > "$TMPFILE"
	    break
	done

	# Read both values from temporary file
	if [ -f "$TMPFILE" ]; then
	    WIFISSID=$(cut -d: -f1 "$TMPFILE")
	    WIFIPASSWD=$(cut -d: -f2 "$TMPFILE")
	    # Check if password is empty and replace with "<no password>"
	    if [ -z "$WIFIPASSWD" ]; then
	        WIFIPASSWD="<no password>"
	    fi
	else
	    WIFISSID="unknown"
	    WIFIPASSWD="unknown"
	fi

	# Clean up temporary file
	rm -f "$TMPFILE"

	echo ""
	echo "Print the following label and tape it to the router..."
	echo ""
	echo "======= Printed with: print-router-label.sh ======="
	echo "     Device: $DEVICE"
	echo "    OpenWrt: $OPENWRTVERSION" 
	echo " Connect to: http://$HOSTNAME.$LOCALDNSTLD" 
	echo "         or: ssh root@$HOSTNAME.$LOCALDNSTLD"
	echo "        LAN: $LANIPADDRESS"
	echo "       User: root"
	echo "   Login PW: $ROOTPASSWD"
	echo "  Wifi SSID: $WIFISSID"
	echo "    Wifi PW: $WIFIPASSWD"
	echo " Configured: $TODAY"
	echo "=== See github.com/richb-hanover/OpenWrtScripts ==="
	echo ""
	echo "Label for Power Brick: $DEVICE"
	echo ""
}

# === CONFIGURATION PARAMETERS ===
# Set the variables to be used for configuration

HOSTNAME="SpareRouter"
ROOTPASSWD="SpareRouter"
TIMEZONE='EST5EDT,M3.2.0,M11.1.0' # see link below for other time zones
ZONENAME='America/New York'			
LANIPADDRESS="172.30.42.1"        # 172.30.42.1 minimizes chance of conflict
LANSUBNET="255.255.255.0"
SNMP_COMMUNITYSTRING=public
WIFISSID="SpareRouter"
WIFIPASSWD=''
ENCRMODE='none'

# === Update root password =====================
# Update the root password. 
# 
echo '*** Updating root password'
passwd <<EOF
$ROOTPASSWD
$ROOTPASSWD
EOF

# === Set the hostname ========================
# Also displayed in LuCI GUI. Used for:
# ssh root@$HOSTNAME.local and http://$HOSTNAME.local
echo '*** Setting host name'
uci set system.@system[0].hostname="$HOSTNAME"
uci commit system

# === Update the LAN address ==================
# Change the default 192.168.1.1 to $LANIPADDRESS
# Make the change in the /etc/config/network file to avoid
# perturbing the SSH session. Reboot at the end of the script
echo "*** Changing IP address to $LANIPADDRESS"
sed -i s#192.168.1.1#$LANIPADDRESS#g /etc/config/network
# sleep 5

# === Enable Wifi on the first radio with configured parameters
# Open one radio for access
# Use its default channel
#
echo "*** Setting Wifi Parameters"
uci set wireless.@wifi-iface[0].ssid="$WIFISSID"
uci set wireless.@wifi-iface[0].key="$WIFIPASSWD"
uci set wireless.@wifi-iface[0].encryption="$ENCRMODE"
uci set wireless.@wifi-iface[0].disabled='0'
uci set wireless.@wifi-device[0].disabled='0'
uci commit wireless

# === Set the Time Zone ========================
# Set the time zone to non-default (other than UTC)
# Full list of time zones is at:
# https://github.com/openwrt/luci/blob/master/modules/luci-lua-runtime/luasrc/sys/zoneinfo/tzdata.lua
#
echo "*** Setting timezone to $TIMEZONE"
uci set system.@system[0].timezone="$TIMEZONE"
echo "*** Setting zone name to $ZONENAME"
uci set system.@system[0].zonename="$ZONENAME"
uci commit system

# === Update the software packages =============
# Download and update all the interesting packages
# Some of these are pre-installed, but there is no harm in
# updating/installing them a second time.
echo '*** Updating software packages'
opkg -V0 update                # retrieve updated packages
opkg -V0 install luci          # install the web GUI
opkg -V0 install umdns         # install mDNS responder
opkg -V0 install luci-app-sqm  # install the SQM modules to get fq_codel etc
opkg -V0 install travelmate	   # install the travelmate package to be a repeater
opkg -V0 install luci-app-travelmate # and its LuCI GUI

echo '*** SpareRouter configuration complete'

# === Print the configuration label ===

print_router_label "$ROOTPASSWD" 

# === Everything is done - reboot ===
echo "Rebooting the router now for these changes to take effect..."
echo "  You should now make a new connection to $LANIPADDRESS."
echo ""

reboot

# --- end of script ---

# ================ 
# 
# The following sections are historical, and can be ignored:
#
# - Enable NetFlow export for traffic analysis
# - Enable mDNS/ZeroConf on eth0 for internal routers *only* 
# - Change default IP addresses and subnets for interfaces
# - Change default DNS names
# - Set the radio channels
# - Set wireless SSID names
# - Set the wireless security credentials

# opkg -V0 install netperf	   # install the netperf module for speed testing
# opkg -V0 install ppp-mod-pppoe # install PPPoE module
# opkg -V0 install avahi-daemon  # install the mDNS daemon
# opkg -V0 install fprobe        # install fprobe netflow exporter
# opkg -V0 install snmpd         # install snmpd 

# === Enable NetFlow export ====================
# NetFlow export
# Start fprobe now to send netflow records to local netflow 
#   collector at the following address and port (I use http://intermapper.com) 
# Supply values for NETFLOWCOLLECTORADRS & NETFLOWCOLLECTORADRS
# and uncomment nine lines
#
# NETFLOWCOLLECTORADRS=192.168.2.13
# NETFLOWCOLLECTORPORT=2055
# echo 'Configuring and starting fprobe...'
# fprobe -i ge00 -f ip -d 15 -e 60 $NETFLOWCOLLECTORADRS':'$NETFLOWCOLLECTORPORT
# Also edit /etc/rc.local to add the same command 
#   so that it will start after next reboot
# sed -i '$ i\
# fprobe -i ge00 -f ip -d 15 -e 60 NEWIPPORT' /etc/rc.local
# sed -i s#NEWIPPORT#$NETFLOWCOLLECTORADRS:$NETFLOWCOLLECTORPORT#g /etc/rc.local

# === Enable SNMP daemon =======================
# Enables responses on IPv4 & IPv6 with same read-only community string
# Supply values for COMMUNITYSTRING and uncomment eleven lines.
# echo '*** Configuring and starting snmpd ***'
# uci set snmpd.@agent[0].agentaddress='UDP:161,UDP6:161'
# uci set snmpd.@com2sec[0].community=$SNMP_COMMUNITYSTRING
# uci add snmpd com2sec6
# uci set snmpd.@com2sec6[-1].secname=ro
# uci set snmpd.@com2sec6[-1].source=default
# uci set snmpd.@com2sec6[-1].community=$SNMP_COMMUNITYSTRING
# uci commit snmpd
# /etc/init.d/snmpd restart   # default snmpd config uses 'public' 
# /etc/init.d/snmpd enable  	# community string for SNMPv1 & SNMPv2c

# ==============================
# Set Smart Queue Management (SQM) values for your own network
#
# Use a speed test (http://speedtest.net or other) to determine 
# the speed of your own network, then set the speeds  accordingly.
# Speeds below are in kbits per second (3000 = 3 megabits/sec)
# For details about setting the SQM for your router, see:
# https://openwrt.org/docs/guide-user/network/traffic-shaping/sqm
# Set DOWNLOADSPEED, UPLOADSPEED, WANIF and then uncomment 18 lines
#
# DOWNLOADSPEED=20000
# UPLOADSPEED=2000
# WANIF=eth0
# echo 'Setting SQM on '$WANIF ' to ' $DOWNLOADSPEED/$UPLOADSPEED 'kbps down/up'
# uci set sqm.@queue[0].interface=$WANIF
# uci set sqm.@queue[0].enabled=1
# uci set sqm.@queue[0].download=$DOWNLOADSPEED
# uci set sqm.@queue[0].upload=$UPLOADSPEED
# uci set sqm.@queue[0].script='simple.qos' # Already the default
# uci set sqm.@queue[0].qdisc='fq_codel'
# uci set sqm.@queue[0].itarget='auto'
# uci set sqm.@queue[0].etarget='auto'
# uci set sqm.@queue[0].linklayer='atm'
# uci set sqm.@queue[0].overhead='44'
# uci commit sqm
# /etc/init.d/sqm restart
# /etc/init.d/sqm enable

# === Update local DNS domain ==================
# DNS: 
# Supply a desired DNS name for NEWDNS and uncomment three lines
#
# NEWDNS=home.lan
# echo 'Changing local domain to' $NEWDNS
# sed -i s#home.lan#$NEWDNS#g /etc/config/*  

# === Update WiFi info for the access point ================
# a) Assign the radio channels
# b) Assign the SSID's
# c) Assign the encryption/passwords
# To see all the wireless info:
#	uci show wireless
#
# Default interface indices and SSIDs are:
#	0 - CEROwrt
#	1 - CEROwrt-guest
#	2 - babel (on 2.4GHz)
#	3 - CEROwrt5
#	4 - CEROwrt-guest5
#	5 - babel (on 5GHz)

# === Assign channels for the wireless radios
# Set the channels for the wireless radios
# Radio0 choices are 1..11
# Radio1 choices are 36, 40, 44, 48, 149, 153, 157, 161, 165
#    The default HT40+ settings bond 36&40, 44&48, etc.
#    Choose 36 or 44 and it'll work fine
# echo 'Setting 2.4 & 5 GHz channels'
# uci set wireless.radio0.channel=6
# uci set wireless.radio1.channel=44

# === Assign the SSID's
# These are the default SSIDs for CeroWrt; no need to set again
# echo 'Setting SSIDs'
# uci set wireless.@wifi-iface[0].ssid=CEROwrt
# uci set wireless.@wifi-iface[1].ssid=CEROwrt-guest
# uci set wireless.@wifi-iface[3].ssid=CEROwrt5
# uci set wireless.@wifi-iface[4].ssid=CEROwrt-guest5

# === Assign the encryption/password ================
# Update the wifi password/security. To see all the wireless info:
#	uci show wireless
# The full list of encryption modes is at: (psk2 gives WPA2-PSK)
# https://openwrt.org/docs/guide-user/network/wifi/basic#encryption_modes 
# echo 'Updating WiFi security information'

# uci set wireless.@wifi-iface[0].key=$WIFIPASSWD
# uci set wireless.@wifi-iface[1].key=$WIFIPASSWD
# uci set wireless.@wifi-iface[3].key=$WIFIPASSWD
# uci set wireless.@wifi-iface[4].key=$WIFIPASSWD

# uci set wireless.@wifi-iface[0].encryption=$ENCRMODE
# uci set wireless.@wifi-iface[1].encryption=$ENCRMODE
# uci set wireless.@wifi-iface[3].encryption=$ENCRMODE
# uci set wireless.@wifi-iface[4].encryption=$ENCRMODE

# uci commit wireless

# === Set up the WAN (eth0) interface for PPPoE =============
# Default is DHCP, this sets it to PPPoE (typical for DSL/ADSL) 
# From http://wiki.openwrt.org/doc/howto/internet.connection
# Supply values for DSLUSERNAME and DSLPASSWORD 
# and uncomment ten lines
#
# echo 'Configuring WAN link for PPPoE'
# DSLUSERNAME=YOUR-DSL-USERNAME
# DSLPASSWORD=YOUR-DSL-PASSWORD
# uci set network.wan.proto=pppoe
# uci set network.wan.username=$DSLUSERNAME
# uci set network.wan.password=$DSLPASSWORD
# uci commit network
# ifup wan
# echo 'Waiting for link to initialize'
# sleep 20

# === Enable mDNS/ZeroConf =====================
# mDNS allows devices to look each other up by name
# This enables mDNS lookups on the LAN (br-lan) interface
# mDNS was useful in CeroWrt because all its interaces
# were routed. In OpenWrt, interfaces are bridge by default
# Uncomment seven lines
# echo 'Enabling mDNS on LAN interface'
# sed -i '/use-iff/ a \
# allow-interfaces=br-lan \
# enable-dbus=no ' /etc/avahi/avahi-daemon.conf
# sed -i s/enable-reflector=no/enable-reflector=yes/ /etc/avahi/avahi-daemon.conf
# /etc/init.d/avahi-daemon start
# /etc/init.d/avahi-daemon enable
