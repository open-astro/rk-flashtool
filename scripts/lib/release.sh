# Resolve the current OpenAstro Linux release from GitHub.
# Sourced by scripts/install, scripts/flash-rootfs, scripts/flash-all.
#
# resolve_release [images_dir]
# Sets: RELEASE_TAG (e.g. "v1.2") and RELEASE_URL (rootfs image download URL).
# Fails fast (5s connect / 15s total) when GitHub is unreachable; then falls
# back to the newest version-stamped image cached in images_dir, and finally
# to RELEASE_FALLBACK_TAG, so offline runs with a cached image still work.
# OPENASTRO_RELEASE=<tag> pins a release (e.g. a beta) instead of "latest".
#
# Two kinds of release:
#   stock    assets: rootfs-stock.img.gz     (ZWO 4.19 kernel stays in p3)
#   mainline assets: rootfs-mainline.img.gz + boot-mainline.img (p3 image)
# fetch_release_images (below) works out which one a release is and downloads
# or reuses the cached files.

RELEASE_REPO="open-astro/rk-flashtool"
RELEASE_FALLBACK_TAG="v1.1"

# A sane tag is v + digit, then digits/dots/hyphens/alphanumerics (covers
# pre-release tags like v1.3.0-rc1); anything else is rejected — applied to
# both network-resolved tags and tags derived from cached filenames.
valid_tag() {
    case "$1" in
        v[0-9]*) case "$1" in *[!v0-9A-Za-z.-]*) return 1 ;; *) return 0 ;; esac ;;
        *) return 1 ;;
    esac
}

resolve_release() {
    local images_dir="$1"
    local latest_url="https://github.com/$RELEASE_REPO/releases/latest"
    local tag=""
    if [ -n "${OPENASTRO_RELEASE:-}" ]; then
        if ! valid_tag "$OPENASTRO_RELEASE"; then
            echo "ERROR: OPENASTRO_RELEASE='$OPENASTRO_RELEASE' is not a valid tag (e.g. v2.0)" >&2
            return 1
        fi
        RELEASE_TAG="$OPENASTRO_RELEASE"
        RELEASE_URL="https://github.com/$RELEASE_REPO/releases/download/$RELEASE_TAG/rootfs-stock.img.gz"
        echo "Using pinned release $RELEASE_TAG (OPENASTRO_RELEASE)" >&2
        return 0
    fi
    if command -v curl >/dev/null 2>&1; then
        tag="$(curl -fsSL --connect-timeout 5 --max-time 15 \
               -o /dev/null -w '%{url_effective}' "$latest_url" 2>/dev/null \
               | sed -n 's#.*/tag/##p')"
    elif command -v wget >/dev/null 2>&1; then
        # wget's --timeout bounds each phase (DNS/connect/read), not total
        # wall-clock time; wrap in coreutils timeout for a hard 15s cap.
        local wget_cmd="wget"
        command -v timeout >/dev/null 2>&1 && wget_cmd="timeout 15 wget"
        tag="$($wget_cmd --timeout=5 --tries=1 --max-redirect=0 -O /dev/null -S \
               "$latest_url" 2>&1 \
               | sed -n 's#.*[Ll]ocation: .*/tag/\([^ ]*\).*#\1#p' | head -n1)"
    fi
    valid_tag "$tag" || tag=""

    if [ -z "$tag" ] && [ -n "$images_dir" ]; then
        local cached
        cached="$(ls "$images_dir"/astrolinux-trixie-rk3568-v*.img \
                     "$images_dir"/astrolinux-trixie-rk3568-v*.img.gz 2>/dev/null \
                  | sort -V | tail -n1)"
        if [ -n "$cached" ]; then
            tag="$(basename "$cached")"
            tag="${tag#astrolinux-trixie-rk3568-}"
            tag="${tag%.img.gz}"; tag="${tag%.img}"
            valid_tag "$tag" || tag=""
            [ -n "$tag" ] && echo "WARNING: could not reach GitHub; using cached image release $tag" >&2
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

# --- Release images ---------------------------------------------------------

# _release_download <url> <dest>: download to <dest>.part, rename on success,
# so an interrupted download is never mistaken for a complete cached file.
_release_download() {
    local url="$1" dest="$2"
    echo "  $url" >&2
    if command -v wget >/dev/null 2>&1; then
        wget -q --show-progress -O "$dest.part" "$url" || { rm -f "$dest.part"; return 1; }
    elif command -v curl >/dev/null 2>&1; then
        curl -fL -o "$dest.part" "$url" || { rm -f "$dest.part"; return 1; }
    else
        echo "ERROR: wget or curl is required to download the image." >&2
        return 1
    fi
    mv "$dest.part" "$dest"
}

# _release_asset_exists <url>: 0 if the release asset exists (HTTP 200 after
# GitHub's redirect), 1 if it doesn't, 2 if GitHub can't be reached.
_release_asset_exists() {
    local url="$1" code=""
    if command -v curl >/dev/null 2>&1; then
        code="$(curl -sIL --connect-timeout 5 --max-time 20 -o /dev/null -w '%{http_code}' "$url" 2>/dev/null)"
    elif command -v wget >/dev/null 2>&1; then
        code="$(wget --spider -S --timeout=10 --tries=1 "$url" 2>&1 | awk '/HTTP\//{c=$2} END{print c}')"
    fi
    case "$code" in
        200) return 0 ;;
        404) return 1 ;;
        *)   return 2 ;;
    esac
}

# _release_check_boot <file>: sanity-check a p3 boot image.
_release_check_boot() {
    [ "$(head -c 8 "$1" 2>/dev/null)" = "ANDROID!" ] \
        || { echo "ERROR: $1 is not an Android boot image" >&2; return 1; }
    [ "$(stat -c %s "$1")" -le 67108864 ] \
        || { echo "ERROR: $1 is larger than the 64 MB boot partition" >&2; return 1; }
}

# fetch_release_images <images_dir>
# Needs resolve_release to have run. Reuses cached files, otherwise downloads.
# Sets:
#   RELEASE_FLAVOR  "stock" or "mainline"
#   ROOTFS_IMG      rootfs image (.img or .img.gz) for p7
#   BOOT_IMG        mainline p3 boot image, or empty for a stock release
#                   (callers then write the stock p3 from the user's backup)
# Cache names (images_dir):
#   astrolinux-trixie-rk3568-<tag>.img[.gz]   rootfs, both flavors
#   astrolinux-trixie-rk3568-<tag>.boot.bin   mainline p3 boot image
fetch_release_images() {
    local images_dir="$1"
    local base="https://github.com/$RELEASE_REPO/releases/download/$RELEASE_TAG"
    local stem="$images_dir/astrolinux-trixie-rk3568-$RELEASE_TAG"
    local boot_cache="$stem.boot.bin"
    local rootfs_cache="" ext
    for ext in .img .img.gz; do
        [ -f "$stem$ext" ] && { rootfs_cache="$stem$ext"; break; }
    done

    RELEASE_FLAVOR="" BOOT_IMG="" ROOTFS_IMG=""
    if [ -f "$boot_cache" ]; then
        RELEASE_FLAVOR=mainline
    elif [ -n "$rootfs_cache" ]; then
        # The boot image is always fetched before the rootfs, so a cached
        # rootfs without a cached boot image is a stock release.
        RELEASE_FLAVOR=stock
    else
        # "|| rc=$?": a bare non-zero call would abort callers running set -e
        local rc=0
        _release_asset_exists "$base/boot-mainline.img" || rc=$?
        case $rc in
            0) RELEASE_FLAVOR=mainline ;;
            1) RELEASE_FLAVOR=stock ;;
            *) echo "ERROR: cannot reach GitHub to download release $RELEASE_TAG, and nothing is cached in $images_dir." >&2
               return 1 ;;
        esac
    fi

    mkdir -p "$images_dir"
    if [ "$RELEASE_FLAVOR" = mainline ]; then
        if [ ! -f "$boot_cache" ]; then
            echo "Downloading $RELEASE_TAG boot image (mainline kernel)..." >&2
            _release_download "$base/boot-mainline.img" "$boot_cache" || return 1
        fi
        _release_check_boot "$boot_cache" || return 1
        BOOT_IMG="$boot_cache"
        if [ -z "$rootfs_cache" ]; then
            echo "Downloading $RELEASE_TAG rootfs..." >&2
            _release_download "$base/rootfs-mainline.img.gz" "$stem.img.gz" || return 1
            rootfs_cache="$stem.img.gz"
        fi
    elif [ -z "$rootfs_cache" ]; then
        echo "Downloading $RELEASE_TAG rootfs..." >&2
        _release_download "$base/rootfs-stock.img.gz" "$stem.img.gz" || return 1
        rootfs_cache="$stem.img.gz"
    fi
    ROOTFS_IMG="$rootfs_cache"
    echo "Release $RELEASE_TAG ($RELEASE_FLAVOR kernel): $(basename "$ROOTFS_IMG")${BOOT_IMG:+ + $(basename "$BOOT_IMG")}" >&2
}
