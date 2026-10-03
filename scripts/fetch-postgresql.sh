#!/bin/sh
# Downloads one PostgreSQL source release and checks it against the digest
# postgresql.org publishes for it.
#
# The file is only moved into place once it has been verified, so an
# interrupted or corrupted download cannot be mistaken for a good one by the
# next make.
#
# Usage:
#   scripts/fetch-postgresql.sh <url> <sha256> <destination-file>
set -eu

url=${1:?usage: fetch-postgresql.sh <url> <sha256> <dest-file>}
want=${2:?usage: fetch-postgresql.sh <url> <sha256> <dest-file>}
dest=${3:?usage: fetch-postgresql.sh <url> <sha256> <dest-file>}

die() { echo "fetch-postgresql: $*" >&2; exit 1; }

sha256() {
    if command -v sha256sum >/dev/null 2>&1; then
        sha256sum "$1" | cut -d' ' -f1
    elif command -v shasum >/dev/null 2>&1; then
        shasum -a 256 "$1" | cut -d' ' -f1
    elif command -v openssl >/dev/null 2>&1; then
        openssl dgst -sha256 -r "$1" | cut -d' ' -f1
    else
        die "no SHA-256 tool found: need sha256sum, shasum or openssl"
    fi
}

fetch() {
    if command -v curl >/dev/null 2>&1; then
        curl -fsSL -o "$2" "$1"
    elif command -v wget >/dev/null 2>&1; then
        wget -q -O "$2" "$1"
    else
        die "neither curl nor wget is installed"
    fi
}

mkdir -p "$(dirname "$dest")"
tmp="$dest.incoming.$$"
trap 'rm -f "$tmp"' EXIT INT TERM

echo "fetch-postgresql: downloading $url"
fetch "$url" "$tmp" || die "download failed: $url"

got=$(sha256 "$tmp")
if [ "$got" != "$want" ]; then
    die "SHA-256 mismatch for $url
   expected $want
   actual   $got
   Nothing has been unpacked. Either the download was corrupted -- try
   again -- or the pinned digest in the makefile no longer describes what
   postgresql.org is serving, which is worth understanding before building."
fi
echo "fetch-postgresql: SHA-256 $got verified"

mv "$tmp" "$dest"
echo "fetch-postgresql: $dest"
