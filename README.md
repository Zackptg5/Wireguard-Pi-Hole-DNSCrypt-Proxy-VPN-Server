# Wireguard-Pi-Hole-Cloudflared/Unbound/DNSCrypt-VPN-Server
Sets up your very own VPN server with my configs

## Requirements
* Debian 10 (newer will probably work too - check if you need unstable repos for latest wireguard and dnscrypt-proxy)
  * Maybe Ubuntu - haven't tested it myself so you're on your own there - dnscrypt-proxy is out of date, even in the PPA last I checked

## Options
* Can change some of the variables in the beginning (keep all but devs if you're unsure):
  * pihole_skip_os_check - set to true to skip the OS check during pihole install. Required for armbian and probably some other SBC distros
  * devs - name for each wireguard client/device conf you want to make
  * initipaddr/initipaddr6 - ipv4/6 internal address you want to use for wireguard
  * sshport - ssh port
  * wgport - wireguard port
  * cfrport - cloudflared port (optional)
  * uport - unbound port (optional)
  * dppport - dnscrypt-proxy port (optional)
  * searx - install searx (optional)
  * custdomain - name of custom domain you want redirected to main pihole landing page (optional)
* Uncomment the port variable if you want unbound
* Can change the unbound config (pi-hole.conf) how you want, don't change anything related to ips and ports though
* Can change dnscrypt-proxy.toml how you want, don't change listen_addresses
  * I recommend you change the servers and anonymized relays to the fastest for your location
  * Alternatively, comment out 'server_names' and replace the anon routes with: `{ server_name='*', via=['anon-relay-1', 'anon-relay-2'] }` setting the anon relays to whichever you like (closest to your location would be most optimal)

## Description
* Changes ssh port number for security reasons
* Locks down firewall with ufw to only allow relevant connections
* Installs fail2ban and sets up a couple rules for security
* Wireguard - vpn tunnel
* Pi-hole - ad blocker
* Cloudflared - DNS-Over-HTTPS proxy - encrypts dns requests - optional
* Unbound - local recursive/caching dns resolver with dnssec support - optional
* DNSCrypt-proxy - caches, encrypts, and annoymizes dns requests - optional
* Searx - metasearch engine - optional

## Configurations:
* Just Pi-hole - barebones, pick a dns server in the pihole gui - you need to trust your isp and selected upstream DNS server(s)
* Pi-hole + cloudflared - use cloudflare's DOH service - if you trust cloudflare more than your server's ISP
* Pi-hole + Unbound - increases privacy and uses dnssec - only entity you need to trust is your server's ISP (note that I have it set to use cloudflare but you can remove the forward zone or change this)
* Pi-hole + unbound + cloudflared
* Pi-hole + dnscrypt-proxy - use whatever dns servers you want - encrypts + anonymizes requests - you don't need to trust anyone
* Pi-hole + unbound + dnscrypt-proxy - same as above but with some local dns resolution via unbound - I don't see much point in this but it's here if you want it

## Super Simplified and Probably Partly Incorrect How it Works 
* Device connects to server via wireguard tunnel -> Pi-Hole filters out ads -> Unbound resolves DNS queries that it can (if you chose it) -> DNSCrypt encrypts, authenticates, and annonymizes dns requests being sent out of the server and back

## Unbound + Dnscrypt-Proxy?
* DNSSEC/Security: dnscrypt-proxy enforces dnssec/encrypts dns requests and is what communicates with the outside world. Unbound also enforces DNSSEC but since it forwards requests to dnscrypt-proxy, what unbound does here doesn't really matter (dnscrypt-proxy enforces DNSSEC too btw)
* Privacy: thanks to anonymous relays, dnscrypt-proxy hides your IP so all outgoing dns requests aren't traced back to you. Once again, unbound doesn't really help here and has no equivalent function at the time of me writing this
* You may want unbound for other reasons and so I made this optional
* Bascially, the addition of anonymized relays negates the need for unbound

## How to Install
* ssh into your server as root
* Place all of the files in this repo in your vps server
* `chmod +x VPS_Setup.bash `
* `bash VPS_Setup.bash`
  * Follow script instructions - will require several reboots
* Setup your lists in pi-hole

## Updating
* You may need to force specify the unstable branch for wireguard and dnscrypt-proxy. For example: apt install -t unstable dnscrypt-proxy
* Whenever you update dnscrypt proxy, you'll need to reapply the [sockets patch](https://github.com/Zackptg5/Wireguard-Pi-Hole-Cloudflared-Unbound-DNSCrypt-VPN-Server/blob/master/VPS_Setup.bash#L135) 
* After updating pihole, run the Pihole_After_Update script to reapply patches

## To Add More Wireguard Peers After Initial Setup
* ssh into your server as root
* Edit the user configurable variables in the Wireguard_After script
* `chmod +x Wireguard_After.bash `
* `bash Wireguard_After.bash`

## Further SSH Configuration
* You can (and should) switch to using a key rather than a password. To do this, you will need to run this from your computer (not your server!)
  ```
  ssh-keygen -t rsa -b 4096
  ssh-copy-id root@$ipaddr -p $sshport #The variables here are taken from the VPS_Setup Script
  ```
* Then on your server you just set up:
  ```
  sed -ri -e 's/^#PasswordAuthentication .*|^PasswordAuthentication yes/PasswordAuthentication no/' -e 's/^#UsePAM .*|^UsePAM yes/UsePAM no/' /etc/ssh/sshd_config
  echo "AuthenticationMethods publickey" >> /etc/ssh/sshd_config
  service sshd restart
  ```
* Note that this is all with openssh. If you wish to use putty, you'll need to convert the key with puttygen or winscp
* [See more tips for security here](https://github.com/BetterWayElectronics/secure-wireguard-implementation)

## Other Notes
* To see used ports: `lsof -i -P -n`
* A QR Code for each profile will be outputted during setup. You can take a picture of it with the device you want to use from the wireguard app
* The unbound config (pi-hole.conf) is pretty solid I think. Only thing you may want to change is some performance related variables like num-threads. Also note that enabling `auto-trust-anchor-file` prevented unbound service from starting regardless of forwarding or lack there of on my server. 
* dnscrypt config (dnscrypt-proxy.toml) is set to use only dnscrypt servers with dnssec, no logging or filtering, and then annonymizes them. [See here for more details.](https://github.com/DNSCrypt/dnscrypt-proxy/wiki/Anonymized-DNS) Note that I was able to wildcard it because the anon relays either didn't have a corresponding public server at the time of writing this or do filtering of some kind and so their servers aren't used (such as cryptostorm). This was a big plus for me because dnscrypt automatically sorts and picks the one with the lowest latency. Feel free to enable DOH or customize these however you want. DOH will require some extra setup though
* I have ipv6 enabled

## Sources I Found Helpful Setting This All Up
* [zzzkeil - Wireguard DNSCrypt Server Setup](https://github.com/zzzkeil/Wireguard-DNScrypt-VPN-Server)
* [notasausage - Pi-hole Unbound Wireguard Setup](https://github.com/notasausage/pi-hole-unbound-wireguard)
* [Unofficial Wireguard Docs](https://github.com/pirate/wireguard-docs)
* [Pi-Hole Unbound Docs](https://docs.pi-hole.net/guides/unbound)
* [SSH Key Pairing on Debian](https://devconnected.com/how-to-set-up-ssh-keys-on-debian-10-buster)
* [Unbound DNS Guide](https://calomel.org/unbound_dns.html)
* [Sample Unbound Config](https://gist.github.com/MatthewVance/5051bf45cfed6e4a2a2ed9bb014bcd72)
* [Unbound Config Docs](https://nlnetlabs.nl/documentation/unbound/unbound.conf)
* [Pi-Hole DNSCrypt 2 Docs](https://github.com/pi-hole/pi-hole/wiki/DNSCrypt-2.0)
* [Anonymized DNS Docs](https://github.com/DNSCrypt/dnscrypt-proxy/wiki/Anonymized-DNS)
* [Commonly Whitelisted Domains](https://discourse.pi-hole.net/t/commonly-whitelisted-domains/212)
* [More Commonly Whitelisted Domains](https://github.com/anudeepND/whitelist)
* [DNS Leak Test](https://dnsleaktest.com)
* [IP Leak Test](https://ipleak.net)
* [See @jedisct1 comment for my reasoning behind unbound/dnscrypt-proxy setup for security/privacy](https://www.reddit.com/r/privacytoolsIO/comments/98ggn4/unbound_recursive_or_dnscrypt/e4h5sre?utm_source=share&utm_medium=web2x&context=3)
