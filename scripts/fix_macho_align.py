#!/usr/bin/env python3
"""8-align the LINKEDIT string table of a thin arm64 Mach-O so the macOS 26/27
beta dyld accepts it ("mis-aligned LINKEDIT string pool").

The beta `codesign -f -s -` re-lays-out LINKEDIT, so checking alignment before
signing is unreliable. Instead: strip the signature to get an unsigned base,
then for pad in 0..15 build a candidate (pad zero bytes inserted before the
string table), AD-HOC SIGN IT, and re-read the *signed* stroff — keep the first
pad whose signed file is 8-aligned. No-op (just ensure signed) if pad=0 works."""
import sys, struct, subprocess

LC_SYMTAB = 0x2
LC_SEGMENT_64 = 0x19
MH_MAGIC_64 = 0xFEEDFACF

def parse(data):
    magic, = struct.unpack_from("<I", data, 0)
    if magic != MH_MAGIC_64:
        return None
    ncmds, = struct.unpack_from("<I", data, 16)
    off = 32; symtab_off = None; linkedit_off = None
    for _ in range(ncmds):
        cmd, cmdsize = struct.unpack_from("<II", data, off)
        if cmd == LC_SYMTAB:
            symtab_off = off
        elif cmd == LC_SEGMENT_64:
            if data[off+8:off+24].split(b"\0")[0] == b"__LINKEDIT":
                linkedit_off = off
        off += cmdsize
    return symtab_off, linkedit_off

def signed_stroff(path):
    data = open(path, "rb").read()
    p = parse(bytearray(data))
    if not p: return None
    so, _ = p
    stroff, = struct.unpack_from("<I", data, so+16)
    return stroff

def sign(path):
    subprocess.run(["codesign", "-f", "-s", "-", path],
                   stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)

def patch(path):
    # No "already aligned" fast-path: the toolchain re-signs the dylib AFTER the
    # linker returns, which re-lays-out LINKEDIT and can shift stroff off an
    # 8-boundary even when it looked aligned here. Returning early without
    # re-signing left such files to be re-signed later into a mis-aligned state.
    # So always run the pad search below — it ends by AD-HOC SIGNING the file in
    # an 8-aligned layout, which a subsequent identical `codesign -f -s -` keeps.
    s = signed_stroff(path)
    if s is None:
        return "skip (not thin arm64 macho)"
    # Unsigned base.
    subprocess.run(["codesign", "--remove-signature", path],
                   stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    base = bytearray(open(path, "rb").read())
    p = parse(base)
    if not p:
        sign(path); return "skip (parse fail)"
    so, le = p
    U, strsize = struct.unpack_from("<II", base, so+16)
    lbase = le + 8 + 16
    vmsize, = struct.unpack_from("<Q", base, lbase+8)
    filesize, = struct.unpack_from("<Q", base, lbase+24)
    for pad in range(0, 16):
        cand = bytearray(base)
        cand[U:U] = b"\0" * pad
        struct.pack_into("<I", cand, so+16, U + pad)
        nf = filesize + pad
        if nf > vmsize:
            struct.pack_into("<Q", cand, lbase+8, (nf + 0x3FFF) & ~0x3FFF)
        struct.pack_into("<Q", cand, lbase+24, nf)
        open(path, "wb").write(cand)
        sign(path)
        if (signed_stroff(path) or 1) % 8 == 0:
            return f"aligned (pad={pad})"
    return "FAILED to align"

if __name__ == "__main__":
    print(patch(sys.argv[1]))
