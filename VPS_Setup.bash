#!/bin/bash
if [[ $EUID -ne 0 ]]; then
  echo "This script must be run as root" 
  exit 1
fi

dir=$PWD
inet=$(ip route show default | awk '/default/ {print $5}')
ipaddr="$(hostname -I | awk '{print $1}')"
ipaddr6="$(hostname -I | awk '{print $NF}')"
[ -f /etc/os-release ] && distro="$(grep -w ID /etc/os-release | sed 's/ID=//')" || distro="unknown"

# User Setable Variables
pihole_skip_os_check=false
intip="10.0.0"
intip6="2607:55:55:55"
wgport=51820
sshport=1024
dnsport=5354
devs="dev1 dev2 dev3"

# Setup
echo "Updating and installing packages"
echo "Keep installed copies if asked!"
sleep 3
apt update && apt upgrade -y
apt install linux-headers-$(uname -r | sed 's/[0-9.-]*//') -y # Install kernel headers if not installed (reinstall won't hurt) - needed for digitalocean and possibly others
apt install sudo fail2ban curl python3 -y
apt install lsof speedtest-cli dnsutils htop -y # Optional for testing/monitoring purposes
echo "Configuring security measures"
sleep 1
sed -i -e 's|maxretry = 5|maxretry = 3|' -e "s|^#ignoreip = .*|ignoreip = 127.0.0.1/8 ::1 $intip.0/24 $intip6::1 $ipaddr|" /etc/fail2ban/jail.conf
systemctl enable fail2ban
systemctl start fail2ban
sed -ri "s/^#Port.*|^Port.*/Port $sshport/" /etc/ssh/sshd_config
service sshd restart

echo "Setting up UFW"
sleep 1
apt install ufw -y
# SSH rule
ufw allow $sshport/tcp
# Pi-hole rules - See here: https://docs.pi-hole.net/main/prerequisites/#ports
ufw allow 53/tcp # pihole-FTL
ufw allow 53/udp # pihole-FTL
ufw allow 67/udp # pihole-FTL - DHCP
ufw allow 67/tcp # pihole-FTL - DHCP
ufw allow 546:547/udp # pihole-FTL - DHCPv6
ufw allow 80/tcp # lighttpd - webserver
# Wireguard rules
ufw allow $wgport/udp
sed -i 's/DEFAULT_FORWARD_POLICY="DROP"/DEFAULT_FORWARD_POLICY="ACCEPT"/' /etc/default/ufw
sed -i "1i# START WIREGUARD RULES\n# NAT table rules\n*nat\n:POSTROUTING ACCEPT [0:0]\n# Allow traffic from WIREGUARD client \n-A POSTROUTING -s $intip.0/24 -o $inet -j MASQUERADE\nCOMMIT\n# END WIREGUARD RULES\n" /etc/ufw/before.rules
sed -i "/# End required lines/a-A INPUT -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT\n-A INPUT -p udp -m udp --dport $wgport -m conntrack --ctstate NEW -j ACCEPT\n-A INPUT -s $intip.0/24 -p tcp -m tcp --dport 53 -m conntrack --ctstate NEW -j ACCEPT\n-A INPUT -s $intip.0/24 -p udp -m udp --dport 53 -m conntrack --ctstate NEW -j ACCEPT\n-A FORWARD -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT\n-A FORWARD -i wg0 -o wg0 -m conntrack --ctstate NEW -j ACCEPT" /etc/ufw/before.rules
sed -i "/-A ufw-before-input -p icmp --icmp-type echo-request -j ACCEPT/a# allow outbound icmp\n-A ufw-before-output -p icmp -m state --state NEW,ESTABLISHED,RELATED -j ACCEPT\n-A ufw-before-output -p icmp -m state --state ESTABLISHED,RELATED -j ACCEPT\n" /etc/ufw/before.rules
sed -i "1i# START WIREGUARD RULES\n# NAT table rules\n*nat\n:POSTROUTING ACCEPT [0:0]\n# Allow traffic from WIREGUARD client \n\n-A POSTROUTING -s $intip6::/112 -o $inet -j MASQUERADE\nCOMMIT\n# END WIREGUARD RULES\n" /etc/ufw/before6.rules
sed -i "/# End required lines/a-A INPUT -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT\n-A INPUT -p udp -m udp --dport $wgport -m conntrack --ctstate NEW -j ACCEPT\n-A INPUT -s $intip6::1/64 -p tcp -m tcp --dport 53 -m conntrack --ctstate NEW -j ACCEPT\n-A INPUT -s $intip6::1/64 -p udp -m udp --dport 53 -m conntrack --ctstate NEW -j ACCEPT\n-A FORWARD -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT\n-A FORWARD -i wg0 -o wg0 -m conntrack --ctstate NEW -j ACCEPT" /etc/ufw/before6.rules
sed -i 's@#net/ipv4/ip_forward=1@net/ipv4/ip_forward=1@g' /etc/ufw/sysctl.conf
sed -i 's@#net/ipv6/conf/default/forwarding=1@net/ipv6/conf/default/forwarding=1@g' /etc/ufw/sysctl.conf
sed -i 's@#net/ipv6/conf/all/forwarding=1@net/ipv6/conf/all/forwarding=1@g' /etc/ufw/sysctl.conf
ufw --force enable

echo "Setting up DNSCrypt-Proxy"
sleep 1
cd /opt
curl -sL $(curl -sL https://api.github.com/repos/DNSCrypt/dnscrypt-proxy/releases/latest | grep "https.*dnscrypt-proxy-linux_x86_64-.*.tar.gz\"" | awk '{print $2}' | sed 's/"//g') | tar xzf - --transform='s/linux-x86_64/dnscrypt-proxy/' 
cd dnscrypt-proxy
cp -f $dir/dnscrypt-proxy.toml .
sed -i "s/<port>/$dnsport/g" dnscrypt-proxy.toml
./dnscrypt-proxy -service install
./dnscrypt-proxy -service start
# Install minisign
curl -sL $(curl -sL https://api.github.com/repos/jedisct1/minisign/releases/latest | grep "https.*minisign-.*linux.tar.gz\"" | awk '{print $2}' | sed 's/"//g') | tar xzf -
cp -f minisign-*/x86_64/minisign minisign
chmod +x minisign
rm -rf minisign-*
# Setup auto-update script
cp -f $dir/dnscrypt-proxy-update.sh .
chmod +x dnscrypt-proxy-update.sh
echo "0 */12 * * * /url/local/dnscrypt-proxy-update.sh" > /var/spool/cron/crontabs/root
cd $dir

echo "Setting up Pi-hole"
mkdir -p /etc/dnsmasq.d /etc/lighttpd /etc/pihole
# Required for DNSSEC to work
echo "proxy-dnssec" > /etc/dnsmasq.d/02-dnscrypt.conf
# Only allow those connected to vpn to access pi-hole
echo -e '$HTTP["remoteip"] !~ "'$intip'\." {\n  url.access-deny = ( "" )\n }' > /etc/lighttpd/external.conf
# Set pihole dns server to dnscrypt-proxy
echo -e "PIHOLE_INTERFACE=$inet\nDNSMASQ_LISTENING=local\nDNS_FQDN_REQUIRED=false\nDNS_BOGUS_PRIV=false\nDNSSEC=true\nPIHOLE_DNS_1=127.0.0.1#$dnsport\nPIHOLE_DNS_2=::1#$dnsport" > /etc/pihole/setupVars.conf
curl -sSL https://install.pi-hole.net | PIHOLE_SKIP_OS_CHECK=$pihole_skip_os_check bash /dev/stdin --unattended
echo ""
pihole -a -p
# Setup whitelist
git clone https://github.com/anudeepND/whitelist.git /opt/whitelist
python3 /opt/whitelist/scripts/whitelist.py
echo "0 1 * * */7     root    /opt/whitelist/scripts/whitelist.py" > /var/spool/cron/crontabs/root

echo "Setting up wireguard"
sleep 1
if [ "$distro" == "debian" ]; then
  # Set up testing repo for wireguard
  echo "deb http://deb.debian.org/debian/ testing main" > /etc/apt/sources.list.d/testing.list
  printf 'Package: *\nPin: release a=testing\nPin-Priority: 90\n' >> /etc/apt/preferences.d/limit-testing
  apt update -y
  apt install wireguard -t testing -y
else
  apt install wireguard -y
fi
apt install qrencode -y
sed -i "1a intip=\"$intip\"\nintip6="$intip6"\nwgport=$wgport" $dir/Wireguard_After.bash
mkdir $dir/wgconfs
umask 077
cd /etc/wireguard
mkdir wgkeys

# Server
wg genpsk > preshared-key
wg genkey | tee server-privkey | wg pubkey > server-pubkey
echo "[Interface]
Address = $intip.1/24, $intip6::1/64
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
AllowedIPs = $intip.$count/32, $intip6::$count/128" >> wg0.conf

  echo "[Interface]
Address = $intip.$count/24, $intip6::$count/64
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
  cp -f $i.conf $dir/wgconfs/$i.conf
  count=$((count+1))
done
mv -f *-privkey *-pubkey wgkeys/

chown -R root:root *
chmod -R og-rwx *
umask 0022
cd $dir
systemctl enable wg-quick@wg0.service
systemctl start wg-quick@wg0.service

echo "All Done!"
exit 0
