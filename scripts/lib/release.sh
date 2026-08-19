# Resolve the current OpenAstro Linux release from GitHub.
# Sourced by scripts/install, scripts/flash-rootfs, scripts/flash-all.
#
# Sets: RELEASE_TAG (e.g. "v1.2") and RELEASE_URL (rootfs image download URL).
# Falls back to RELEASE_FALLBACK_TAG when GitHub is unreachable.

RELEASE_REPO="open-astro/rk-flashtool"
RELEASE_FALLBACK_TAG="v1.2"

resolve_release() {
    local latest_url="https://github.com/$RELEASE_REPO/releases/latest"
    local tag=""
    if command -v curl >/dev/null 2>&1; then
        tag="$(curl -fsSL -o /dev/null -w '%{url_effective}' "$latest_url" 2>/dev/null \
               | sed -n 's#.*/tag/##p')"
    elif command -v wget >/dev/null 2>&1; then
        tag="$(wget --max-redirect=0 -O /dev/null -S "$latest_url" 2>&1 \
               | sed -n 's#.*[Ll]ocation: .*/tag/\([^ ]*\).*#\1#p' | head -n1)"
    fi
    if [ -z "$tag" ]; then
        tag="$RELEASE_FALLBACK_TAG"
        echo "WARNING: could not query GitHub for the latest release; assuming $tag" >&2
    fi
    RELEASE_TAG="$tag"
    RELEASE_URL="https://github.com/$RELEASE_REPO/releases/download/$RELEASE_TAG/rootfs-stock.img.gz"
}
