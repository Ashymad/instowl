#!/usr/bin/env bash

set -e

sedi() {
    file="$1"
    shift

    sed "$@" "$file" > "$file".tmp
    cat "$file".tmp > "$file"
    rm "$file".tmp
}

BOOTDIR="$PWD"

PREFIX="${PREFIX:-$HOME/.local}"

SRCDIR="${SRCDIR:-$PREFIX/src}"
PKGDIR="${PKGDIR:-$PREFIX/pkg}"

mkdir -p "$SRCDIR"
mkdir -p "$PKGDIR"
ROOTDIR="$(mktemp -d)"

pushd "$SRCDIR"

echo "[1/9] Cloning janet repo"
git clone https://github.com/janet-lang/janet

echo "[2/9] Building janet"
PREFIX="" DESTDIR="$ROOTDIR" make -C janet -j$(nproc) install

echo "[3/9] Cloning jpm repo"
git clone https://github.com/janet-lang/jpm

pushd jpm

sedi project.janet 's/(dyn :modpath)/(dyn :dest-dir)/'
mkdir -p "$ROOTDIR/lib/janet/jpm"
mkdir -p "$ROOTDIR/$ROOTDIR/lib/janet/jpm"

echo "[4/9] Building jpm"
PREFIX="" DESTDIR="$ROOTDIR" JANET_PATH="$ROOTDIR/lib/janet" "$ROOTDIR/bin/janet" ./bootstrap.janet
popd
popd

cp -r $ROOTDIR/$ROOTDIR/* $ROOTDIR/
sedi "$ROOTDIR/bin/jpm" '1s@^@#!/usr/bin/env janet\n@'

echo "[5/9] Building instowl"
"$ROOTDIR/bin/janet" "$ROOTDIR/bin/jpm" --headerpath="$ROOTDIR/include" build

pushd "$SRCDIR/janet"

echo "[6/9] Instowling janet"
JPM="$ROOTDIR/bin/jpm" "$ROOTDIR/bin/janet" "$BOOTDIR/instowl.local"
popd

pushd "$SRCDIR/jpm"

echo "[7/9] Instowling jpm"
JPM="$ROOTDIR/bin/jpm" "$BOOTDIR/instowl.local"
popd

echo "[8/9] Instowling instowl"
./instowl.local

echo "[9/9] Cleanup"
rm -rf "$ROOTDIR"
