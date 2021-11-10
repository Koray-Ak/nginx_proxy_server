#!/bin/bash

if ! [ -x "$(command -v docker-compose)" ]; then
  echo 'Error: docker-compose is not installed.' >&2
  exit 1
fi

data_path="/var/lib/docker/volumes/letsencrypt/_data"
www_path="/var/lib/docker/volumes/www/_data"
nginx_path="/var/lib/docker/volumes/nginx/_data/conf.d"
logs_path="/var/lib/docker/volumes/logs/_data"

docker volume create nginx
docker volume create letsencrypt
docker volume create logs
docker volume create www

echo "Docker volumes has been created"

docker-compose -f docker-compose.yml up -d

sed -i -e "s|/usr/share/nginx/html|/var/www/html|g" $nginx_path/default.conf

echo -e "<!DOCTYPE html>\n" \
"<html lang="de">\n" \
"  <head>\n" \
"    <meta charset="utf-8">\n" \
"    <meta name="viewport" content="width=device-width, initial-scale=1.0">\n" \
"    <title>Proxy</title>\n" \
"  </head>\n" \
"  <body>\n" \
"    Hier ist der Proxy von kvwmap-server\n" \
"  </body>\n" \
"</html>"> $www_path/index.html

docker-compose -f docker-compose.yml down

read -p "Enter Domain Name: " domains

staging=1 # Set to 1 if you're testing your setup to avoid hitting request limits

if [ -d "$data_path" ]; then
  read -p "Existing data found for $domains. Continue and replace existing certificate? (y/N) " decision
  if [ "$decision" != "Y" ] && [ "$decision" != "y" ]; then
    exit
  fi
fi


if [ ! -e "$data_path/options-ssl-nginx.conf" ] || [ ! -e "$data_path/ssl-dhparams.pem" ]; then
  echo "### Downloading recommended TLS parameters ..."
  curl -s https://raw.githubusercontent.com/certbot/certbot/master/certbot-nginx/certbot_nginx/_internal/tls_configs/options-ssl-nginx.conf > "$data_path/options-ssl-nginx.conf"
  curl -s https://raw.githubusercontent.com/certbot/certbot/master/certbot/certbot/ssl-dhparams.pem > "$data_path/ssl-dhparams.pem"
  echo
fi

echo "### Starting nginx ..."
 docker-compose up -d
echo

echo "### Requesting Let's Encrypt certificate for $domains ..."
#Join $domains to -d args
domain_args=""
for domain in "${domains[@]}"; do
  domain_args="$domain_args -d $domain"
done

# Enable staging mode if needed
if [ $staging != "0" ]; then staging_arg="--staging"; fi

docker run --rm --interactive --name certbot \
    -v "$www_path:/var/www/html" \
    -v "$data_path:/etc/letsencrypt" \
    -v "$logs_path:/var/log/nginx" \
certbot/certbot certonly --webroot -w /var/www/html $domain_args $staging_arg

echo -e "server {\n" \
"listen 443 ssl;\n" \
"server_name $domains;\n" \
"\n" \
"root /var/www/html;\n" \
"\n" \
"ssl_certificate /etc/letsencrypt/live/$domains/fullchain.pem;\n" \
"ssl_certificate_key /etc/letsencrypt/live/$domains/privkey.pem;\n" \
"\n" \
"include /etc/letsencrypt/options-ssl-nginx.conf;\n" \
"ssl_dhparam /etc/letsencrypt/ssl-dhparams.pem;\n" \
"\n" \
"location / {\n" \
"proxy_pass http://proxy_nginx_1;\n" \
"}\n}\n"> $nginx_path/default-ssl.conf

echo "### Reloading nginx ..."
docker-compose exec nginx nginx -s reload
