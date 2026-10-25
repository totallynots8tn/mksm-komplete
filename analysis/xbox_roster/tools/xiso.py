import struct
ISO=r"C:\Users\Arcade Machine 1\Documents\MKSMK\Mortal Kombat - Shaolin Monks (USA, Europe) (En,Fr,De,Es,It)\Mortal Kombat - Shaolin Monks (USA, Europe) (En,Fr,De,Es,It).iso"
MAGIC=b"MICROSOFT*XBOX*MEDIA"
class XIso:
    def __init__(self,path=ISO):
        self.f=open(path,'rb')
        for base in (0,0x0FD90000,0x18300000,0x02080000):
            self.f.seek(base+0x10000)
            if self.f.read(20)==MAGIC:
                self.base=base;break
        else: raise ValueError('no XDVDFS')
        self.f.seek(self.base+0x10000+20)
        self.root_sec,self.root_size=struct.unpack('<II',self.f.read(8))
        self.files={}
        self._walk(self.root_sec,self.root_size,'')
    def rd(self,sec,off,n):
        self.f.seek(self.base+sec*2048+off); return self.f.read(n)
    def _walk(self,sec,size,prefix):
        if size==0: return
        data=self.rd(sec,0,size)
        seen=set()
        def node(o):
            if o in seen or o*4+14>len(data): return
            seen.add(o)
            l,r,s,sz,attr,nl=struct.unpack_from('<HHIIBB',data,o*4)
            if l==0xFFFF: return
            name=data[o*4+14:o*4+14+nl].decode('latin1')
            if l: node(l)
            path=prefix+name
            if attr&0x10: self._walk(s,sz,path+chr(92))
            else: self.files[path.upper()]=(s,sz)
            if r: node(r)
        node(0)
    def read(self,name,off,n):
        s,sz=self.files[name.upper()]
        n=min(n,sz-off)
        return self.rd(s,off,n)
