#!/bin/bash
if [[ $EUID -ne 0 ]]; then
  echo "This script must be run as root" 
  exit 1
fi

dir=$PWD
inet=$(ip route show default | awk '/default/ {print $5}')
ipaddr="$(hostname -I | awk '{print $1}')"
ipaddr6="$(hostname -I | awk '{print $2}')"
[ -f /etc/os-release ] && distro="$(grep -w ID /etc/os-release | sed 's/ID=//')" || distro="unknown"

# User Setable Variables
pihole_skip_os_check=false
intipaddr="10.0.0"
intipaddr6="2607:55:55:55"
wgport=51820
sshport=1024
devs="dev1 dev2 dev3"
# searx=true
# custdomain=anonzackptg5.com
# uport=5353
dpport=5354
# cfrport=5053

# Setup
echo "Updating and installing packages"
echo "Keep installed copies if asked!"
sleep 3
apt update && apt upgrade -y
apt install sudo fail2ban curl -y
apt install speedtest-cli dnsutils htop -y # Optional for testing/monitoring purposes
echo "Configuring security measures"
sleep 1
sed -i -e 's|maxretry = 5|maxretry = 3|' -e "s|^#ignoreip = .*|ignoreip = 127.0.0.1/8 ::1 $intipaddr.0/24 $intipaddr6::1 $ipaddr|" /etc/fail2ban/jail.conf
systemctl enable fail2ban
systemctl start fail2ban
sed -ri -e 's/^#PermitEmptyPasswords .*|^PermitEmptyPasswords yes/PermitEmptyPasswords no/' -e "s/^#Port.*|^Port.*/Port $sshport/" /etc/ssh/sshd_config
service sshd restart

echo "Setting up UFW"
sleep 1
apt install ufw -y
# Wireguard rule
ufw allow $wgport/udp
# SSH rule
ufw allow $sshport/tcp
# Pi-hole rules
ufw allow 80/tcp
ufw allow 53/tcp
ufw allow 53/udp
ufw allow 67/tcp
ufw allow 67/udp
ufw allow 546:547/udp
# Wireguard rules
sed -i 's/DEFAULT_FORWARD_POLICY="DROP"/DEFAULT_FORWARD_POLICY="ACCEPT"/' /etc/default/ufw
sed -i "1i# START WIREGUARD RULES\n# NAT table rules\n*nat\n:POSTROUTING ACCEPT [0:0]\n# Allow traffic from WIREGUARD client \n-A POSTROUTING -s $intipaddr.0/24 -o $inet -j MASQUERADE\nCOMMIT\n# END WIREGUARD RULES\n" /etc/ufw/before.rules
sed -i "/# End required lines/a-A INPUT -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT\n-A INPUT -p udp -m udp --dport $wgport -m conntrack --ctstate NEW -j ACCEPT\n-A INPUT -s $intipaddr.0/24 -p tcp -m tcp --dport 53 -m conntrack --ctstate NEW -j ACCEPT\n-A INPUT -s $intipaddr.0/24 -p udp -m udp --dport 53 -m conntrack --ctstate NEW -j ACCEPT\n-A FORWARD -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT\n-A FORWARD -i wg0 -o wg0 -m conntrack --ctstate NEW -j ACCEPT" /etc/ufw/before.rules
sed -i "/-A ufw-before-input -p icmp --icmp-type echo-request -j ACCEPT/a# allow outbound icmp\n-A ufw-before-output -p icmp -m state --state NEW,ESTABLISHED,RELATED -j ACCEPT\n-A ufw-before-output -p icmp -m state --state ESTABLISHED,RELATED -j ACCEPT\n" /etc/ufw/before.rules
sed -i "1i# START WIREGUARD RULES\n# NAT table rules\n*nat\n:POSTROUTING ACCEPT [0:0]\n# Allow traffic from WIREGUARD client \n\n-A POSTROUTING -s $intipaddr6::/112 -o $inet -j MASQUERADE\nCOMMIT\n# END WIREGUARD RULES\n" /etc/ufw/before6.rules
sed -i "/# End required lines/a-A INPUT -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT\n-A INPUT -p udp -m udp --dport $wgport -m conntrack --ctstate NEW -j ACCEPT\n-A INPUT -s $intipaddr6::1/64 -p tcp -m tcp --dport 53 -m conntrack --ctstate NEW -j ACCEPT\n-A INPUT -s $intipaddr6::1/64 -p udp -m udp --dport 53 -m conntrack --ctstate NEW -j ACCEPT\n-A FORWARD -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT\n-A FORWARD -i wg0 -o wg0 -m conntrack --ctstate NEW -j ACCEPT" /etc/ufw/before6.rules

echo "Configuring sysctl"
sleep 1
sed -i 's/#net.ipv4.ip_forward=1/net.ipv4.ip_forward=1/g' /etc/sysctl.conf
sed -i 's/#net.ipv6.conf.all.forwarding=1/net.ipv6.conf.all.forwarding=1/g' /etc/sysctl.conf
sed -i 's@#net/ipv4/ip_forward=1@net/ipv4/ip_forward=1@g' /etc/ufw/sysctl.conf
sed -i 's@#net/ipv6/conf/default/forwarding=1@net/ipv6/conf/default/forwarding=1@g' /etc/ufw/sysctl.conf
sed -i 's@#net/ipv6/conf/all/forwarding=1@net/ipv6/conf/all/forwarding=1@g' /etc/ufw/sysctl.conf

if [ "$distro" == "debian" ]; then
  # Set up unstable repo for wireguard and dnscrypt-proxy
  echo "deb http://deb.debian.org/debian/ unstable main" > /etc/apt/sources.list.d/unstable.list
  printf 'Package: *\nPin: release a=unstable\nPin-Priority: 90\n' >> /etc/apt/preferences.d/limit-unstable
  apt update -y
fi

echo "Setting up Pi-hole v5.0"
echo "Select any dns server - it'll get changed by this script"
sleep 3
curl -sSL https://install.pi-hole.net | PIHOLE_SKIP_OS_CHECK=$pihole_skip_os_check bash
sed -i "s/domain_name_servers=.*/domain_name_servers=$ipaddr $ipaddr6/" /etc/dhcpcd.conf
echo "Set password to whatever"
sleep 1
pihole -a -p
# Required for DNSSEC to work
echo "proxy-dnssec" > /etc/dnsmasq.d/02-dnscrypt.conf

if [ "$uport" ]; then
  echo "Setting up Unbound"
  sleep 1
  port=$uport
  apt install unbound unbound-host -y
  curl -o /var/lib/unbound/root.hints https://www.internic.net/domain/named.cache
  chown -R unbound:unbound /var/lib/unbound
  sed -i -e "s/<port>/$uport/" -e "s/<ipaddr>/$ipaddr/g" -e "s/<intipaddr>/$intipaddr/g" -e "s/<intipaddr6>/$intipaddr6/g" pi-hole.conf
  mv -f pi-hole.conf /etc/unbound/unbound.conf.d/pi-hole.conf
  # Fix for no dns for wireguard client issue
  systemctl disable unbound
  sed -i 's/^After=network.target/After=wg-quick@wg0.service/' /lib/systemd/system/unbound.service
fi
if [ "$cfrport" ]; then
  echo "Setting up cloudflared"
  sleep 1
  [ "$uport" ] && sed -i "/^ *name:/a        forward-addr: 127.0.0.1@$cfrport#\n        forward-addr: ::1@$cfrport" /etc/unbound/unbound.conf.d/pi-hole.conf || port=$cfrport
  wget https://bin.equinox.io/c/VdrWdbjqyF/cloudflared-stable-linux-amd64.deb
  apt install ./cloudflared-stable-linux-amd64.deb && rm -f cloudflared-stable-linux-amd64.deb
  cloudflared -v
  mkdir /etc/cloudflared
  echo -e "proxy-dns: true\nproxy-dns-port: $cfrport\nproxy-dns-upstream:\n  - https://1.1.1.1/dns-query\n  - https://1.0.0.1/dns-query\n  - https://[2606:4700:4700::1111]/dns-query\n  - https://[2606:4700:4700::1001]/dns-query" > /etc/cloudflared/config.yml
  cloudflared service install --legacy
  systemctl start cloudflared
  # Setup weekly update check since not in repo
  echo -e "cloudflared update\nsystemctl restart cloudflared" > /etc/cron.weekly/cloudflared-updater.sh
  chmod +x /etc/cron.weekly/cloudflared-updater.sh
  chown root:root /etc/cron.weekly/cloudflared-updater.sh
  sed -i '/cache-size/d' $dir/Pihole_After_Update.bash
elif [ "$dpport" ]; then
  echo "Setting up dnscrypt"
  sleep 1
  [ "$uport" ] && sed -i "/^ *name:/a\        forward-addr: 127.0.0.1@$dpport\n        forward-addr: ::1@$dpport" /etc/unbound/unbound.conf.d/pi-hole.conf || port=$dpport
  [ "$distro" = "debian" ] && apt install -t unstable dnscrypt-proxy || apt install dnscrypt-proxy
  mv -f dnscrypt-proxy.toml /etc/dnscrypt-proxy/dnscrypt-proxy.toml
  sed -i "s/\(.*\)=127..*/\1=127.0.0.1:$dpport\n\1=[::1]:$dpport/g" /lib/systemd/system/dnscrypt-proxy.socket
  # Disable pihole cache, redundant and seems to slow things down
  sed -i "s/cache-size=.*/cache-size=0/g" /etc/dnsmasq.d/01-pihole.conf
  sed -i "s/CACHE_SIZE=.*/CACHE_SIZE=0/" /etc/pihole/setupVars.conf
elif [ "$uport" ]; then
  # Use cloudflare
  sed -i "/^ *name:/a\        forward-addr: 1.1.1.1@53#cloudflare-dns.com\n        forward-addr: 1.0.0.1@53#cloudflare-dns.com" /etc/unbound/unbound.conf.d/pi-hole.conf
  # Disable pihole cache, redundant and seems to slow things down
  sed -i "s/cache-size=.*/cache-size=0/g" /etc/dnsmasq.d/01-pihole.conf
  sed -i "s/CACHE_SIZE=.*/CACHE_SIZE=0/" /etc/pihole/setupVars.conf
else
  sed -i '/cache-size/d' $dir/Pihole_After_Update.bash
fi

# Now we can start it since forward addresses are set
if [ "$uport" ]; then
  systemctl enable unbound
  systemctl start unbound
fi

echo "Setting up wireguard"
sed -i "1a intipaddr=\"$intipaddr\"\nintipaddr6="$intipaddr6"\nwgport=$wgport" $dir/Wireguard_After.bash
sleep 1
apt install wireguard qrencode -y
umask 077
cd /etc/wireguard

# Server
wg genpsk > preshared-key
wg genkey | tee server-privkey | wg pubkey > server-pubkey
echo "[Interface]
Address = $intipaddr.1/24, $intipaddr6::1/64
ListenPort = $wgport
PrivateKey = $(<server-privkey)
PostUp = iptables -A FORWARD -i wg0 -j ACCEPT; iptables -A FORWARD -o wg0 -j ACCEPT; iptables -t nat -A POSTROUTING -o $inet -j MASQUERADE
PostDown = iptables -D FORWARD -i wg0 -j ACCEPT; iptables -D FORWARD -o wg0 -j ACCEPT; iptables -t nat -D POSTROUTING -o $inet -j MASQUERADE" > wg0.conf

# Clients
count=2
for i in $devs; do
  wg genkey | tee $i-privkey | wg pubkey > $i-pubkey
  echo "
[Peer]
# $i
PublicKey = $(<$i-pubkey)
PresharedKey = $(<preshared-key)
AllowedIPs = $intipaddr.$count/32, $intipaddr6::$count/128" >> wg0.conf

  echo "[Interface]
Address = $intipaddr.$count/24, $intipaddr6::$count/64
MTU = 1420
DNS = $ipaddr, $ipaddr6
PrivateKey = $(<$i-privkey)

[Peer]
PublicKey = $(<server-pubkey)
PresharedKey = $(<preshared-key)
Endpoint = $ipaddr:$wgport
AllowedIPs = 0.0.0.0/0, ::/0" > $i.conf

  echo "$i:"
  qrencode -t ansiutf8 < $i.conf
  sleep 1
  cp -f $i.conf $dir/$i.conf
  count=$((count+1))
done

chown -R root:root *
chmod -R og-rwx *
umask 0022
cd $dir
systemctl enable wg-quick@wg0.service
systemctl start wg-quick@wg0.service

# Set DNS servers
if [ "$port" ]; then
  sed -ri "/^PIHOLE_DNS|^DNS_FQDN_REQUIRED|^DNS_BOGUS_PRIV|^DNSSEC|^DNSMASQ_LISTENING|^PIHOLE_INTERFACE/d" /etc/pihole/setupVars.conf
  echo -e "PIHOLE_INTERFACE=$inet\nDNSMASQ_LISTENING=local\nDNS_FQDN_REQUIRED=false\nDNS_BOGUS_PRIV=false\nDNSSEC=false" >> /etc/pihole/setupVars.conf
fi
case $port in
  $uport) echo -e "PIHOLE_DNS_1=127.0.0.1#$uport\nPIHOLE_DNS_2=::1#$uport" >> /etc/pihole/setupVars.conf;;
  $cfrport) echo -e "PIHOLE_DNS_1=127.0.0.1#$cfrport\nPIHOLE_DNS_2=::1#$cfrport" >> /etc/pihole/setupVars.conf;;
  $dpport) echo -e "PIHOLE_DNS_1=127.0.0.1#$dpport\nPIHOLE_DNS_2=::1#$dpport" >> /etc/pihole/setupVars.conf;;
  *) sed -i -e "s/DNSMASQ_LISTENING=.*/DNSMASQ_LISTENING=local/g" -e "s/PIHOLE_INTERFACE=.*/PIHOLE_INTERFACE=$inet/g" /etc/pihole/setupVars.conf;;
esac

# Only allow those connected to vpn to access pi-hole
echo -e '$HTTP["remoteip"] !~ "'$intipaddr'\." {\n  url.access-deny = ( "" )\n }' > /etc/lighttpd/external.conf

# Reload ufw
ufw --force enable
ufw reload

if [ "$searx" ]; then
  # Install searx
  cd /opt
  git clone https://github.com/searx/searx searx
  cd searx
  sed -in "/SEARX_INTERNAL_URL/p; s/SEARX_INTERNAL_URL/SEARX_INTERNAL_HTTP/" .config.sh
  sed -ri "s/#(.*)127.0.0.1(.*)/\1$intipaddr.1\2/g" .config.sh
  ./utils/searx.sh install all
  ./utils/filtron.sh install all
  ufw allow 4004/tcp
  # Add link to searx search from main page
  if [ "$custdomain" ]; then
    sed -i "s/instance_name : \".*\"/instance_name : \"$(echo $custdomain | cut -d . -f1)\"/" /etc/searx/settings.yml
    sed -i "/admin panel?/a\            <a href='http://$custdomain:4004'></br>Or did you mean to go to Searx?</a>" /var/www/html/pihole/index.php
  else
    sed -i "/admin panel?/a\            <a href='http://$intipaddr.1:4004'></br>Or did you mean to go to Searx?</a>" /var/www/html/pihole/index.php
  fi
  sed -i -e "s/secret_key : .*/secret_key : $(openssl rand -hex 16)/" -e 's/autocomplete : ".*" #/autocomplete : "google" #/' /etc/searx/settings.yml
  # Set dark theme, show advanced settings, and disable wikipedia (doesn't work) and bing by default
  sed -i "/image_proxy/a\ \nui:\n    advanced_search : True\n    theme_args :\n        oscar_style : logicodev-dark" /etc/searx/settings.yml
  sed -i "/image_proxy/a\ \nengines:\n  - name : wikipedia    engine : wikipedia    shortcut : wp    base_url : 'https://{language}.wikipedia.org/'    disabled : true\n  - name : bing\n    engine : bing\n    shortcut : bi\n    disabled : true" /etc/searx/settings.yml
  sed -i '/image_proxy/a\ \nenabled_plugins:\n  - "Open Access DOI rewrite"\n  - "Hash plugin"\n  - "HTTPS rewrite"\n  - "Infinite scroll"\n  - "Self Informations"\n  - "Search on category select"\n  - "Tracker URL remover"' /etc/searx/settings.yml
  # Set sci-hub to default, fix link (tw is dead)
  sed -i "s/oadoi.org/sci-hub.do/g" /usr/local/searx/searx-src/searx/preferences.py
  sed -i "s/sci-hub.tw/sci-hub.do/g" /usr/local/searx/searx-src/searx/settings.yml
  systemctl restart uwsgi
fi
# Add custom domain name as redirect for main page
if [ "$custdomain" ]; then
  sed -i "s/elseif (filter_var(\$serverName/elseif (\$serverName === \"$custdomain\" || filter_var(\$serverName/" /var/www/html/pihole/index.php
  echo "$intipaddr.1 $custdomain" >> /etc/pihole/custom.list
fi
sed -i "1a intipaddr=$intipaddr\nsearx=$searx\ncustdomain=$custdomain" $dir/Pihole_After_Update.bash

pihole restartdns
echo "Choose 'repair' when prompted"
sleep 3
pihole -r
bash Pihole_After_Update.bash

echo "All Done!"
echo "Rebooting!"
sleep 1
reboot
exit 0
