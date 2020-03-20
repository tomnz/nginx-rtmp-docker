#!/bin/sh
set -e

mkdir -p /appdata/nginx/client-body /appdata/nginx/dash /appdata/nginx/hls
chown -R nginx:nginx /appdata/nginx
chmod -R 777 /appdata/nginx

if [ $# -ne 0 ]; then
    exec "$@"
else
    echo "Running nginx!"
    exec nginx -g "daemon off;"
fi
