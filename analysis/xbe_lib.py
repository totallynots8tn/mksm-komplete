import struct
from capstone import Cs, CS_ARCH_X86, CS_MODE_32

class Xbe:
    def __init__(self, path=r"C:\Users\Arcade Machine 1\Documents\MKSMK\default.xbe"):
        self.d=open(path,'rb').read()
        base=struct.unpack_from('<I',self.d,0x104)[0]
        ns=struct.unpack_from('<I',self.d,0x11c)[0]
        sh=struct.unpack_from('<I',self.d,0x120)[0]-base
        self.sections=[]
        for i in range(ns):
            flags,va,vsize,fa,fsize,naddr,ndig=struct.unpack_from('<IIIIIII',self.d,sh+i*0x38)
            noff=naddr-base
            name=self.d[noff:noff+16].split(b'\0')[0].decode('latin1')
            self.sections.append((name,va,vsize,fa,fsize))
        self.md=Cs(CS_ARCH_X86,CS_MODE_32)
        self.md.detail=False
    def sec_for(self,va):
        for s in self.sections:
            if s[1]<=va<s[1]+s[2]: return s
        return None
    def off(self,va):
        s=self.sec_for(va)
        if not s: raise ValueError(f'unmapped {va:08x}')
        name,v,sz,f,fsz=s
        if va-v<fsz: return f+(va-v)
        return None
    def read(self,va,n):
        o=self.off(va)
        if o is None: return b'\0'*n
        return self.d[o:o+n]
    def u32(self,va): return struct.unpack('<I',self.read(va,4))[0]
    def u8(self,va): return self.read(va,1)[0]
    def dis(self,va,count=40,back=0):
        va-=back; o=self.off(va)
        if o is None: return []
        return list(self.md.disasm(self.d[o:o+count*8],va))[:count]
    def print_dis(self,va,count=40,back=0):
        for ins in self.dis(va,count,back):
            print(f'{ins.address:08x}: {ins.mnemonic:8s} {ins.op_str}')
    def follow(self,va):
        # follow jmp thunks up to 4 deep
        for _ in range(4):
            b=self.read(va,5)
            if b and b[0]==0xe9:
                rel=struct.unpack('<i',b[1:5])[0]
                va=va+5+rel
            elif b and b[0]==0xeb:
                va=va+2+struct.unpack('<b',b[1:2])[0]
            else: break
        return va
    def vtable(self,va,n=8):
        out=[]
        for i in range(n):
            p=self.u32(va+4*i)
            if p==0: break
            out.append((p,self.follow(p)))
        return out
    def cstr(self,va,maxlen=200):
        o=self.off(va)
        if o is None: return ''
        e=self.d.find(b'\0',o,o+maxlen)
        return self.d[o:e].decode('latin1','replace')

x=Xbe()
