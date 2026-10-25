from xt import *
import json,collections
# find every call to assert-like functions; gather preceding push imm32 strings
assert_fns=collections.Counter()
names={}
for tgt,lst in calls().items():
    pass
# generic: for each E8 call, look at the 5 instructions before; if >=3 are push of .rdata strings, record
md=x.md
def pushes_before(a):
    # disassemble window before call
    out=[]
    for back in range(40,0,-1):
        ins=list(md.disasm(text[a-TVA-back:a-TVA],a-back))
        if ins and ins[-1].address+ins[-1].size==a:
            return ins[-6:]
    return []
res=[]
for tgt,lst in calls().items():
    for a,op in lst:
        if op!=0xE8: continue
        ins=pushes_before(a)
        strs=[]
        for i in ins:
            if i.mnemonic=='push' and i.op_str.startswith('0x'):
                v=int(i.op_str,16); s=x.sec_for(v)
                if s and s[0]=='.rdata':
                    c=x.cstr(v,100)
                    if c and all(32<=ord(ch)<127 for ch in c): strs.append(c); continue
            strs.append(None)
        good=[s for s in strs if s]
        if len(good)>=2 and any(s.endswith(('.cpp','.h','.c')) for s in good):
            res.append((a,tgt,strs))
cnt=collections.Counter(t for a,t,s in res)
print('assert targets',[(hex(t),n) for t,n in cnt.most_common(8)])
fn_names=collections.defaultdict(set)
for a,t,strs in res:
    # function name: the string just after the line push, i.e. pushes order: line, func, file, expr, msg
    good=[s for s in strs if s]
    # locate file idx
    for i,s in enumerate(strs):
        if s and s.endswith(('.cpp','.h','.c')):
            fi=i;break
    fname=strs[fi-1] if fi>0 else None
    expr=strs[fi+1] if fi+1<len(strs) else None
    f=fn(a)
    fn_names[f].add((fname,strs[fi]))
out={hex(f):sorted({n for n,_ in v if n}) for f,v in fn_names.items()}
files={hex(f):sorted({fl for _,fl in v}) for f,v in fn_names.items()}
json.dump({'names':out,'files':files},open('fnnames.json','w'),indent=0)
print('functions named',len(out))
