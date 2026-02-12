#!/bin/bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")" && pwd)"
SRC_MARK="$ROOT_DIR/assets/app-icon-source.png"
TMP_DIR="/tmp/drmedhat-icon"
BASE_PNG="$TMP_DIR/icon-base.png"

# FaceTime-style background (solid color). Adjust if you want a different shade.
BG_COLOR_HEX="E6F7FB"  # light blue
MARK_SIZE=680            # size of the logo mark inside the square
BASE_SIZE=1024
CORNER_RADIUS=200        # rounded corners for FaceTime-like shape

mkdir -p "$TMP_DIR"

if [ ! -f "$SRC_MARK" ]; then
  echo "Missing $SRC_MARK" >&2
  exit 1
fi

# Resize the mark to a consistent size
sips -Z "$MARK_SIZE" "$SRC_MARK" --out "$TMP_DIR/mark.png" >/dev/null

# Composite mark onto a solid background (no external deps)
BASE_SIZE="$BASE_SIZE" BG_COLOR_HEX="$BG_COLOR_HEX" CORNER_RADIUS="$CORNER_RADIUS" python3 - <<'PY'
import os, struct, zlib
from pathlib import Path

base_size = int(os.environ["BASE_SIZE"])
corner_radius = int(os.environ["CORNER_RADIUS"])
mark_path = Path("/tmp/drmedhat-icon/mark.png")
output_path = Path("/tmp/drmedhat-icon/icon-base.png")

hex_color = os.environ["BG_COLOR_HEX"]
if len(hex_color) != 6:
    raise SystemExit("BG_COLOR_HEX must be 6 hex chars")

bg = tuple(int(hex_color[i:i+2], 16) for i in (0,2,4))

# --- PNG decode helpers ---

def read_png_rgba(path: Path):
    data = path.read_bytes()
    if data[:8] != b"\x89PNG\r\n\x1a\n":
        raise SystemExit("Not PNG")
    o = 8
    width = height = None
    bit_depth = color_type = None
    idat = b""
    while o < len(data):
        length = struct.unpack(">I", data[o:o+4])[0]
        ctype = data[o+4:o+8]
        chunk = data[o+8:o+8+length]
        o = o + 12 + length
        if ctype == b"IHDR":
            width, height, bit_depth, color_type, *_ = struct.unpack(">IIBBBBB", chunk)
        elif ctype == b"IDAT":
            idat += chunk
        elif ctype == b"IEND":
            break
    if bit_depth != 8:
        raise SystemExit(f"Unsupported bit depth {bit_depth}")
    if color_type not in (2, 6):
        raise SystemExit(f"Unsupported color type {color_type}")

    bpp = 3 if color_type == 2 else 4
    raw = zlib.decompress(idat)
    stride = width * bpp

    def paeth(a,b,c):
        p = a + b - c
        pa = abs(p - a)
        pb = abs(p - b)
        pc = abs(p - c)
        if pa <= pb and pa <= pc:
            return a
        if pb <= pc:
            return b
        return c

    pixels = bytearray()
    idx = 0
    prev = bytearray(stride)
    for _y in range(height):
        f = raw[idx]
        idx += 1
        row = bytearray(raw[idx:idx+stride])
        idx += stride
        if f == 1:  # Sub
            for i in range(stride):
                left = row[i-bpp] if i >= bpp else 0
                row[i] = (row[i] + left) & 0xFF
        elif f == 2:  # Up
            for i in range(stride):
                row[i] = (row[i] + prev[i]) & 0xFF
        elif f == 3:  # Avg
            for i in range(stride):
                left = row[i-bpp] if i >= bpp else 0
                up = prev[i]
                row[i] = (row[i] + ((left + up) >> 1)) & 0xFF
        elif f == 4:  # Paeth
            for i in range(stride):
                left = row[i-bpp] if i >= bpp else 0
                up = prev[i]
                up_left = prev[i-bpp] if i >= bpp else 0
                row[i] = (row[i] + paeth(left, up, up_left)) & 0xFF
        elif f != 0:
            raise SystemExit(f"Unsupported filter {f}")
        pixels += row
        prev = row

    # convert to RGBA
    if bpp == 3:
        rgba = bytearray()
        for i in range(0, len(pixels), 3):
            rgba.extend(pixels[i:i+3])
            rgba.append(255)
        return width, height, rgba
    return width, height, pixels


def write_png_rgba(path: Path, width: int, height: int, rgba: bytes):
    # Filter type 0 for each row
    raw = bytearray()
    stride = width * 4
    for y in range(height):
        raw.append(0)
        start = y * stride
        raw.extend(rgba[start:start+stride])
    comp = zlib.compress(raw)

    def chunk(ctype: bytes, payload: bytes):
        return struct.pack(">I", len(payload)) + ctype + payload + struct.pack(">I", zlib.crc32(ctype + payload) & 0xFFFFFFFF)

    ihdr = struct.pack(">IIBBBBB", width, height, 8, 6, 0, 0, 0)
    png = b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", ihdr) + chunk(b"IDAT", comp) + chunk(b"IEND", b"")
    path.write_bytes(png)

# --- composite ---
mark_w, mark_h, mark_rgba = read_png_rgba(mark_path)

# background canvas with rounded corners
canvas = bytearray(base_size * base_size * 4)
radius = max(0, min(corner_radius, base_size // 2))
r2 = radius * radius
for y in range(base_size):
    for x in range(base_size):
        # distance from nearest corner
        dx = min(x, base_size - 1 - x)
        dy = min(y, base_size - 1 - y)
        alpha = 255
        if dx < radius and dy < radius:
            # outside the corner circle -> transparent
            if (dx - radius) ** 2 + (dy - radius) ** 2 > r2:
                alpha = 0
        idx = (y * base_size + x) * 4
        canvas[idx] = bg[0]
        canvas[idx + 1] = bg[1]
        canvas[idx + 2] = bg[2]
        canvas[idx + 3] = alpha

# center mark
xoff = (base_size - mark_w) // 2
yoff = (base_size - mark_h) // 2

for y in range(mark_h):
    for x in range(mark_w):
        mi = (y * mark_w + x) * 4
        sr, sg, sb, sa = mark_rgba[mi:mi+4]
        if sa == 0:
            continue
        di = ((y + yoff) * base_size + (x + xoff)) * 4
        dr, dg, db, da = canvas[di:di+4]
        if da == 0:
            # keep transparent corners
            continue
        inv = 255 - sa
        canvas[di]   = (sr * sa + dr * inv) // 255
        canvas[di+1] = (sg * sa + dg * inv) // 255
        canvas[di+2] = (sb * sa + db * inv) // 255
        canvas[di+3] = 255

write_png_rgba(output_path, base_size, base_size, canvas)
print(f"Wrote {output_path}")
PY

# Build icon sizes
rm -rf "$TMP_DIR/pngs"
mkdir -p "$TMP_DIR/pngs"
for size in 16 32 64 128 256 512 1024; do
  sips -Z $size "$BASE_PNG" --out "$TMP_DIR/pngs/icon_${size}.png" >/dev/null
 done

# Pack into ICNS
python3 - <<'PY'
import struct
from pathlib import Path

sizes = [
    (16, b"icp4"),
    (32, b"icp5"),
    (64, b"icp6"),
    (128, b"ic07"),
    (256, b"ic08"),
    (512, b"ic09"),
    (1024, b"ic10"),
]

src_dir = Path("/tmp/drmedhat-icon/pngs")
chunks = []
for size, code in sizes:
    png_path = src_dir / f"icon_{size}.png"
    data = png_path.read_bytes()
    chunk_len = 8 + len(data)
    chunks.append(code + struct.pack(">I", chunk_len) + data)

icns_body = b"".join(chunks)
file_len = 8 + len(icns_body)
output = b"icns" + struct.pack(">I", file_len) + icns_body

out_path = Path("assets/app-icon.icns")
out_path.write_bytes(output)
print(f"Wrote {out_path} ({out_path.stat().st_size} bytes)")
PY

echo "Icon updated: assets/app-icon.icns"
