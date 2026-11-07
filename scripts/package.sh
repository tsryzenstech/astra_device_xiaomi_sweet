#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# Bundles the images and the fastboot flashing scripts into a zip.
source "$(dirname "$0")/common.sh"
need zip

# Only images that passed scripts/verify.py get packaged.
[ "$OUT/verify.txt" -nt "$IMAGES/super.img" ] && grep -qx 'RESULT: PASS' "$OUT/verify.txt" ||
    die "these images did not pass the verification: run ./build.sh verify"

# The astraOS version the phone reports (27.0, or 27.0-rev3 for a pre-release).
version=$(grep '^ro.astra.version=' "$SYSTEM_ROOT/system/build.prop" | cut -d= -f2)
name="astraOS-${version:-dev}-${DEVICE}"
pkg=$OUT/$name
rm -rf "$pkg" "$pkg.zip"
mkdir -p "$pkg"
cp "$IMAGES"/{boot.img,boot-debug.img,boot-rescue.img,userdata.img,userdata-wipe.img,userdata-diag.img,vbmeta.img,super.img,SHA256SUMS} "$pkg/"
cp "$DEVICE_DIR"/flash/* "$OUT/verify.txt" "$pkg/"
cp "$OUT/u-boot/u-boot.img" "$pkg/"
(cd "$pkg" && sha256sum u-boot.img >> SHA256SUMS)
chmod +x "$pkg/flash-all.sh" "$pkg/flash-diag.sh"
(cd "$OUT" && zip -qr "$name.zip" "$name")
log "package: $OUT/$name.zip"

# ---- OTA ------------------------------------------------------------------------
# For a published build (release.json, from the GitHub workflow): what the phone
# downloads to update itself (see astra's docs/VERSIONING.md) and ota.json, which
# describes it. The phone writes super.img and the EFI partition on its next start.
if [ -f "$DEVICE_DIR/release.json" ]; then
    log "package: OTA files"
    compress=gzip
    command -v pigz >/dev/null 2>&1 && compress=pigz
    "$compress" -6 -c "$IMAGES/super.img" > "$OUT/$name-super.img.gz"
    "$compress" -9 -c "$OUT/esp.fat" > "$OUT/$name-esp.fat.gz"
    python3 - "$DEVICE_DIR/release.json" "$OUT/ota.json" "$DEVICE" "$version" \
        "$(grep '^ro.astra.codename=' "$SYSTEM_ROOT/system/build.prop" | cut -d= -f2)" \
        "$IMAGES/super.img" "$OUT/$name-super.img.gz" "$OUT/esp.fat" "$OUT/$name-esp.fat.gz" <<'PY'
import hashlib, json, os, sys
release, out, device, version, codename = sys.argv[1:6]
def describe(raw, packed):
    def sha(path):
        h = hashlib.sha256()
        with open(path, "rb") as f:
            for block in iter(lambda: f.read(1 << 22), b""):
                h.update(block)
        return h.hexdigest()
    return {"name": os.path.basename(packed), "size": os.path.getsize(packed), "sha256": sha(packed),
            "raw_size": os.path.getsize(raw), "raw_sha256": sha(raw)}
r = json.load(open(release))
manifest = {"format": 1, "device": device, "tag": r["tag"], "version": version, "codename": codename,
            "channel": r["channel"], "time": int(r["time"]), "notes": r.get("notes", []),
            "astra": r.get("astra", ""), "device_commit": r.get("device_commit", ""),
            "files": {"super": describe(sys.argv[6], sys.argv[7]), "esp": describe(sys.argv[8], sys.argv[9])}}
json.dump(manifest, open(out, "w"), indent=1, ensure_ascii=False)
PY
    log "package: $OUT/$name-super.img.gz, $OUT/$name-esp.fat.gz, $OUT/ota.json"
fi
