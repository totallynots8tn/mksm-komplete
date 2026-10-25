import struct
from xiso import XIso
X=XIso()
hdr=X.read('GAMEDATA.WAD',0,32)
assert hdr[:4]==b'PWF '
COUNT,STRIDE=struct.unpack_from('<II',hdr,12)
TABLE=X.read('GAMEDATA.WAD',32,COUNT*8)
def rec(r):
    a,b=struct.unpack_from('<II',TABLE,r*8)
    if b&0x80000000: return (a&0x1FFFFF)*0x800, ((a>>22)|(b<<10))&0x3FFFFF, True
    return a,b,False
def read(r,n=512):
    off,size,packed=rec(r)
    if not size: return b'',size
    vol,within=divmod(off,STRIDE)
    return X.read('GAMEDATA.WA'+chr(ord('D')+vol),within,min(n,size)),size
def name(r):
    p,size=read(r,512)
    if p[:4]==b'EWDF' and len(p)>=17:
        length,payload,stamp=struct.unpack_from('<III',p,4)
        return p[16:payload-1].decode('ascii','replace'),size,length
    return ('<'+p[:8].hex()+'>' if p else '<empty>'),size,None
import zlib,re
def decoded(r):
    off,size,packed=rec(r)
    p,_=read(r,size)
    if p[:4]!=b'EWDF': return p
    length,payload,stamp=struct.unpack_from('<III',p,4)
    body=p[payload:]
    for wb in (-15,15,31):
        try:
            return zlib.decompressobj(wb).decompress(body)
        except Exception: pass
    return None
def strings(b,minlen=4):
    return [m.group().decode() for m in re.finditer(rb'[\x20-\x7e]{%d,}'%minlen,b)]
