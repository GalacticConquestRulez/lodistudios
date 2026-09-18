#!/usr/bin/env bash
#
# build-libssh2.sh — build libssh2 (mbedTLS crypto backend) as an Apple xcframework.
#
# This is the rebuild recipe for Vendor/libssh2.xcframework. The committed
# artifact means a fresh clone builds LodiKit without running this script; run
# this only to regenerate or bump versions.
#
# What it does, from a clean checkout:
#   1. Downloads pinned source tarballs for mbedTLS (3.6.x LTS) and libssh2
#      (1.11.x) and verifies them by SHA-256. Fails loudly on any download or
#      checksum error.
#   2. For each of three Apple slices — macOS arm64, iOS arm64 device, iOS arm64
#      simulator — builds mbedTLS and libssh2 as *static* libraries with CMake,
#      using CMake's native iOS support (-DCMAKE_SYSTEM_NAME=iOS), no
#      third-party toolchain file.
#   3. Merges the four static archives (libmbedcrypto, libmbedx509, libmbedtls,
#      libssh2) for each slice into a single archive with `libtool -static`, so
#      the xcframework carries exactly one library per slice.
#   4. Packages the three slices plus the public libssh2 headers into
#      Vendor/libssh2.xcframework with `xcodebuild -create-xcframework`.
#
# All intermediate work happens in a gitignored temp dir
# (scripts/.build-libssh2). The only committed outputs are this script and
# Vendor/libssh2.xcframework.

set -euo pipefail

# ---------------------------------------------------------------------------
# Pinned versions and integrity hashes
# ---------------------------------------------------------------------------
# mbedTLS: current 3.6.x LTS. The release .tar.bz2 bundles its framework
# submodules, so no submodule fetch is needed. SHA-256 is from the official
# mbedtls-<v>-sha256sum.txt release asset.
MBEDTLS_VERSION="3.6.7"
MBEDTLS_TARBALL="mbedtls-${MBEDTLS_VERSION}.tar.bz2"
MBEDTLS_URL="https://github.com/Mbed-TLS/mbedtls/releases/download/mbedtls-${MBEDTLS_VERSION}/${MBEDTLS_TARBALL}"
MBEDTLS_SHA256="a7e8bcbec0e6f761b4af24f25677626b35f762f68eef79c08677a363212d11f6"

# libssh2: current 1.11.x. libssh2 ships GPG signatures but no sha256sum asset,
# so this hash was computed from the official release tarball and pinned here.
LIBSSH2_VERSION="1.11.1"
LIBSSH2_TARBALL="libssh2-${LIBSSH2_VERSION}.tar.xz"
LIBSSH2_URL="https://github.com/libssh2/libssh2/releases/download/libssh2-${LIBSSH2_VERSION}/${LIBSSH2_TARBALL}"
LIBSSH2_SHA256="9954cb54c4f548198a7cbebad248bdc87dd64bd26185708a294b2b50771e3769"

# Deployment targets (match LodiKit/Package.swift).
MACOS_MIN="14.0"
IOS_MIN="17.0"

# ---------------------------------------------------------------------------
# Paths
# ---------------------------------------------------------------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
WORK_DIR="${SCRIPT_DIR}/.build-libssh2"          # gitignored temp
SRC_DIR="${WORK_DIR}/src"
DL_DIR="${WORK_DIR}/downloads"
OUT_DIR="${WORK_DIR}/out"                          # per-slice merged libs + headers
XCFRAMEWORK_OUT="${REPO_ROOT}/Vendor/libssh2.xcframework"

log()  { printf '\033[1;36m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33mwarn:\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[1;31merror:\033[0m %s\n' "$*" >&2; exit 1; }

# ---------------------------------------------------------------------------
# Preflight
# ---------------------------------------------------------------------------
for tool in cmake xcodebuild libtool curl shasum tar; do
    command -v "$tool" >/dev/null 2>&1 || die "required tool not found: $tool"
done

log "Clean work dir: ${WORK_DIR}"
rm -rf "${WORK_DIR}"
mkdir -p "${SRC_DIR}" "${DL_DIR}" "${OUT_DIR}"

# ---------------------------------------------------------------------------
# Download + verify + extract
# ---------------------------------------------------------------------------
fetch() {
    local url="$1" out="$2"
    log "Downloading ${url}"
    curl --fail --location --silent --show-error -o "${out}" "${url}" \
        || die "download failed: ${url}"
    [ -s "${out}" ] || die "downloaded file is empty: ${out}"
}

verify_sha256() {
    local file="$1" expected="$2"
    local actual
    actual="$(shasum -a 256 "${file}" | awk '{print $1}')"
    if [ "${actual}" != "${expected}" ]; then
        die "checksum mismatch for ${file}
  expected: ${expected}
  actual:   ${actual}"
    fi
    log "Checksum OK: $(basename "${file}")"
}

fetch "${MBEDTLS_URL}" "${DL_DIR}/${MBEDTLS_TARBALL}"
verify_sha256 "${DL_DIR}/${MBEDTLS_TARBALL}" "${MBEDTLS_SHA256}"

fetch "${LIBSSH2_URL}" "${DL_DIR}/${LIBSSH2_TARBALL}"
verify_sha256 "${DL_DIR}/${LIBSSH2_TARBALL}" "${LIBSSH2_SHA256}"

log "Extracting sources"
tar -xjf "${DL_DIR}/${MBEDTLS_TARBALL}" -C "${SRC_DIR}"
tar -xJf "${DL_DIR}/${LIBSSH2_TARBALL}" -C "${SRC_DIR}"

MBEDTLS_SRC="${SRC_DIR}/mbedtls-${MBEDTLS_VERSION}"
LIBSSH2_SRC="${SRC_DIR}/libssh2-${LIBSSH2_VERSION}"
[ -d "${MBEDTLS_SRC}" ] || die "mbedTLS source dir not found: ${MBEDTLS_SRC}"
[ -d "${LIBSSH2_SRC}" ] || die "libssh2 source dir not found: ${LIBSSH2_SRC}"

# ---------------------------------------------------------------------------
# Per-slice build
# ---------------------------------------------------------------------------
# build_slice <slice-name> <sysroot> <system-name> <min-flag>
#   slice-name : xcframework slice id, e.g. macos-arm64
#   sysroot    : CMAKE_OSX_SYSROOT (macosx | iphoneos | iphonesimulator)
#   system-name: "" for macOS (Darwin default), "iOS" for iOS device/sim
#   min-flag   : the compiler min-version flag, e.g. -mmacosx-version-min=14.0
build_slice() {
    local slice="$1" sysroot="$2" system_name="$3" min_flag="$4"

    log "================ Building slice: ${slice} (${sysroot}) ================"

    local slice_build="${WORK_DIR}/build/${slice}"
    local mbedtls_build="${slice_build}/mbedtls"
    local mbedtls_install="${slice_build}/mbedtls-install"
    local libssh2_build="${slice_build}/libssh2"
    local libssh2_install="${slice_build}/libssh2-install"
    rm -rf "${slice_build}"
    mkdir -p "${mbedtls_build}" "${libssh2_build}"

    # Common CMake args shared by both mbedTLS and libssh2 for this slice.
    local -a common_args=(
        -G "Unix Makefiles"
        -DCMAKE_BUILD_TYPE=Release
        -DCMAKE_OSX_ARCHITECTURES=arm64
        -DCMAKE_OSX_SYSROOT="${sysroot}"
        -DBUILD_SHARED_LIBS=OFF
        -DCMAKE_C_FLAGS="${min_flag}"
    )
    if [ -n "${system_name}" ]; then
        # CMake native iOS support. No code signing for a static lib. Disabling
        # the "combined" install keeps CMake from expecting a device+sim fat build.
        common_args+=(
            -DCMAKE_SYSTEM_NAME="${system_name}"
            -DCMAKE_OSX_DEPLOYMENT_TARGET="${IOS_MIN}"
            "-DCMAKE_IOS_INSTALL_COMBINED=NO"
        )
    else
        common_args+=( -DCMAKE_OSX_DEPLOYMENT_TARGET="${MACOS_MIN}" )
    fi

    # ---- mbedTLS ----------------------------------------------------------
    log "[${slice}] Configuring mbedTLS"
    cmake -S "${MBEDTLS_SRC}" -B "${mbedtls_build}" \
        "${common_args[@]}" \
        -DCMAKE_INSTALL_PREFIX="${mbedtls_install}" \
        -DENABLE_TESTING=OFF \
        -DENABLE_PROGRAMS=OFF \
        -DMBEDTLS_FATAL_WARNINGS=OFF \
        || die "[${slice}] mbedTLS configure failed"

    log "[${slice}] Building + installing mbedTLS"
    cmake --build "${mbedtls_build}" --target install -j "$(sysctl -n hw.ncpu)" \
        || die "[${slice}] mbedTLS build failed"

    # ---- libssh2 (mbedTLS backend) ---------------------------------------
    log "[${slice}] Configuring libssh2 (CRYPTO_BACKEND=mbedTLS)"
    cmake -S "${LIBSSH2_SRC}" -B "${libssh2_build}" \
        "${common_args[@]}" \
        -DCMAKE_INSTALL_PREFIX="${libssh2_install}" \
        -DCRYPTO_BACKEND=mbedTLS \
        -DCMAKE_PREFIX_PATH="${mbedtls_install}" \
        -DMBEDTLS_INCLUDE_DIR="${mbedtls_install}/include" \
        -DMBEDCRYPTO_LIBRARY="${mbedtls_install}/lib/libmbedcrypto.a" \
        -DBUILD_EXAMPLES=OFF \
        -DBUILD_TESTING=OFF \
        -DENABLE_ZLIB_COMPRESSION=OFF \
        -DRUN_DOCKER_TESTS=OFF \
        -DRUN_SSHD_TESTS=OFF \
        || die "[${slice}] libssh2 configure failed"

    log "[${slice}] Building + installing libssh2"
    cmake --build "${libssh2_build}" --target install -j "$(sysctl -n hw.ncpu)" \
        || die "[${slice}] libssh2 build failed"

    # ---- merge into one static archive -----------------------------------
    # mbedTLS installs libmbedcrypto/libmbedx509/libmbedtls; libssh2 installs
    # libssh2.a. Combine all four into a single per-slice archive so the
    # xcframework carries one library.
    local merged="${OUT_DIR}/${slice}/libssh2.a"
    mkdir -p "${OUT_DIR}/${slice}"

    local -a archives=(
        "${libssh2_install}/lib/libssh2.a"
        "${mbedtls_install}/lib/libmbedtls.a"
        "${mbedtls_install}/lib/libmbedx509.a"
        "${mbedtls_install}/lib/libmbedcrypto.a"
    )
    for a in "${archives[@]}"; do
        [ -f "${a}" ] || die "[${slice}] expected archive missing: ${a}"
    done

    log "[${slice}] Merging static archives -> ${merged}"
    libtool -static -o "${merged}" "${archives[@]}" \
        || die "[${slice}] libtool merge failed"

    # Stash the libssh2 public headers once (same for every slice). Capture from
    # the first slice's install into a shared headers dir.
    if [ ! -d "${OUT_DIR}/include" ]; then
        mkdir -p "${OUT_DIR}/include"
        for h in libssh2.h libssh2_sftp.h libssh2_publickey.h; do
            cp "${libssh2_install}/include/${h}" "${OUT_DIR}/include/${h}" \
                || die "missing public header: ${h}"
        done
    fi

    log "[${slice}] done"
}

# macOS arm64: Darwin default, no CMAKE_SYSTEM_NAME.
build_slice "macos-arm64" "macosx" "" "-mmacosx-version-min=${MACOS_MIN}"

# iOS arm64 device.
build_slice "ios-arm64" "iphoneos" "iOS" "-miphoneos-version-min=${IOS_MIN}"

# iOS arm64 simulator.
build_slice "ios-arm64-simulator" "iphonesimulator" "iOS" "-mios-simulator-version-min=${IOS_MIN}"

# ---------------------------------------------------------------------------
# Package the xcframework
# ---------------------------------------------------------------------------
log "Creating xcframework: ${XCFRAMEWORK_OUT}"
rm -rf "${XCFRAMEWORK_OUT}"

xcodebuild -create-xcframework \
    -library "${OUT_DIR}/macos-arm64/libssh2.a"          -headers "${OUT_DIR}/include" \
    -library "${OUT_DIR}/ios-arm64/libssh2.a"            -headers "${OUT_DIR}/include" \
    -library "${OUT_DIR}/ios-arm64-simulator/libssh2.a"  -headers "${OUT_DIR}/include" \
    -output "${XCFRAMEWORK_OUT}" \
    || die "xcodebuild -create-xcframework failed"

log "Slices in xcframework:"
/usr/libexec/PlistBuddy -c "Print :AvailableLibraries" "${XCFRAMEWORK_OUT}/Info.plist" 2>/dev/null \
    | grep -E "LibraryIdentifier" || true

log "Done."
log "mbedTLS ${MBEDTLS_VERSION} + libssh2 ${LIBSSH2_VERSION} (crypto backend: mbedTLS)"
log "Artifact: ${XCFRAMEWORK_OUT}"
