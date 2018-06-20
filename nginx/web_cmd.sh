#!/usr/bin/env bash

# initialize the letsencrypt.sh environment
setup_letsencrypt() {

  # create the directory that will serve ACME challenges
  mkdir -p .well-known/acme-challenge
  chmod -R 755 .well-known

  # See https://github.com/lukas2511/letsencrypt.sh/blob/master/docs/domains_txt.md
  echo "$DOMAIN www.$DOMAIN" > domains.txt

  # See https://github.com/lukas2511/letsencrypt.sh/blob/master/docs/staging.md
  echo "CA=\"https://acme-staging.api.letsencrypt.org/directory\"" > config.sh

  # See https://github.com/lukas2511/letsencrypt.sh/blob/master/docs/wellknown.md
  echo "WELLKNOWN=\"$WEB_ROOT/.well-known/acme-challenge\"" >> config.sh

  # fetch stable version of letsencrypt.sh
  curl "https://raw.githubusercontent.com/lukas2511/letsencrypt.sh/v0.2.0/letsencrypt.sh" > letsencrypt.sh
  chmod 755 letsencrypt.sh
}

# creates self-signed SSL files
# these files are used in development and get production up and running so letsencrypt.sh can do its work
create_pems() {
  openssl req \
      -x509 \
      -nodes \
      -newkey rsa:1024 \
      -keyout privkey.pem \
      -out $SSL_CERT_HOME/fullchain.pem \
      -days 3650 \
      -sha256 \
      -config <(cat <<EOF
[ req ]
prompt = no
distinguished_name = subject
x509_extensions    = x509_ext
 
[ subject ]
commonName = $DOMAIN
 
[ x509_ext ]
subjectAltName = @alternate_names
 
[ alternate_names ]
DNS.1 = localhost
IP.1 = 127.0.0.1
EOF
)
 
  openssl dhparam -out dhparam.pem 2048
  chmod 600 *.pem
}

# if we have not already done so initialize Docker volume to hold SSL files
if [ ! -d "$SSL_CERT_HOME" ]; then
  mkdir -p $SSL_CERT_HOME # _HOME
  chmod 755 $SSL_ROOT
  chmod -R 700 $SSL_ROOT/certs
  cd $SSL_CERT_HOME
  create_pems
  cd $SSL_ROOT
  setup_letsencrypt
fi

# if we are configured to run SSL with a real certificate authority run letsencrypt.sh to retrieve/renew SSL certs
if [ "$CA_SSL" = "true" ]; then

  # Nginx must be running for challenges to proceed
  # run in daemon mode so our script can continue
  nginx

  # retrieve/renew SSL certs
  ./letsencrypt.sh --cron

  # copy the fresh certs to where Nginx expects to find them
  cp $SSL_ROOT/certs/$DOMAIN/fullchain.pem $SSL_ROOT/certs/$DOMAIN/privkey.pem $SSL_CERT_HOME

  # pull Nginx out of daemon mode
  nginx -s stop
fi

# start Nginx in foreground so Docker container doesn't exit
nginx -g "daemon off;"