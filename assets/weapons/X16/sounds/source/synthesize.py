"""Original X16/OpenSRS procedural sound design. No sample or recording inputs.
SPDX-License-Identifier: CC-BY-4.0
Rebuild: python synthesize.py (NumPy, SciPy, SoundFile).
"""
from pathlib import Path
import json, hashlib, math
import numpy as np
import scipy
from scipy import signal
import soundfile as sf

ROOT=Path(__file__).resolve().parents[1]
FS=48000
TARGET=10**(-1.0/20)
RENDER={}
DETAIL={}
def nsec(d): return int(round(d*FS))
def timeline(d): return np.arange(nsec(d),dtype=np.float64)/FS

def filtered_noise(rng,d,lo=100,hi=14000,order=2):
    x=rng.normal(0,1,nsec(d)+2048)
    sos=signal.butter(order,[lo,hi],btype='bandpass',fs=FS,output='sos')
    x=signal.sosfilt(sos,x)[2048:]
    return x/max(np.std(x),1e-9)

def put(out,x,at=0,level=1):
    k=nsec(at);end=min(len(out),k+len(x))
    if end>k:out[k:end]+=x[:end-k]*level

def modes(rng,d,frequencies,decays,weights=None,attack=.00012,rough=.003):
    t=timeline(d);out=np.zeros_like(t)
    if weights is None:weights=np.ones(len(frequencies))
    for f,decay,w in zip(frequencies,decays,weights):
        # Inharmonic short-lived structural modes; small nonperiodic frequency wander.
        drift=np.interp(t,np.linspace(0,d,17),rng.normal(0,rough,17))
        phase=2*np.pi*np.cumsum(f*(1+drift))/FS
        out+=w*np.sin(phase)*np.exp(-t/decay)
    return out*(1-np.exp(-t/attack))/max(np.sqrt(np.sum(np.array(weights)**2)),1)

def contact(rng,d=.06,weight=1,steel=.5):
    t=timeline(d)
    # Broad noisy contact transient plus heavily damped, non-harmonic body vibration.
    crack=filtered_noise(rng,d,650,15500)*(1-np.exp(-t/.000045))*np.exp(-t/(.00065+.0015*weight))
    body=filtered_noise(rng,d,170,3800)*(1-np.exp(-t/.00010))*np.exp(-t/(.0017+.0038*weight))
    freq=np.array([578,1377,2581,4129,6737])*rng.uniform(.91,1.09,5)
    ring=modes(rng,d,freq,[.006,.009,.006,.005,.003],[.9,.62,.38,.25,.12])
    return .66*body+.40*crack+steel*.55*ring

def friction(rng,d,lo=300,hi=11000,grains=45):
    t=timeline(d);out=filtered_noise(rng,d,lo,hi)*.2
    for at in rng.uniform(0,max(.001,d-.008),grains):
        put(out,contact(rng,.013,.13,.12),at,rng.uniform(.04,.22))
    # Irregular pressure; gradual engagement/release, no periodic scraping loop.
    knots=rng.uniform(.25,1,16)
    env=np.interp(t,np.linspace(0,d,16),knots)*np.sin(np.pi*np.minimum(t/d,1))**.65
    return out*env

def gunshot(seed,variation):
    rng=np.random.default_rng(seed);d=.72;t=timeline(d);x=np.zeros_like(t)
    v=rng.uniform(.93,1.07)
    # Analytic bipolar pressure front, not a pitched oscillator.
    a=.00024*v;b=.00105*v
    front=(np.exp(-t/a)-(a/b)*np.exp(-t/b))*(1-np.exp(-t/.000022))
    put(x,front,0,2.20)
    crack=filtered_noise(rng,d,1400,19000,2)
    crack*=np.exp(-t/(.0011*v))+.19*np.exp(-t/.0042)
    crack*=1-np.exp(-t/.000025)
    x+=.43*crack
    gas=filtered_noise(rng,d,180,7600,2)
    gas*=((1-np.exp(-t/.00025))*np.exp(-t/(.012*v)))
    x+=.58*gas
    chest=filtered_noise(rng,d,100,1250,2)
    chest*=(1-np.exp(-t/.00035))*np.exp(-t/(.021*v))
    x+=.34*chest
    # A few unresolved pressure discontinuities, not rapid-fire echoes.
    for at,amp in [(.0016,.22),(.0038,.11),(.0071,.075)]:
        put(x,contact(rng,.024,.55,.05),at*rng.uniform(.9,1.1),amp)
    # Muted action cycle, mainly relevant in the tail rather than a metallic ping.
    put(x,contact(rng,.040,.75,.24),.025*rng.uniform(.94,1.06),.032)
    put(x,contact(rng,.042,.88,.27),.063*rng.uniform(.94,1.06),.040)
    dry=x.copy()
    # Original algorithmic outdoor scattering; every tap has independent filtering.
    # Small early reflections merge into an unpitched decay. No sampled IRs.
    for j,at in enumerate([.012,.023,.039,.061,.088,.123,.171,.228]):
        at*=rng.uniform(.91,1.09)
        refl=signal.sosfilt(signal.butter(2,[180,6500/(1+j*.27)],btype='bandpass',fs=FS,output='sos'),dry[:nsec(.072)])
        put(x,refl,at,rng.uniform(.032,.055)*math.exp(-at/.11))
    scatter=filtered_noise(rng,d,260,4400)
    env=(1-np.exp(-t/.018))*np.exp(-t/.070)
    texture=np.interp(t,np.linspace(0,d,80),rng.uniform(.35,1.1,80))
    x+=scatter*env*texture*.037
    return x

def mechanical(kind,seed):
    rng=np.random.default_rng(seed)
    lengths={'dry_fire':.13,'magazine_release':.18,'magazine_insert':.26,'slide_pull_back':.27,'slide_forward':.19}
    x=np.zeros(nsec(lengths[kind]))
    if kind=='dry_fire':
        put(x,contact(rng,.055,.38,.38),0,.72)
        put(x,contact(rng,.035,.12,.15),.0035,.20)
        put(x,modes(rng,.07,[490,1730,3680],[.008,.009,.004],[1,.3,.18]),.001,.17)
    elif kind=='magazine_release':
        put(x,contact(rng,.04,.22,.13),0,.53)
        put(x,contact(rng,.05,.42,.24),.012,.72)
        put(x,friction(rng,.068,340,8500,22),.023,.16)
        put(x,contact(rng,.04,.25,.08),.049,.14)
    elif kind=='magazine_insert':
        put(x,contact(rng,.04,.28,.05),0,.16)
        put(x,friction(rng,.078,230,8500,48),.001,.22)
        put(x,contact(rng,.085,1.28,.16),.080,1.0)
        put(x,contact(rng,.035,.30,.42),.087,.24)
        put(x,contact(rng,.05,.39,.12),.101,.14)
    elif kind=='slide_pull_back':
        put(x,contact(rng,.045,.45,.50),0,.40)
        put(x,friction(rng,.121,430,13000,63),.004,.40)
        # Quiet spring/rail response is a damped broadband structure, no boing.
        put(x,modes(rng,.12,[1021,1837,3283,5879],[.027,.020,.014,.008],[.2,.38,.3,.12]),.018,.055)
        put(x,contact(rng,.074,.94,.69),.131,1.0)
        put(x,contact(rng,.045,.25,.37),.135,.25)
        put(x,contact(rng,.040,.21,.24),.148,.08)
    elif kind=='slide_forward':
        put(x,contact(rng,.027,.24,.43),0,.16)
        put(x,friction(rng,.030,650,14500,33),.0004,.26)
        put(x,contact(rng,.085,1.14,.66),.034,1.0)
        put(x,contact(rng,.047,.53,.40),.0367,.48)
        put(x,contact(rng,.030,.20,.38),.044,.10)
    return x

def impact(kind,seed):
    rng=np.random.default_rng(seed)
    if kind=='concrete':
        d=.26;t=timeline(d)
        x=filtered_noise(rng,d,900,16500)*(1-np.exp(-t/.00004))*np.exp(-t/.0017)*.8
        x+=filtered_noise(rng,d,260,7200)*(1-np.exp(-t/.0001))*np.exp(-t/.008)*.8
        x+=modes(rng,d,[423,919,1907,3563],[.011,.009,.006,.004],[.6,.4,.3,.15])*.25
        for at in [.012,.027,.041,.071,.103]:put(x,contact(rng,.032,.10,.03),at,rng.uniform(.035,.095))
        x+=filtered_noise(rng,d,1700,10500)*(1-np.exp(-t/.006))*np.exp(-t/.029)*.07
    else:
        d=.20;t=timeline(d)
        # Dense damped mass plus fabric snap. No voice, scream or exaggerated gore.
        x=filtered_noise(rng,d,80,1150)*(1-np.exp(-t/.00014))*np.exp(-t/.010)*.90
        x+=filtered_noise(rng,d,700,6800)*(1-np.exp(-t/.000035))*np.exp(-t/.0020)*.43
        x+=friction(rng,d,350,3800,9)*np.exp(-t/.018)*.10
        put(x,contact(rng,.040,.65,.0),.0038,.20)
    return x

def extras():
    rng=np.random.default_rng(73191);out={}
    # Distant version derives exclusively from our synthesized near shot.
    x=gunshot(2027,1)
    x=signal.sosfilt(signal.butter(3,[180,2600],fs=FS,btype='bandpass',output='sos'),x)
    y=np.zeros(nsec(.95));put(y,x)
    for t,g in [(.038,.17),(.082,.12),(.137,.06)]:put(y,x,t,g)
    out['gunshot_distant']=y
    t=timeline(.20)
    env=np.exp(-((t-.067)/.040)**2)
    # Moving broad spectral resonance, with no sinusoidal whistle.
    carrier=filtered_noise(rng,.20,1800,14500)
    b1=signal.sosfilt(signal.butter(2,[3400,11500],fs=FS,btype='bandpass',output='sos'),carrier)
    b2=signal.sosfilt(signal.butter(2,[1000,5400],fs=FS,btype='bandpass',output='sos'),carrier)
    mix=1/(1+np.exp(-(t-.060)/.009))
    y=((1-mix)*b1+mix*b2)*env*.65
    put(y,contact(rng,.035,.08,.0),.058,.09)
    out['near_miss_whiz']=y
    y=np.zeros(nsec(.30));put(y,friction(rng,.205,220,6800,65),0,.43)
    put(y,contact(rng,.053,.53,.12),0,.17);put(y,contact(rng,.05,.24,.10),.17,.10)
    out['draw_rustle']=y
    y=np.zeros(nsec(.57));put(y,contact(rng,.10,1.5,.22),0,1.0)
    for at,g in [(.054,.43),(.137,.24),(.193,.13),(.229,.07)]:put(y,contact(rng,.055,.8,.21),at,g)
    put(y,friction(rng,.17,650,10500,46),.22,.10)
    out['magazine_floor']=y
    y=np.zeros(nsec(.53))
    for at,g in [(0,1),(.063,.48),(.123,.25),(.163,.15),(.187,.08)]:
        sound=modes(rng,.13,[2873,4861,7387,10429],[.027,.041,.026,.013],[.42,1,.45,.22],rough=.001)
        sound+=contact(rng,.13,.07,.12)*.25
        put(y,sound,at,g)
    out['casing_tinkle']=y
    return out

def finish(x,name):
    # Remove subsonic/DC energy, then trim and use sub-millisecond zero-origin ramps.
    x=signal.sosfilt(signal.butter(2,38 if 'gunshot' in name else 65,fs=FS,btype='highpass',output='sos'),x)
    threshold=max(abs(x))*10**(-78/20)
    hot=np.flatnonzero(abs(x)>threshold)
    x=x[max(0,hot[0]-1):min(len(x),hot[-1]+nsec(.006))].copy()
    edge=min(5,len(x));x[:edge]*=np.linspace(0,1,edge)
    end=min(nsec(.008),len(x)//6);x[-end:]*=np.linspace(1,0,end)**1.5
    # Four-times oversampled peak normalization leaves true-peak headroom.
    peak=np.max(abs(signal.resample_poly(x,4,1)))
    x*=TARGET/peak
    # 24-bit PCM TPDF dither at one least-significant-bit scale.
    rng=np.random.default_rng(int(hashlib.sha256(name.encode()).hexdigest()[:8],16))
    x+=(rng.random(len(x))-rng.random(len(x)))/(2**23)
    x[0]=0;x[-1]=0
    sf.write(ROOT/(name+'.wav'),x,FS,subtype='PCM_24')
    RENDER[name]=x

for i in range(1,4):finish(gunshot(2026+i*177,i),f'X16_Gunshot_0{i}')
for i,k in enumerate(['dry_fire','magazine_release','magazine_insert','slide_pull_back','slide_forward']):
    finish(mechanical(k,6100+319*i),'X16_'+''.join(w.title() for w in k.split('_')))
finish(impact('concrete',88502),'X16_Impact_Concrete')
finish(impact('body',99640),'X16_Impact_Body')
rng=np.random.default_rng(44583);t=timeline(.047)
tick=filtered_noise(rng,.047,1700,11800)*(1-np.exp(-t/.000025))*np.exp(-t/.0007)
tick+=modes(rng,.047,[2371,5131],[.0024,.0012],[.20,.16])*.19
finish(tick,'X16_HitMarker_Tick')
for k,x in extras().items():finish(x,'X16_'+''.join(w.title() for w in k.split('_')))

# Mechanical assets are peak-normalized for interchange, not equal-volume mixing.
gains={'X16_Gunshot_01':-8,'X16_Gunshot_02':-8,'X16_Gunshot_03':-8,
'X16_DryFire':-18,'X16_MagazineRelease':-20,'X16_MagazineInsert':-16,
'X16_SlidePullBack':-15,'X16_SlideForward':-14,'X16_Impact_Concrete':-15,
'X16_Impact_Body':-17,'X16_HitMarker_Tick':-23,'X16_GunshotDistant':-23,
'X16_NearMissWhiz':-18,'X16_DrawRustle':-24,'X16_MagazineFloor':-20,'X16_CasingTinkle':-27}
review=np.zeros(nsec(18));cursor=0;cue=[]
for name,x in RENDER.items():
    put(review,x,cursor,10**(gains[name]/20));cue.append({'start_seconds':round(cursor,3),'file':name+'.wav','preview_gain_db':gains[name]})
    cursor+=len(x)/FS+.48
review=review[:nsec(cursor)]
sf.write(ROOT/'preview'/'X16_Audition_Reel.wav',review,FS,subtype='PCM_24')
(ROOT/'preview'/'CUE_SHEET.json').write_text(json.dumps(cue,indent=2))
(ROOT/'source'/'requirements.txt').write_text(f'numpy=={np.__version__}\nscipy=={scipy.__version__}\nsoundfile=={sf.__version__}\n')
print('Created',len(RENDER),'individual sound assets and audition reel.')
