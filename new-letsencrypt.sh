#/bin/bash

read -p "Enter the Domain Name: " domains
docker ps -a --format "{{.Names}}"
read -p "Enter the Container Name: " containername

staging=1 # Set to 1 if you're testing your setup to avoid hitting request limits

# Enable staging mode if needed
if [ $staging != "0" ]; then staging_arg="--staging"; fi

docker run --rm --interactive --name certbot \
    -v "www:/var/www/html" \
    -v "letsencrypt:/etc/letsencrypt" \
    -v "logs:/var/log/nginx" \
certbot/certbot certonly --webroot -w /var/www/html -d $domains $staging_arg

echo -e "server {\n" \
"listen 80;\n" \
"server_name $domains;\n" \
"\n" \
"root /var/www/html;\n" \
"\n" \
"location / {\n" \
"return 301 https://$host$request_uri;\n" \
"index  index.html index.htm;\n" \
"}\n" \
"\n" \
"location /.well-known/ {\n" \
"}\n" \
"\n" \
"error_page   500 502 503 504  /50x.html;\n" \
"location = /50x.html {\n" \
"\n" \
"root /usr/share/nginx/html;\n" \
"}\n" \
"\n" \
"}\n" \
"\n" \
"server {\n" \
"listen 443 ssl;\n" \
"listen [::]:443;\n" \
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
"proxy_pass http://$containername;\n" \
"}\n}\n"> /var/lib/docker/volumes/nginx/_data/conf.d/$domains.conf

