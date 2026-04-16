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
# For the full multi-tag publish pipeline see scripts/publish.sh.

ARG ALPINE_VERSION=3.20

FROM alpine:${ALPINE_VERSION}

ARG TRANSCODE=false

# Packaged nginx 1.26.x + arut's rtmp module + ffmpeg 6.x + tini as PID 1.
RUN apk add --no-cache \
      nginx \
      nginx-mod-rtmp \
      ffmpeg \
      tini \
      tzdata

# The nginx package creates the `nginx` user/group. Prepare runtime dirs.
RUN mkdir -p /var/log/nginx /var/www /appdata/nginx/hls && \
    chown -R nginx:nginx /var/log/nginx /var/www /appdata && \
    chmod -R 775 /var/log/nginx /var/www

# Forward logs to docker's log driver.
RUN ln -sf /dev/stdout /var/log/nginx/access.log && \
    ln -sf /dev/stderr /var/log/nginx/error.log

# Static assets (RTMP stat stylesheet).
COPY static /static
RUN chown -R nginx:nginx /static && chmod -R 775 /static

# nginx configuration — pick passthrough or transcode variant at build time.
COPY nginx/mime.types /etc/nginx/mime.types
COPY nginx/nginx.conf /tmp/nginx.conf.default
COPY nginx/nginx.transcode.conf /tmp/nginx.conf.transcode
RUN if [ "$TRANSCODE" = "true" ]; then \
        cp /tmp/nginx.conf.transcode /etc/nginx/nginx.conf; \
    else \
        cp /tmp/nginx.conf.default /etc/nginx/nginx.conf; \
    fi && \
    rm -f /tmp/nginx.conf.default /tmp/nginx.conf.transcode && \
    chmod 444 /etc/nginx/nginx.conf /etc/nginx/mime.types

# Record which variant was baked in, for debugging.
LABEL org.hecklevision.transcode="${TRANSCODE}"

EXPOSE 1935/tcp
EXPOSE 8027/tcp

# Quick sanity: fail the build if nginx can't parse the config we just baked.
RUN nginx -t

COPY docker-entrypoint.sh /docker-entrypoint.sh
RUN chmod 555 /docker-entrypoint.sh

# tini reaps ffmpeg children cleanly if they're spawned by exec_push.
ENTRYPOINT ["/sbin/tini", "--", "/docker-entrypoint.sh"]
CMD []
