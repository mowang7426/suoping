"""Portable Mach-O deployment and jailbreak dependency inspection."""
import struct

def macho_slices(data):
    magic=struct.unpack_from('>I',data)[0]
    if magic in (0xcafebabe,0xcafebabf):
        count=struct.unpack_from('>I',data,4)[0]
        size=32 if magic==0xcafebabf else 20
        for i in range(count):
            pos=8+i*size
            off,length=struct.unpack_from('>QQ' if size==32 else '>II',data,pos+8)
            yield data[off:off+length]
    else:
        yield data

def inspect_macho(data,rootless=False):
    reports=[]
    for part in macho_slices(data):
        assert part[:4]==b'\xcf\xfa\xed\xfe', 'expected little-endian 64-bit Mach-O'
        cpu=struct.unpack_from('<I',part,4)[0]
        assert cpu==0x100000c, 'expected arm64/arm64e'
        ncmds=struct.unpack_from('<I',part,16)[0]
        pos=32; minimum=None; deps=[]; rpaths=[]
        for _ in range(ncmds):
            cmd,size=struct.unpack_from('<II',part,pos)
            assert size>=8 and pos+size<=len(part)
            if cmd==0x32:
                platform,minimum=struct.unpack_from('<II',part,pos+8)
                assert platform==2, 'non-iOS platform'
            elif cmd==0x25:
                minimum=struct.unpack_from('<I',part,pos+8)[0]
            elif cmd in (0xc,0x18|0x80000000,0x1f|0x80000000,0x8000001c):
                offset=struct.unpack_from('<I',part,pos+8)[0]
                text=part[pos+offset:pos+size].split(b'\0')[0].decode()
                (rpaths if cmd==0x8000001c else deps).append(text)
            pos+=size
        assert minimum==0x000f0000, f'deployment must be iOS15.0, got {minimum!r}'
        assert minimum<=0x000f0001, 'iOS15.0.1 unsupported'
        if rootless:
            for dep in deps:
                assert not dep.startswith(('/Library/','/usr/lib/libsubstrate','/usr/lib/libhooker')), dep
            if any(d.startswith('@rpath/') for d in deps):
                assert any(p.startswith('/var/jb/') or p.startswith('@loader_path') for p in rpaths), rpaths
        reports.append({'minimum':'15.0','dependencies':deps,'rpaths':rpaths})
    assert reports
    return reports
