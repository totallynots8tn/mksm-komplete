import sys,struct,bisect,re
sys.path.insert(0,r"C:\Users\Arcade Machine 1\Documents\MKSMK\analysis")
from xbe_lib import x
d=x.d
TEXT=[s for s in x.sections if s[0]=='.text'][0]
_,TVA,TVS,TFA,TFS=TEXT
text=d[TFA:TFA+TFS]
targets=sorted(int(l,16) for l in open(r"C:\Users\Arcade Machine 1\Documents\MKSMK\analysis\routine_targets.txt").read().split() if l.strip())
tset=set(targets)
def func_of(va):
    i=bisect.bisect_right(targets,va)-1
    return targets[i] if i>=0 else None
def xref_imm(val):
    """addresses in .text where the 4-byte little-endian value occurs"""
    b=struct.pack('<I',val); out=[]; i=text.find(b)
    while i>=0:
        out.append(TVA+i); i=text.find(b,i+1)
    return out
# build call/jmp graph: E8/E9 rel32
_calls=None
def calls():
    global _calls
    if _calls is None:
        _calls={}
        for i in range(len(text)-5):
            op=text[i]
            if op in (0xE8,0xE9):
                tgt=(TVA+i+5+struct.unpack_from('<i',text,i+1)[0])&0xffffffff
                if TVA<=tgt<TVA+TVS:
                    _calls.setdefault(tgt,[]).append((TVA+i,op))
    return _calls
def thunks_to(real):
    # thunk table entries (jmp rel32) pointing at real
    return [a for a,op in calls().get(real,[]) if op==0xE9 and a<0x16000]
def callers(fn):
    """E8 calls to fn or to any thunk of fn"""
    res=[]
    for t in [fn]+thunks_to(fn):
        for a,op in calls().get(t,[]):
            if op==0xE8: res.append((a,t))
    return res
def real(va): return x.follow(va)
def dis(va,n=40):
    for ins in x.dis(va,n):
        extra=''
        m=re.search(r'0x([0-9a-f]{5,8})',ins.op_str)
        if m:
            v=int(m.group(1),16)
            s=x.sec_for(v)
            if s and s[0] in ('.rdata','.data'):
                c=x.cstr(v,60)
                if len(c)>=3 and all(32<=ord(ch)<127 for ch in c): extra=f'   ; "{c}"'
            if ins.mnemonic in ('call','jmp') and TVA<=v<0x16000:
                extra=f'   ; -> {x.follow(v):#x}'
        print(f'{ins.address:08x}: {ins.mnemonic:7s} {ins.op_str}{extra}')
_fstarts=None
def fstarts():
    global _fstarts
    if _fstarts is None:
        s=set()
        for t,l in calls().items():
            if any(op==0xE8 for a,op in l) or any(a<0x16000 for a,op in l): s.add(t)
        # after int3 padding (>=2 CC) followed by non-CC
        i=0;n=len(text)
        while i<n-2:
            if text[i]==0xCC and text[i+1]==0xCC:
                j=i
                while j<n and text[j]==0xCC: j+=1
                if j<n: s.add(TVA+j)
                i=j
            else: i+=1
        _fstarts=sorted(s)
    return _fstarts
def fn(va):
    fs=fstarts(); i=bisect.bisect_right(fs,va)-1
    return fs[i] if i>=0 else None
def callers2(f):
    return [(a,fn(a)) for a,t in callers(f)]
import json as _j
try: NAMES=_j.load(open(__file__.replace('xt.py','fnnames.json')))['names']
except Exception: NAMES={}
def nm(va):
    v=NAMES.get(hex(va)); return '/'.join(v) if v else ''
def disfn(f,maxn=600):
    fs=fstarts(); nxt=fs[fs.index(f)+1] if f in fs else f+0x400
    # extend past int3-less fallthrough: stop at first ret followed by CC
    n=0
    for ins in x.dis(f,maxn):
        n+=1
        if ins.address>=nxt and text[ins.address-TVA]==0xCC: break
    lst=[i for i in x.dis(f,n) if i.mnemonic!='int3']
    print(f'##### {f:#x} {nm(f)} callers:',' '.join(f'{b:#x}' for a,b in callers2(f)[:10]))
    dis(f,len(lst))
