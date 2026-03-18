#!/usr/bin/env bash

set -e

BOOTDIR="$PWD"

PREFIX="${PREFIX:-$HOME/.instow}"

SRCDIR="${SRCDIR:-$PREFIX/var/src}"
PKGDIR="${PKGDIR:-$PREFIX/var/pkg}"

mkdir -p "$SRCDIR"
mkdir -p "$PKGDIR"
ROOTDIR="$(mktemp -d)"

pushd "$SRCDIR"

echo "[1/9] Cloning janet repo"
[ -d janet ] || git clone https://github.com/janet-lang/janet

echo "[2/9] Building janet"
PREFIX="" DESTDIR="$ROOTDIR" make -C janet -j$(nproc) install

echo "[3/9] Cloning jpm repo"
[ -d jpm ] || git clone https://github.com/janet-lang/jpm

pushd jpm

echo "[4/9] Building jpm"
PREFIX="$ROOTDIR" DESTDIR="$ROOTDIR" JANET_PATH="$ROOTDIR/lib/janet" "$ROOTDIR/bin/janet" ./bootstrap.janet
cp -r "$ROOTDIR/$ROOTDIR/"* "$ROOTDIR/"
popd
popd

echo "[5/9] Building instow"
"$ROOTDIR/bin/jpm" build

pushd "$SRCDIR/janet"

echo "[6/9] Instowing janet"
JPM="$ROOTDIR/bin/jpm" "$ROOTDIR/bin/janet" "$BOOTDIR/instow"
popd

pushd "$SRCDIR/jpm"

echo "[7/9] Instowing jpm"
JPM="$ROOTDIR/bin/jpm" "$BOOTDIR/instow"
popd

echo "[8/9] Instowing instow"
./instow

echo "[9/9] Cleanup"
rm -rf "$ROOTDIR"
