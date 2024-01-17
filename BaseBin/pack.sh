#!/bin/sh

set -e

PREV_DIR=$(pwd)
PACK_DIR=$(dirname -- "$0")
cd "$PACK_DIR"

TARGET="../basebin.tar"

if [ -d "$TARGET" ]; then
	rm -rf "$TARGET"
fi

if [ -d "basebin.tar" ]; then
	rm -rf "basebin.tar"
fi

if [ -d ".tmp/basebin" ]; then
	rm -rf ".tmp/basebin"
fi
mkdir -p ".tmp/basebin"

# jailbreakd
cd "telescoped"
make
cp ".theos/obj/debug/telescoped" "../.tmp/basebin/telescoped"
cd -

# jbinit
cd "telescopeinit"
make
cp ".theos/obj/debug/telescopeinit" "../.tmp/basebin/telescopeinit"
cd -

# external
cp -r ./_external/* .tmp/basebin/

# Create TrustCache, for basebinaries
rm -rf "./basebin.tc"
./TrustCache create "./basebin.tc" "./.tmp/basebin"
cp "./basebin.tc" "./.tmp/basebin"

# Tar /tmp to basebin.tar
cd ".tmp"
# only works with procursus tar for whatever reason
sudo tar -cvf "../$TARGET" "./basebin"
cd -

rm -rf ".tmp"

cd "$PREV_DIR"