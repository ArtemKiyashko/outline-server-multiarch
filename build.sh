#!/bin/bash
set -x

: '
# by HoJeong Go

Usage:

    ./build.sh $arch $tag $checkpoint

    -- Arguments:

    $arch {string} The arch to build, using docker platform style
    $tag {string} The docker tag to use while building the image
    $checkpoint {string} The git branch or tag to checkout on Jigsaw-Code/Outline-Server

    -- Environments:

    $AB_LEAVE_BASE_DIRECTORY {any} If it is not empty string, script will not clean working directory

About:

    This script builds Outline-Server docker buildx image
    with specific arch by downloading compatible third_party
    automatically.
'

readonly REPO_BASE="Jigsaw-Code/outline-server"
readonly NS_BASE="outline-server"

readonly REPO_SSS="Jigsaw-Code/outline-ss-server"
readonly NS_SSS="outline-ss-server"

readonly REPO_PROM="prometheus/prometheus"
readonly NS_PROM="prometheus"

TMP=$(mktemp -d)
# Need to ARCH in build script
ARCH=${1}
TAG=${2}
CHECKPOINT=${3}

export DOCKER_PLATFORMS="${ARCH}"

gh_releases() {
    local REPO=${1}

    echo $(
        curl -sL "https://api.github.com/repos/${REPO}/releases" | \
        jq -r '[.[] | select(.prerelease == false)][0]'
    )
}

gh_release_asset_url_by_arch() {
    local REPO=${1} ARCH=${2}

    echo $(
        gh_releases "${REPO}" | \
        jq -r "[.assets[] | select(.name | contains(\"${ARCH}\"))][0].browser_download_url"
    )
}

unpack_archive_from_url() {
    local NAME=${1} URL=${2} STRIP_LEVEL=${3}

    mkdir -p "${TMP}/${NAME}"

    curl -sL "${URL}" -o "${TMP}/${NAME}.archive"
    tar -xf "${TMP}/${NAME}.archive" -C "${TMP}/${NAME}" --strip-components="${STRIP_LEVEL}"
}

remap_arch() {
    local ARCH="${1}" AMD64="${2:-amd64}" ARM64="${3:-arm64}" ARMv7="${4:-armv7}" ARMv6="${5:-armv6}"

    [[ "${ARCH}" == *"amd64"* ]] && echo "${AMD64}"
    [[ "${ARCH}" == *"arm64"* ]] && echo "${ARM64}"
    [[ "${ARCH}" == *"v7"* ]] && echo "${ARMv7}"
    [[ "${ARCH}" == *"v6"* ]] && echo "${ARMv6}"
}

# Clone outline-server
[[ ! -d "./outline-server" ]] && git clone "https://github.com/${REPO_BASE}.git" "${NS_BASE}"

# Go to repo and checkout to latest release
cd "${NS_BASE}"

# Use patch latest
if [[ "${CHECKPOINT}" == "latest" ]]; then
    CHECKPOINT="$(git describe --tags --abbrev=0)"
fi

git checkout "${CHECKPOINT}"

# Multi arch build
for C_ARCH in ${ARCH//,/ }
do
    # Download outline-ss-server
    ARCH_SSS="$(remap_arch "${C_ARCH}" x86_64 arm64 armv7 armv6)"
    RES_SSS="$(gh_release_asset_url_by_arch "${REPO_SSS}" "linux_${ARCH_SSS}")"

    unpack_archive_from_url "${NS_SSS}.${ARCH_SSS}" "${RES_SSS}" "0"

    mkdir -p "third_parties/${C_ARCH}/outline-ss-server"
    mv "${TMP}/${NS_SSS}.${ARCH_SSS}/outline-ss-server" "third_parties/${C_ARCH}/outline-ss-server/"

    # Download prometheus
    ARCH_PROM="$(remap_arch "${C_ARCH}" amd64 arm64 armv7 armv6)"
    RES_PROM="$(gh_release_asset_url_by_arch "${REPO_PROM}" "linux-${ARCH_PROM}")"

    unpack_archive_from_url "${NS_PROM}.${ARCH_PROM}" "${RES_PROM}" "1"

    mkdir -p "third_parties/${C_ARCH}/prometheus"
    mv "${TMP}/${NS_PROM}.${ARCH_PROM}/prometheus" "third_parties/${C_ARCH}/prometheus/"
done

# Apply patches
# for FILE in ../patches/*.patch; do
#     [[ -e "${FILE}" ]] || continue;
#     git apply "${FILE}";
# done;

# Build docker-image
export SB_IMAGE="${TAG}"
export NODE_IMAGE="node:16-alpine"

npm run

# Clean-up
cd ..

rm -rf "${TMP}"
[[ "${AB_LEAVE_BASE_DIRECTORY}" == "" ]] && rm -rf "${NS_BASE}"
