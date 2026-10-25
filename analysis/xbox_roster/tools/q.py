import json,re,sys
J=json.load(open('fnnames.json')); n=J['names']; f=J['files']
pat=re.compile(sys.argv[1],re.I)
for k in sorted(n,key=lambda k:int(k,16)):
    files=','.join(p.split(chr(92))[-1] for p in f[k])
    s=' | '.join(n[k])
    if pat.search(s) or pat.search(files): print(k,s[:90],' ',files)
