#!/usr/bin/env bash
# Build both variants and push to Docker Hub.
#
# Tag scheme (new, simplified):
#   latest       → no-transcode / passthrough (the common case)
#   transcode    → multi-bitrate HLS transcode
#   YYYY-MM-DD-no-transcode  (immutable dated tag per build)
#   YYYY-MM-DD-transcode     (immutable dated tag per build)
#
# Archive preservation (idempotent):
#   Before pushing the new `latest`, the old remote `latest` is re-tagged as
#   `archive-latest` (if not already archived). Similarly the old remote
#   `no-transcode` tag is re-tagged as `archive-no-transcode`. These let you
#   roll back to the 2020/2021 images if the new build has problems.
#
# Env vars:
#   IMAGE       Docker Hub repo (default: codingtom/nginx-rtmp-docker)
#   DATE_TAG    Date suffix (default: $(date +%Y-%m-%d))
#   PUSH        1 = push to Docker Hub (default). 0 = build locally only.
#   PLATFORMS   Buildx platforms (default: linux/amd64).
#                 Set to linux/amd64,linux/arm64 for multi-arch.
#   BUILDER     Name of buildx builder to use/create (default: nginx-rtmp-builder).
#   SKIP_ARCHIVE  1 = skip the archive step (default 0).

set -euo pipefail

IMAGE="${IMAGE:-codingtom/nginx-rtmp-docker}"
DATE_TAG="${DATE_TAG:-$(date +%Y-%m-%d)}"
PUSH="${PUSH:-1}"
PLATFORMS="${PLATFORMS:-linux/amd64}"
BUILDER="${BUILDER:-nginx-rtmp-builder}"
SKIP_ARCHIVE="${SKIP_ARCHIVE:-0}"

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

info()  { printf "\033[1;34m[info]\033[0m %s\n" "$*"; }
ok()    { printf "\033[1;32m[ ok ]\033[0m %s\n" "$*"; }
warn()  { printf "\033[1;33m[warn]\033[0m %s\n" "$*"; }
fail()  { printf "\033[1;31m[fail]\033[0m %s\n" "$*" >&2; exit 1; }

command -v docker >/dev/null || fail "docker not installed"
docker info >/dev/null 2>&1 || fail "docker daemon not reachable (start Docker Desktop?)"

# --- Auth check --------------------------------------------------------------

if [[ "$PUSH" == "1" ]]; then
  CFG="${DOCKER_CONFIG:-$HOME/.docker}/config.json"
  if ! jq -e '.auths["https://index.docker.io/v1/"] // .auths["index.docker.io"]' "$CFG" >/dev/null 2>&1; then
    info "Not logged in to Docker Hub. Running 'docker login'…"
    docker login
  fi
  ok "Docker Hub login found."
fi

# --- Buildx setup ------------------------------------------------------------

if ! docker buildx inspect "$BUILDER" >/dev/null 2>&1; then
  info "Creating buildx builder: $BUILDER"
  docker buildx create --name "$BUILDER" --use >/dev/null
else
  docker buildx use "$BUILDER" >/dev/null
fi
docker buildx inspect --bootstrap >/dev/null

# --- Archive step: preserve old remote tags before we overwrite them ---------
#
# Uses `docker buildx imagetools create` which copies the image manifest server-
# side. No pull/push of layers — just a new tag pointing at the same manifest.
#
# We tag if:
#   - the source tag exists on the registry
#   - the archive tag does NOT already exist (idempotent)

archive_tag() {
  local src="$1" dst="$2"
  if ! docker buildx imagetools inspect "${IMAGE}:${src}" >/dev/null 2>&1; then
    info "  source tag ${IMAGE}:${src} not found on registry — nothing to archive"
    return 0
  fi
  if docker buildx imagetools inspect "${IMAGE}:${dst}" >/dev/null 2>&1; then
    ok "  ${IMAGE}:${dst} already exists — skipping"
    return 0
  fi
  info "  archiving ${IMAGE}:${src} → ${IMAGE}:${dst}"
  docker buildx imagetools create --tag "${IMAGE}:${dst}" "${IMAGE}:${src}"
  ok "  archived"
}

if [[ "$PUSH" == "1" && "$SKIP_ARCHIVE" != "1" ]]; then
  info "Archive step (idempotent):"
  archive_tag "latest"       "archive-latest"
  archive_tag "no-transcode" "archive-no-transcode"
fi

# --- Build + push ------------------------------------------------------------

# Format: friendly_name TRANSCODE=... moving_tag
variants=(
  "no-transcode TRANSCODE=false latest"
  "transcode    TRANSCODE=true  transcode"
)

PUSH_FLAG="--load"
[[ "$PUSH" == "1" ]] && PUSH_FLAG="--push"

for spec in "${variants[@]}"; do
  read -r friendly build_arg moving <<<"$spec"
  dated_tag="${IMAGE}:${DATE_TAG}-${friendly}"
  moving_tag="${IMAGE}:${moving}"

  info "Building ${friendly} → ${dated_tag} + ${moving_tag}"
  docker buildx build \
    --platform "$PLATFORMS" \
    --build-arg "$build_arg" \
    --tag "$dated_tag" \
    --tag "$moving_tag" \
    $PUSH_FLAG \
    .

  if [[ "$PUSH" == "1" ]]; then
    ok "pushed ${dated_tag} and ${moving_tag}"
  else
    ok "built ${friendly} locally"
  fi
done

if [[ "$PUSH" != "1" ]]; then
  info "PUSH=0 — images built locally but not pushed. Images tagged:"
  docker images "${IMAGE}" --format 'table {{.Repository}}:{{.Tag}}\t{{.Size}}\t{{.CreatedAt}}' | head -20
fi

cat <<EOF

Tag map after this run:
  ${IMAGE}:latest                → no-transcode variant (current)
  ${IMAGE}:transcode             → transcode variant (current)
  ${IMAGE}:${DATE_TAG}-no-transcode   → immutable snapshot
  ${IMAGE}:${DATE_TAG}-transcode      → immutable snapshot
  ${IMAGE}:archive-latest        → old 2020 transcode image (rollback)
  ${IMAGE}:archive-no-transcode  → old 2021 no-transcode image (rollback)

To clean up the redundant legacy tag (optional — Docker Hub UI, or API):
  the old 'no-transcode' tag still points at the 2021 image. Delete it at
  https://hub.docker.com/r/${IMAGE}/tags  if you want the tag list tidy.
EOF
