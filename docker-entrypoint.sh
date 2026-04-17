#!/bin/sh
# Renders /etc/nginx/templates/nginx.conf.template into /etc/nginx/nginx.conf
# via envsubst with an explicit variable allowlist, then runs nginx.
#
# Runtime env vars (defaults come from the Dockerfile + variant logic below):
#   HTTP_PORT              HTTP listen port (default 8080)
#   RTMP_PORT              RTMP listen port (default 1935)
#   HLS_FRAGMENT           hls_fragment directive (default: 1s passthrough / 500ms transcode)
#   HLS_PLAYLIST_LENGTH    hls_playlist_length (default: 4s passthrough / 20s transcode)
#   HLS_SYNC               hls_sync (default 100ms)
#
# Only the names listed in $VARS below are substituted; every other `$foo`
# in the template (nginx's own variables like $remote_addr, $name) is
# preserved verbatim. Passing an empty allowlist to envsubst would substitute
# *everything* — hence the explicit list.
#
# Special flag:
#   --render-only    Render the config and exit 0. Used by the Dockerfile
#                    build step to smoke-test the template.

set -e

# Variant-specific defaults for the HLS timing knobs. TRANSCODE is baked in
# at build time by the Dockerfile (ENV TRANSCODE=...).
if [ "${TRANSCODE}" = "true" ]; then
    : "${HLS_FRAGMENT:=500ms}"
    : "${HLS_PLAYLIST_LENGTH:=20s}"
else
    : "${HLS_FRAGMENT:=1s}"
    : "${HLS_PLAYLIST_LENGTH:=4s}"
fi
export HLS_FRAGMENT HLS_PLAYLIST_LENGTH

VARS='${HTTP_PORT} ${RTMP_PORT} ${HLS_FRAGMENT} ${HLS_PLAYLIST_LENGTH} ${HLS_SYNC}'

echo "[entrypoint] rendering nginx.conf with:"
echo "[entrypoint]   TRANSCODE=${TRANSCODE}  HTTP_PORT=${HTTP_PORT}  RTMP_PORT=${RTMP_PORT}"
echo "[entrypoint]   HLS_FRAGMENT=${HLS_FRAGMENT}  HLS_PLAYLIST_LENGTH=${HLS_PLAYLIST_LENGTH}  HLS_SYNC=${HLS_SYNC}"

envsubst "$VARS" \
    < /etc/nginx/templates/nginx.conf.template \
    > /etc/nginx/nginx.conf
chmod 444 /etc/nginx/nginx.conf

if [ "${1:-}" = "--render-only" ]; then
    exit 0
fi

# HLS + friends live in /appdata; the compose file mounts a tmpfs here.
mkdir -p /appdata/nginx/client-body /appdata/nginx/dash /appdata/nginx/hls
chown -R nginx:nginx /appdata/nginx
chmod -R 777 /appdata/nginx

if [ $# -ne 0 ]; then
    exec "$@"
else
    echo "[entrypoint] starting nginx"
    exec nginx -g "daemon off;"
fi
