# Dockerfile for a simple Nginx stream replicator

# Software versions to build
ARG ALPINE_VERSION=alpine:3.8
ARG FFMPEG_VERSION=4.2.2
ARG NGINX_VERSION=1.16.1
ARG NGINX_RTMP_MODULE_VERSION=741e0af3cea9b17e2c5f6a2c40920dceb758ae5e
ARG PCRE_VERSION=8.44

# Build stage for nginx
FROM ${ALPINE_VERSION} as build-nginx
ARG NGINX_VERSION
ARG NGINX_RTMP_MODULE_VERSION
ARG PCRE_VERSION

# Install buildtime dependencies
# Note: We build against LibreSSL instead of OpenSSL, because LibreSSL is already included in Alpine
RUN apk update && \
    apk --no-cache add \
    build-base \
    libressl-dev

# Download sources
# Note: We download our own fork of nginx-rtmp-module which contains some additional enhancements over the original version by arut
RUN mkdir -p /build && \
    wget -O - https://nginx.org/download/nginx-${NGINX_VERSION}.tar.gz | tar -zxC /build -f - && \
    mv /build/nginx-${NGINX_VERSION} /build/nginx && \
    wget -O - https://github.com/DvdGiessen/nginx-rtmp-module/archive/${NGINX_RTMP_MODULE_VERSION}.tar.gz | tar -zxC /build -f - && \
    mv /build/nginx-rtmp-module-${NGINX_RTMP_MODULE_VERSION} /build/nginx-rtmp-module && \
    wget -O - https://ftp.pcre.org/pub/pcre/pcre-${PCRE_VERSION}.tar.gz | tar -zxC /build -f - && \
    mv /build/pcre-${PCRE_VERSION} /build/pcre

# Build a minimal version of nginx
RUN cd /build/nginx && \
    ./configure \
    --build=codingtom/nginx-rtmp-docker \
    --prefix=/etc/nginx \
    --with-cc-opt="-static -static-libgcc" \
    --sbin-path=/usr/local/sbin/nginx \
    --conf-path=/etc/nginx/nginx.conf \
    --error-log-path=/var/log/nginx/error.log \
    --http-log-path=/var/log/nginx/access.log \
    --pid-path=/var/run/nginx.pid \
    --lock-path=/var/lock/nginx.lock \
    --http-client-body-temp-path=/appdata/nginx/client-body \
    --user=nginx \
    --group=nginx \
    --without-http-cache \
    --without-http_access_module \
    --without-http_auth_basic_module \
    --without-http_autoindex_module \
    --without-http_browser_module \
    --without-http_charset_module \
    --without-http_empty_gif_module \
    --without-http_fastcgi_module \
    --without-http_geo_module \
    --without-http_grpc_module \
    --without-http_gzip_module \
    --without-http_limit_conn_module \
    --without-http_limit_req_module \
    --without-http_map_module \
    --without-http_memcached_module \
    --without-http_mirror_module \
    --without-http_proxy_module \
    --without-http_referer_module \
    --without-http_scgi_module \
    --without-http_split_clients_module \
    --without-http_ssi_module \
    --without-http_upstream_hash_module \
    --without-http_upstream_ip_hash_module \
    --without-http_upstream_keepalive_module \
    --without-http_upstream_least_conn_module \
    --without-http_upstream_random_module \
    --without-http_upstream_zone_module \
    --without-http_userid_module \
    --without-http_uwsgi_module \
    --without-mail_imap_module \
    --without-mail_pop3_module \
    --without-mail_smtp_module \
    --without-poll_module \
    --without-select_module \
    --without-stream_access_module \
    --without-stream_geo_module \
    --without-stream_limit_conn_module \
    --without-stream_map_module \
    --without-stream_return_module \
    --without-stream_split_clients_module \
    --without-stream_upstream_hash_module \
    --without-stream_upstream_least_conn_module \
    --without-stream_upstream_random_module \
    --without-stream_upstream_zone_module \
    --with-ipv6 \
    --with-pcre=../pcre \
    --with-threads \
    --with-debug \
    --add-module=/build/nginx-rtmp-module && \
    make -j $(getconf _NPROCESSORS_ONLN)

# Build stage for ffmpeg
FROM ${ALPINE_VERSION} as build-ffmpeg
ARG FFMPEG_VERSION

# FFmpeg build dependencies.
RUN apk update && \
    apk --no-cache add \
    build-base \
    coreutils \
    freetype-dev \
    lame-dev \
    libogg-dev \
    libass \
    libass-dev \
    libvpx-dev \
    libvorbis-dev \
    libwebp-dev \
    libtheora-dev \
    openssl-dev \
    opus-dev \
    pkgconf \
    pkgconfig \
    rtmpdump-dev \
    wget \
    x264-dev \
    x265-dev \
    yasm

RUN echo http://dl-cdn.alpinelinux.org/alpine/edge/community >> /etc/apk/repositories
RUN apk add --update fdk-aac-dev

RUN mkdir -p /build && \
    wget -O - http://ffmpeg.org/releases/ffmpeg-${FFMPEG_VERSION}.tar.gz | tar -zxC /build -f - && \
    mv /build/ffmpeg-${FFMPEG_VERSION} /build/ffmpeg

RUN cd /build/ffmpeg && \
    ./configure \
    --prefix=/usr/local \
    --enable-version3 \
    --enable-gpl \
    --enable-nonfree \
    --enable-small \
    --enable-libmp3lame \
    --enable-libx264 \
    --enable-libx265 \
    --enable-libvpx \
    --enable-libtheora \
    --enable-libvorbis \
    --enable-libopus \
    --enable-libfdk-aac \
    --enable-libass \
    --enable-libwebp \
    --enable-postproc \
    --enable-avresample \
    --enable-libfreetype \
    --enable-openssl \
    --disable-debug \
    --disable-doc \
    --disable-ffplay \
    --extra-libs="-lpthread -lm" && \
    make -j $(getconf _NPROCESSORS_ONLN) && \
    make install && \
    make distclean

# Cleanup.
RUN rm -rf /var/cache/* /build/*

# Final image stage
FROM ${ALPINE_VERSION}

# Set up group and user
RUN addgroup -S nginx && \
    adduser -s /sbin/nologin -G nginx -S -D -H nginx

# Set up directories
RUN mkdir -p /etc/nginx /var/log/nginx /var/www && \
    chown -R nginx:nginx /var/log/nginx /var/www && \
    chmod -R 775 /var/log/nginx /var/www

# Forward logs to Docker
RUN ln -sf /dev/stdout /var/log/nginx/access.log && \
    ln -sf /dev/stderr /var/log/nginx/error.log

ADD static /static
RUN chown -R nginx:nginx /static && \
    chmod -R 775 /static

# Set up exposed ports
EXPOSE 1935/tcp
EXPOSE 1935/udp
EXPOSE 8027

# Set up entrypoint
COPY docker-entrypoint.sh /docker-entrypoint.sh
RUN chmod 555 /docker-entrypoint.sh
ENTRYPOINT ["/docker-entrypoint.sh"]
CMD []

# Copy files from build stages
COPY --from=build-nginx /build/nginx/objs/nginx /usr/local/sbin/nginx
RUN chmod 550 /usr/local/sbin/nginx

COPY --from=build-ffmpeg /usr/local /usr/local
COPY --from=build-ffmpeg /lib /lib
COPY --from=build-ffmpeg /usr/lib /usr/lib

# Set up config file
ADD nginx /etc/nginx
RUN chmod -R 444 /etc/nginx
