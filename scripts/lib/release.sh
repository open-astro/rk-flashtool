# Resolve the current OpenAstro Linux release from GitHub.
# Sourced by scripts/install, scripts/flash-rootfs, scripts/flash-all.
#
# resolve_release [images_dir]
# Sets: RELEASE_TAG (e.g. "v1.2") and RELEASE_URL (rootfs image download URL).
# Fails fast (5s connect / 15s total) when GitHub is unreachable; then falls
# back to the newest version-stamped image cached in images_dir, and finally
# to RELEASE_FALLBACK_TAG, so offline runs with a cached image still work.

RELEASE_REPO="open-astro/rk-flashtool"
RELEASE_FALLBACK_TAG="v1.2"

resolve_release() {
    local images_dir="$1"
    local latest_url="https://github.com/$RELEASE_REPO/releases/latest"
    local tag=""
    if command -v curl >/dev/null 2>&1; then
        tag="$(curl -fsSL --connect-timeout 5 --max-time 15 \
               -o /dev/null -w '%{url_effective}' "$latest_url" 2>/dev/null \
               | sed -n 's#.*/tag/##p')"
    elif command -v wget >/dev/null 2>&1; then
        tag="$(wget --timeout=5 --tries=1 --max-redirect=0 -O /dev/null -S \
               "$latest_url" 2>&1 \
               | sed -n 's#.*[Ll]ocation: .*/tag/\([^ ]*\).*#\1#p' | head -n1)"
    fi
    # Only accept a sane tag (v + digits/dots); anything else means resolution failed.
    case "$tag" in
        v[0-9]*) case "$tag" in *[!v0-9.]*) tag="" ;; esac ;;
        *) tag="" ;;
    esac

    if [ -z "$tag" ] && [ -n "$images_dir" ]; then
        local cached
        cached="$(ls "$images_dir"/astrolinux-trixie-rk3568-v*.img \
                     "$images_dir"/astrolinux-trixie-rk3568-v*.img.gz 2>/dev/null \
                  | sort -V | tail -n1)"
        if [ -n "$cached" ]; then
            tag="$(basename "$cached")"
            tag="${tag#astrolinux-trixie-rk3568-}"
            tag="${tag%.img.gz}"; tag="${tag%.img}"
            echo "WARNING: could not reach GitHub; using cached image release $tag" >&2
        fi
    fi
    if [ -z "$tag" ]; then
        tag="$RELEASE_FALLBACK_TAG"
        echo "WARNING: could not query GitHub for the latest release; assuming $tag" >&2
    fi

    # Old unstamped caches predate version-stamped filenames and are ignored.
    if [ -n "$images_dir" ] && ls "$images_dir"/astrolinux-trixie-rk3568.img* >/dev/null 2>&1; then
        echo "NOTE: ignoring unversioned cached image(s) in $images_dir (unknown release);" >&2
        echo "      pass the file as an argument to use it, or delete it to save space." >&2
    fi

    RELEASE_TAG="$tag"
    RELEASE_URL="https://github.com/$RELEASE_REPO/releases/download/$RELEASE_TAG/rootfs-stock.img.gz"
}
