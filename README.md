# nginx-rtmp-docker

Lightweight nginx + RTMP module for replicating live streams, with optional multi-bitrate HLS transcoding.

Docker Hub: [codingtom/nginx-rtmp-docker](https://hub.docker.com/r/codingtom/nginx-rtmp-docker)

## Tags

| Tag | What it is |
|---|---|
| `latest` | No-transcode / passthrough (default, low CPU) |
| `transcode` | Re-encodes source into multiple HLS bitrates (CPU-heavy) |
| `YYYY-MM-DD-no-transcode` | Immutable snapshot of the passthrough build |
| `YYYY-MM-DD-transcode` | Immutable snapshot of the transcoding build |
| `archive-latest`, `archive-no-transcode` | Pre-2026 builds preserved for rollback |

## Run

```sh
docker run -d \
  -p 1935:1935 \
  -p 8027:8027 \
  --name rtmp \
  codingtom/nginx-rtmp-docker:latest
```

- `1935/tcp` — RTMP ingest (push here from OBS)
- `8027/tcp` — HLS output + RTMP stat endpoint (`/stat`)

## Stream to it

In OBS: **Settings → Stream → Service: Custom → Server: `rtmp://<host>:1935/live` → Stream Key: anything**.

### Passthrough variant (`:latest`)

HLS is generated directly in the `live` application, so:

- HLS playlist: `http://<host>:8027/live/<stream_key>.m3u8`
- HLS segments: `http://<host>:8027/live/<stream_key>-N.ts`
- Raw RTMP: `rtmp://<host>:1935/live/<stream_key>`

### Transcode variant (`:transcode`)

An ffmpeg inside the container re-encodes the incoming stream into multiple HLS bitrates and pushes each to a second RTMP application, which writes HLS with a master playlist:

- Master HLS playlist: `http://<host>:8027/live/<stream_key>.m3u8` (references the variants)
- Variant playlist: `http://<host>:8027/live/<stream_key>_src.m3u8`, `..._720p.m3u8`, etc.
- Raw RTMP passthrough: `rtmp://<host>:1935/hls/<stream_key>_src`

## Build locally

```sh
# Passthrough (default)
docker build -t nginx-rtmp:latest .

# Transcoding variant
docker build --build-arg TRANSCODE=true -t nginx-rtmp:transcode .
```

The `TRANSCODE` build arg picks which `nginx.conf` gets baked in:
- `TRANSCODE=false` → `nginx/nginx.conf` (passthrough)
- `TRANSCODE=true`  → `nginx/nginx.transcode.conf` (multi-bitrate HLS)

## Publish

`scripts/publish.sh` builds both variants, pushes to Docker Hub, adds a dated tag for reproducibility, and preserves previous remote tags under `archive-*` names on first run. See the script for env-var knobs.

```sh
./scripts/publish.sh          # build + push with today's date
PUSH=0 ./scripts/publish.sh   # build locally only
PLATFORMS=linux/amd64,linux/arm64 ./scripts/publish.sh   # multi-arch
```

## How it works

Built on Alpine 3.20 using the packaged `nginx`, `nginx-mod-rtmp` (arut's module), and `ffmpeg`. Much smaller + faster to rebuild than the previous from-source stack, and picks up Alpine security updates on every rebuild.

- Logs go to docker via `/var/log/nginx/{access,error}.log` → `/dev/stdout`/`stderr`.
- HLS segments live under `/appdata/nginx/hls` — mount a tmpfs there for best performance:
  `-mount type=tmpfs,destination=/appdata`.
- `/stat` and `/static/stat.xsl` render the RTMP stat page.

## History

Originally forked from [DvdGiessen/nginx-rtmp-docker](https://github.com/DvdGiessen/nginx-rtmp-docker) (itself a fork of older Alpine-nginx-rtmp images). The 2020 "Hecklevision kit" added multi-bitrate HLS + the stat endpoint. In 2021 a separate `no-transcode` branch was cut for passthrough-only use on small hosts. In 2026 the two branches were consolidated into this one, the base image modernized to Alpine 3.20, and the from-source nginx/ffmpeg build replaced with packaged binaries.
