#!/bin/bash
if [[ $EUID -ne 0 ]]; then
  echo "This script must be run as root" 
  exit 1
fi

# Disable pihole cache, redundant and seems to slow things down
sed -i "s/cache-size=.*/cache-size=0/g" /etc/dnsmasq.d/01-pihole.conf
sed -i "s/CACHE_SIZE=.*/CACHE_SIZE=0/" /etc/pihole/setupVars.conf
# Add link to searx search from main page and add custom domain name as redirect for main page
if [ "$searx" ]; then
  if [ "$custdomain" ]; then
    sed -i "/admin panel?/a\            <a href='http://$custdomain:4004'></br>Or did you mean to go to Searx?</a>" /var/www/html/pihole/index.php
  else
    sed -i "/admin panel?/a\            <a href='http://$intipaddr.1:4004'></br>Or did you mean to go to Searx?</a>" /var/www/html/pihole/index.php
  fi
fi
if [ "$custdomain" ]; then
  sed -i "s/elseif (filter_var(\$serverName/elseif (\$serverName === \"$custdomain\" || filter_var(\$serverName/" /var/www/html/pihole/index.php
fi
