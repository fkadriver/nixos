# Repair non-PIE ELF64 binaries mangled by patchelf (seen on vmware-workstation's
# vmnet-natd): patchelf added a LOAD at the file start that is too short to cover
# the PHDR/INTERP/NOTE segments, and moved .dynamic into a read-only LOAD. glibc
# >= 2.43's loader reads those notes from memory and writes DT_DEBUG into
# .dynamic, so the binary SEGVs in dl_main before main(). Fix both in place.
import struct, sys
PT_LOAD, PT_DYNAMIC, PT_INTERP, PT_NOTE, PT_PHDR = 1, 2, 3, 4, 6
PF_W = 2
path = sys.argv[1]
b = bytearray(open(path, 'rb').read())
assert b[:4] == b'\x7fELF' and b[4] == 2, "ELF64 only"
phoff, = struct.unpack_from('<Q', b, 0x20)
phentsize, phnum = struct.unpack_from('<HH', b, 0x36)
off = lambda i: phoff + i * phentsize
ph = [list(struct.unpack_from('<IIQQQQQQ', b, off(i))) for i in range(phnum)]
# fields: 0 type, 1 flags, 2 offset, 3 vaddr, 4 paddr, 5 filesz, 6 memsz, 7 align
loads = [i for i, p in enumerate(ph) if p[0] == PT_LOAD]
changed = False

# 1. LOAD holding the program header table must cover PHDR/INTERP/NOTEs after it.
first = min(loads, key=lambda i: ph[i][2])
L = ph[first]
end = max(p[2] + p[5] for p in ph if p[0] in (PT_PHDR, PT_INTERP, PT_NOTE) and p[2] < 0x1000)
need = end - L[2]
if L[5] < need:
    nxt = min(ph[i][3] for i in loads if ph[i][3] > L[3])
    assert L[3] + need <= nxt and L[3] + need <= (L[3] & ~0xfff) + 0x1000, "unsafe growth"
    print(f"LOAD[{first}] size {L[5]:#x} -> {need:#x}")
    struct.pack_into('<QQ', b, off(first) + 0x20, need, need)
    changed = True

# 2. LOAD containing PT_DYNAMIC must be writable (ld.so writes DT_DEBUG).
dyn = next(p for p in ph if p[0] == PT_DYNAMIC)
for i in loads:
    p = ph[i]
    if p[3] <= dyn[3] < p[3] + p[6] and not p[1] & PF_W:
        print(f"LOAD[{i}] holding .dynamic: flags {p[1]:#x} -> {p[1] | PF_W:#x}")
        struct.pack_into('<I', b, off(i) + 4, p[1] | PF_W)
        changed = True

if changed:
    open(path, 'wb').write(b)
else:
    print("nothing to fix")
