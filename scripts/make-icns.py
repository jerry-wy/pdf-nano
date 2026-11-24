"""Package the generated PNG representations into a modern ICNS container."""
import pathlib
import struct
import sys

source = pathlib.Path(sys.argv[1])
representations = {
    b'ic08': 'icon_256x256.png',
    b'ic09': 'icon_512x512.png',
    b'ic10': 'icon_512x512@2x.png',
}
chunks = []
def chunk(kind, data):
    return kind + struct.pack('>I', len(data) + 8) + data

# Finder's application-icon decoder scrambles PNG-based icp4/icp5 entries.
# Use Chromium's conservative size layout, without ambiguous @2x entries.
# https://chromium.googlesource.com/chromium/src/+/HEAD/docs/mac/icons.md
for size, kind, mask in [(16, b'is32', b's8mk'), (32, b'il32', b'l8mk'), (128, b'it32', b't8mk')]:
    rgba = (source / f'icon_{size}x{size}.rgba').read_bytes()
    if len(rgba) != size * size * 4:
        raise ValueError(f'Invalid {size}px RGBA icon')
    # it32 has a four-byte prefix before its compressed RGB planes.
    encoded = bytearray(b'\0\0\0\0' if size == 128 else b'')
    for channel in range(3):
        plane = rgba[channel::4]
        for offset in range(0, len(plane), 128):
            run = plane[offset:offset + 128]
            encoded.append(len(run) - 1)
            encoded.extend(run)
    chunks.extend([chunk(kind, encoded), chunk(mask, rgba[3::4])])

for kind, filename in representations.items():
    png = (source / filename).read_bytes()
    chunks.append(chunk(kind, png))
payload = b''.join(chunks)
pathlib.Path(sys.argv[2]).write_bytes(b'icns' + struct.pack('>I', len(payload) + 8) + payload)
