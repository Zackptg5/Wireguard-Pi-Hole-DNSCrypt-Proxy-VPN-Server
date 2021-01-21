#!/bin/bash
# To remove a client:
# wg set wg0 peer <public-key> remove
# systemctl restart wg-quick@wg0.service

if [[ $EUID -ne 0 ]]; then
  echo "This script must be run as root" 
  exit 1
fi

dir=$PWD
inet=$(ip route show default | awk '/default/ {print $5}')
ipaddr="$(hostname -I | awk '{print $1}')"
ipaddr6="$(hostname -I | awk '{print $3}')"

# Set to whatever new profiles you want
devs="new1 new2"

umask 077
cd /etc/wireguard

echo "Adding peers to wireguard config"
count=$((`grep -c '\[Peer\]' wg0.conf` + 2))
for i in $devs; do
  wg genkey | tee $i-privkey | wg pubkey > $i-pubkey
  echo "
[Peer]
# $i
PublicKey = $(<$i-pubkey)
PresharedKey = $(<preshared-key)
AllowedIPs = $intipaddr.$count/32, $intipaddr6::$count/128
PersistentkeepAlive = 60" >> wg0.conf

  echo "[Interface]
Address = $intipaddr.$count/24, $intipaddr6::$count/64
MTU = 1420
DNS = $ipaddr, $ipaddr6
PrivateKey = $(<$i-privkey)

[Peer]
PublicKey = $(<server-pubkey)
PresharedKey = $(<preshared-key)
Endpoint = $ipaddr:$wgport
AllowedIPs = 0.0.0.0/0, ::/0
PersistentKeepalive = 60" > $i.conf

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
wg addconf wg0 <(wg-quick strip wg0)
systemctl restart wg-quick@wg0.service

echo "All Done!"
exit 0
