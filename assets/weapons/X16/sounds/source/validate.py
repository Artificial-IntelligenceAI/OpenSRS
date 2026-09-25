from pathlib import Path
import json,hashlib
import numpy as np
from scipy import signal
import soundfile as sf
R=Path(__file__).resolve().parents[1]
required=['X16_Gunshot_01','X16_Gunshot_02','X16_Gunshot_03','X16_DryFire','X16_MagazineRelease','X16_MagazineInsert','X16_SlidePullBack','X16_SlideForward','X16_Impact_Concrete','X16_Impact_Body','X16_HitMarker_Tick']
report={'sample_rate_hz':48000,'required_sound_types':9,'required_wav_files':11,'all_required_present':True,'subjective_listening_status':'Pending: this session does not support audio input. No listening or realism sign-off is claimed.','checks':{}}
for name in required:assert (R/(name+'.wav')).is_file(),name
for p in sorted(R.glob('*.wav')):
 x,sr=sf.read(p,dtype='float64');info=sf.info(p)
 assert sr==48000 and x.ndim==1 and info.subtype=='PCM_24'
 assert np.isfinite(x).all()
 peak=float(np.max(np.abs(x)));true=float(np.max(np.abs(signal.resample_poly(x,8,1))))
 clips=int(np.sum(np.abs(x)>=(1-1/2**23)))
 assert clips==0 and true<.92,(p.name,true)
 assert abs(20*np.log10(true)+1)<.12,(p.name,true)
 first=int(np.flatnonzero(np.abs(x)>1e-7)[0]);last=int(np.flatnonzero(np.abs(x)>1e-7)[-1])
 assert first<12 and len(x)-1-last<12,(p.name,first,last)
 # Digital silence and DC/signal checks, not a claim of perceptual realism.
 dc=float(abs(np.mean(x)));assert dc<.003
 bands={}
 short=x[:min(len(x),4800)]
 f,P=signal.welch(short,fs=sr,nperseg=min(1024,len(short)))
 for lo,hi in [(40,200),(200,1000),(1000,5000),(5000,20000)]:
  bands[f'{lo}-{hi}_Hz_percent']=round(float(P[(f>=lo)&(f<hi)].sum()/max(P.sum(),1e-20)*100),2)
 report['checks'][p.name]={'duration_seconds':round(len(x)/sr,5),'sample_rate_hz':sr,'channels':info.channels,'encoding':info.subtype,'sample_peak_dbfs':round(20*np.log10(peak),3),'true_peak_dbtp_8x':round(20*np.log10(true),3),'clipped_samples':clips,'leading_zero_samples':first,'dc_offset':round(dc,9),'first_100ms_spectral_energy':bands,'sha256':hashlib.sha256(p.read_bytes()).hexdigest()}
# Variants are genuinely different renders rather than three renamed copies.
shots=[sf.read(R/(n+'.wav'))[0] for n in required[:3]]
cor=[]
for i in range(3):
 for j in range(i+1,3):
  c=float(np.corrcoef(shots[i][:4800],shots[j][:4800])[0,1]);cor.append(round(c,4));assert abs(c)<.9
report['gunshot_variation_correlations_first_100ms']=cor
report['asset_count']=len(report['checks']);report['technical_validation_passed']=True
(R/'VALIDATION.json').write_text(json.dumps(report,indent=2))
for n,a in report['checks'].items():print(n,a['duration_seconds'],a['sample_peak_dbfs'],a['true_peak_dbtp_8x'],a['first_100ms_spectral_energy'])
print('PASS: required assets, encoding, peaks, trimming, DC, finite samples, distinct variants.')
