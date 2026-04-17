# syntax=docker/dockerfile:1.7
#
# Package-based build on Alpine. Uses upstream `nginx` + `nginx-mod-rtmp`
# (arut's module) + `ffmpeg` from Alpine's stable repo. Rebuilding this
# image automatically picks up Alpine security updates.
#
# Build arg TRANSCODE selects the nginx.conf variant:
#   TRANSCODE=false (default) → passthrough, lowest CPU
#   TRANSCODE=true            → multi-bitrate HLS transcode (requires headroom)
#
# Example local build:
#   docker build -t nginx-rtmp:latest .                          # default: no-transcode
#   docker build --build-arg TRANSCODE=true -t nginx-rtmp:transcode .
#
# Runtime env vars (see README for the full table):
#   HTTP_PORT, RTMP_PORT, HLS_FRAGMENT, HLS_PLAYLIST_LENGTH, HLS_SYNC
#
# For the full multi-tag publish pipeline see scripts/publish.sh.

ARG ALPINE_VERSION=3.20

FROM alpine:${ALPINE_VERSION}

ARG TRANSCODE=false

# Packaged nginx 1.26.x + arut's rtmp module + ffmpeg 6.x + tini as PID 1.
# gettext provides envsubst, used by the entrypoint to render nginx.conf
# from its template with runtime env vars.
RUN apk add --no-cache \
      nginx \
      nginx-mod-rtmp \
      ffmpeg \
      gettext \
      tini \
      tzdata

# The nginx package creates the `nginx` user/group. Prepare runtime dirs.
RUN mkdir -p /var/log/nginx /var/www /appdata/nginx/hls /etc/nginx/templates && \
    chown -R nginx:nginx /var/log/nginx /var/www /appdata && \
    chmod -R 775 /var/log/nginx /var/www

# Forward logs to docker's log driver.
RUN ln -sf /dev/stdout /var/log/nginx/access.log && \
    ln -sf /dev/stderr /var/log/nginx/error.log

# Static assets (RTMP stat stylesheet).
COPY static /static
RUN chown -R nginx:nginx /static && chmod -R 775 /static

# nginx configuration — pick passthrough or transcode variant at build time.
# The chosen file is copied to /etc/nginx/templates/nginx.conf.template and
# rendered by the entrypoint at every container start via envsubst.
COPY nginx/mime.types /etc/nginx/mime.types
COPY nginx/nginx.conf /tmp/nginx.conf.default
COPY nginx/nginx.transcode.conf /tmp/nginx.conf.transcode
RUN if [ "$TRANSCODE" = "true" ]; then \
        cp /tmp/nginx.conf.transcode /etc/nginx/templates/nginx.conf.template; \
    else \
        cp /tmp/nginx.conf.default /etc/nginx/templates/nginx.conf.template; \
    fi && \
    rm -f /tmp/nginx.conf.default /tmp/nginx.conf.transcode && \
    chmod 444 /etc/nginx/mime.types /etc/nginx/templates/nginx.conf.template

# Runtime defaults. TRANSCODE is re-exported as ENV so the entrypoint can
# pick variant-appropriate defaults for HLS_FRAGMENT / HLS_PLAYLIST_LENGTH
# (transcode uses a longer playlist; passthrough goes for low latency).
# All of these can be overridden at `docker run` time via -e.
ENV TRANSCODE=${TRANSCODE} \
    HTTP_PORT=8080 \
    RTMP_PORT=1935 \
    HLS_SYNC=100ms

LABEL org.opencontainers.image.title="nginx-rtmp-docker" \
      org.opencontainers.image.source="https://github.com/tomnz/nginx-rtmp-docker" \
      io.nginx-rtmp.transcode="${TRANSCODE}"

EXPOSE 1935/tcp
EXPOSE 8080/tcp

COPY docker-entrypoint.sh /docker-entrypoint.sh
RUN chmod 555 /docker-entrypoint.sh

# Sanity check: render the template with default env vars and ensure nginx
# can parse it. Catches template syntax errors at build time rather than
# first container start.
RUN /docker-entrypoint.sh --render-only && nginx -t

# tini reaps ffmpeg children cleanly if they're spawned by exec_push.
ENTRYPOINT ["/sbin/tini", "--", "/docker-entrypoint.sh"]
CMD []
