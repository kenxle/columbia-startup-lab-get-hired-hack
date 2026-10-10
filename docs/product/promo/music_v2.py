import numpy as np, wave
SR=44100; T=30.0; N=int(SR*T); t=np.arange(N)/SR
out=np.zeros((N,2))
def hz(m): return 440*2**((m-69)/12)
def env(n,a,r):
    e=np.ones(n); a=int(a*SR); r=int(r*SR)
    e[:a]=np.linspace(0,1,a); e[-r:]*=np.linspace(1,0,r); return e
def lp(x,c):
    y=np.zeros_like(x); s=0.0; c=np.broadcast_to(c,x.shape)
    for i in range(len(x)): s+=c[i]*(x[i]-s); y[i]=s
    return y
BEAT=0.6; BAR=2.4
# chords (midi): Dm, Bb, F, C, Dm, Bb, then F to end
# v2: beat lands on shot 5 (16.5 s), final chord on shot 9 (25.5 s)
SOL=16.5; END=25.5
prog=[(0,[50,57,62,65]),(4.8,[46,53,58,62]),(9.6,[53,57,60,65]),(14.4,[48,55,60,64]),
      (SOL,[50,57,62,65,69]),(19.5,[46,53,58,62,65]),(22.5,[48,55,60,64,67]),(END,[41,53,57,60,65,69])]
for i,(st,notes) in enumerate(prog):
    en = prog[i+1][0] if i+1<len(prog) else T
    n=int((en-st+0.8)*SR); s0=int(st*SR); n=min(n,N-s0); tt=np.arange(n)/SR
    sig=np.zeros(n)
    for m in notes:
        for d in (-0.06,0.06):
            f=hz(m)*(1+d/100*3)
            sig+=np.sin(2*np.pi*f*tt)+0.35*np.sin(4*np.pi*f*tt)+0.12*np.sin(6*np.pi*f*tt)
    rel = 3.5 if st==END else 0.9
    sig*=env(n,0.9 if st<25 else 0.4,min(rel,n/SR*0.5))/len(notes)
    out[s0:s0+n,0]+=sig*0.9; out[s0:s0+n,1]+=np.roll(sig,90)*0.9
# bass pulse on eighths (root), up to the final chord
roots={0:38,4.8:34,9.6:41,14.4:36,SOL:38,19.5:34,22.5:36}
keys=sorted(roots)
k=0.0
while k<END-0.2:
    r=[roots[x] for x in keys if x<=k+1e-9][-1]
    n=int(0.28*SR); s0=int(k*SR); tt=np.arange(n)/SR
    b=np.sin(2*np.pi*hz(r)*tt)*np.exp(-tt*9)*0.55
    vol=0.6 if k<SOL else 0.85
    out[s0:s0+n]+=(b*vol)[:,None]
    k+=BEAT/2
# hats + soft kick in solution section
rng=np.random.default_rng(3)
k=SOL
while k<END-0.1:
    n=int(0.05*SR); s0=int(k*SR)
    h=rng.standard_normal(n); h=h-lp(h,0.3); h*=np.exp(-np.arange(n)/SR*90)*0.12
    out[s0:s0+n,0]+=h*0.8; out[s0:s0+n,1]+=h
    if abs((k-SOL)/BEAT - round((k-SOL)/BEAT))<1e-6 and round((k-SOL)/BEAT)%2==0:
        m=int(0.25*SR); tt=np.arange(m)/SR
        kick=np.sin(2*np.pi*(55+70*np.exp(-tt*30))*tt)*np.exp(-tt*12)*0.5
        out[s0:s0+m]+=kick[:,None]
    k+=BEAT/2
# riser into shot 5
s0=int((SOL-1.8)*SR); n=int(1.8*SR); tt=np.arange(n)/SR
nz=rng.standard_normal(n); nz=lp(nz,0.05+0.25*tt/tt[-1])*(tt/tt[-1])**2*0.35
out[s0:s0+n]+=nz[:,None]
# fades and normalize
out[:int(0.6*SR)]*=np.linspace(0,1,int(0.6*SR))[:,None]
out[-int(1.5*SR):]*=np.linspace(1,0,int(1.5*SR))[:,None]
out/=np.abs(out).max()/0.85
w=wave.open('audio/music_v2.wav','wb'); w.setnchannels(2); w.setsampwidth(2); w.setframerate(SR)
w.writeframes((out*32767).astype('<i2').tobytes()); w.close()
