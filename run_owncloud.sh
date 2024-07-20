#!/bin/bash
set -ex

# environment
# place docker compose file
rootPath=$HOME/owncloudServer
ossBucket=$AliyunOssBucket
# bucket mount path
bucketMountPath="$HOME/oss/$ossBucket"
# data path in oss
OwncloudFilePath="$bucketMountPath/owncloud/files"
MysqlPath="$bucketMountPath/owncloud/mariadb"
RedisPath="$bucketMountPath/owncloud/redis"
NginxPath="$bucketMountPath/owncloud/ssl"

if ! (findmnt "$bucketMountPath"); then
	echo "$bucketMountPath" is not mount point && exit 1
fi

# custom env
NGINX_HTTPS_PORT=${HTTPS_PORT}
NGINX_IP=${HTTPS_HOST}
OWNCLOUD_ADMIN_USERNAME=${OWNCLOUD_ADMIN_USERNAME}
OWNCLOUD_ADMIN_PASSWORD=${OWNCLOUD_ADMIN_PASSWORD}

if [ -z "$NGINX_HTTPS_PORT" -o -z "$NGINX_IP" -o -z "$OWNCLOUD_ADMIN_USERNAME" -o -z "$OWNCLOUD_ADMIN_PASSWORD" ]; then
  echo "must specify all environment AliyunOssBucket HTTPS_PORT HTTPS_HOST OWNCLOUD_ADMIN_USERNAME OWNCLOUD_ADMIN_PASSWORD"
  exit 1
fi

mkdir -p $rootPath
cd $rootPath
mkdir -p $OwncloudFilePath $MysqlPath $RedisPath $NginxPath
chmod 777 $OwncloudFilePath $MysqlPath $RedisPath $NginxPath

NginxCertPath="$NginxPath/certs"
NginxConfPath="$NginxPath/conf"

# create ssl certs
if [ ! -d "$NginxCertPath" ]; then
	mkdir -p "$NginxCertPath"
	pushd $NginxCertPath
	openssl genpkey -algorithm RSA -out ca_key.pem -pkeyopt rsa_keygen_bits:4096
	openssl req -x509 -new -nodes -key ca_key.pem -sha256 -days 3650 -out ca_cert.pem -subj "/C=CN"
	openssl genpkey -algorithm RSA -out server_key.pem -pkeyopt rsa_keygen_bits:2048
	openssl req -new -key server_key.pem -out server_csr.pem -subj "/C=CN"
	openssl x509 -req -in server_csr.pem -CA ca_cert.pem -CAkey ca_key.pem -CAcreateserial -out server_cert.pem -days 1825 -sha256
	rm server_csr.pem
	popd
fi

# nginx conf
function createOrUpdateNginxConf() {
  mkdir -p "$NginxConfPath"
	cat << EOF > "$NginxConfPath/owncloud_https.conf"
server {
    listen $NGINX_HTTPS_PORT ssl default_server;

    ssl_certificate     /etc/nginx/ssl/server_cert.pem;
    ssl_certificate_key /etc/nginx/ssl/server_key.pem;
    ssl_protocols       TLSv1 TLSv1.1 TLSv1.2;
    ssl_ciphers         HIGH:!aNULL:!MD5;

    client_max_body_size 0;

    location / {
        proxy_set_header   Host             \$host:$NGINX_HTTPS_PORT;
        proxy_redirect     http://          https://;
        proxy_pass         http://owncloud:8080/;
    }
}
EOF
}

createOrUpdateNginxConf

# env
cat << EOF > .env
OWNCLOUD_VERSION=10.14
OWNCLOUD_DOMAIN=localhost:8080
OWNCLOUD_TRUSTED_DOMAINS="localhost, owncloud, 127.0.0.1, $NGINX_IP"
ADMIN_USERNAME=${OWNCLOUD_ADMIN_USERNAME}
ADMIN_PASSWORD=${OWNCLOUD_ADMIN_PASSWORD}
HTTPS_PORT=${NGINX_HTTPS_PORT}
# custom env
OWNCLOUD_DATA="$OwncloudFilePath"
MYSQL_DATA="$MysqlPath"
REDIS_DATA="$RedisPath"
NGINX_SSL="$NginxCertPath"
NGINX_CONF="$NginxConfPath"
EOF

# docker compose

cat << 'EOF' > docker-compose.yml
version: "3"
volumes:
  ssl:
    driver: local
    driver_opts:
      type: none
      o: bind,ro
      device: ${NGINX_SSL}
  server:
    driver: local
    driver_opts:
      type: none
      o: bind
      device: ${NGINX_CONF}
  files:
    driver: local
    driver_opts:
      type: none
      o: bind
      device: ${OWNCLOUD_DATA}
  mysql:
    driver: local
    driver_opts:
      type: none
      o: bind
      device: ${MYSQL_DATA}
  redis:
    driver: local
    driver_opts:
      type: none
      o: bind
      device: ${REDIS_DATA}

networks:
  owncloud_network:
    name: owncloud_network
    driver: bridge

services:
  nginx:
    image: nginx
    container_name: nginx_server
    restart: always
    ports:
      - ${HTTPS_PORT}:${HTTPS_PORT}
    depends_on:
      - owncloud
    healthcheck:
      test: ["CMD", "curl", "-k", "http://localhost:${HTTPS_PORT}"]
      interval: 30s
      timeout: 10s
      retries: 5
    volumes:
      - ssl:/etc/nginx/ssl
      - server:/etc/nginx/conf.d
    networks:
      - owncloud_network
  owncloud:
    image: owncloud/server:${OWNCLOUD_VERSION}
    container_name: owncloud_server
    restart: always
#    ports:
#      - 8080:8080
    depends_on:
      - mariadb
      - redis
    environment:
      - OWNCLOUD_DOMAIN=${OWNCLOUD_DOMAIN}
      - OWNCLOUD_TRUSTED_DOMAINS=${OWNCLOUD_TRUSTED_DOMAINS}
      - OWNCLOUD_DB_TYPE=mysql
      - OWNCLOUD_DB_NAME=owncloud
      - OWNCLOUD_DB_USERNAME=owncloud
      - OWNCLOUD_DB_PASSWORD=owncloud
      - OWNCLOUD_DB_HOST=mariadb
      - OWNCLOUD_ADMIN_USERNAME=${ADMIN_USERNAME}
      - OWNCLOUD_ADMIN_PASSWORD=${ADMIN_PASSWORD}
      - OWNCLOUD_MYSQL_UTF8MB4=true
      - OWNCLOUD_REDIS_ENABLED=true
      - OWNCLOUD_REDIS_HOST=redis
    healthcheck:
      test: ["CMD", "/usr/bin/healthcheck"]
      interval: 30s
      timeout: 10s
      retries: 50
    volumes:
      - files:/mnt/data
    networks:
      - owncloud_network
  mariadb:
    image: mariadb:10.11 # minimum required ownCloud version is 10.9
    container_name: owncloud_mariadb
    restart: always
    environment:
      - MYSQL_ROOT_PASSWORD=owncloud
      - MYSQL_USER=owncloud
      - MYSQL_PASSWORD=owncloud
      - MYSQL_DATABASE=owncloud
      - MARIADB_AUTO_UPGRADE=1
    command: ["--max-allowed-packet=128M", "--innodb-log-file-size=64M"]
    healthcheck:
      test: ["CMD", "mysqladmin", "ping", "-u", "root", "--password=owncloud"]
      interval: 10s
      timeout: 5s
      retries: 50
    volumes:
      - mysql:/var/lib/mysql
    networks:
      - owncloud_network
  redis:
    image: redis:6
    container_name: owncloud_redis
    restart: always
    command: ["--databases", "1"]
    healthcheck:
      test: ["CMD", "redis-cli", "ping"]
      interval: 10s
      timeout: 5s
      retries: 5
    volumes:
      - redis:/data
    networks:
      - owncloud_network
EOF
docker compose up -d