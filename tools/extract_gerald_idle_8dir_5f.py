from PIL import Image
from pathlib import Path
import hashlib, json
src=Image.open(r'C:\Users\quoth\Downloads\gerald_idle_user_reference_8dir_5f_96x128_upload.png').convert('RGBA')
assert src.size==(480,1024), src.size
base=Path(r'C:\Users\quoth\Documents\Default Project\project-fantasy\assets\characters\gerald\generated\gerald_idle_8dir_5f_96x128')
base.mkdir(parents=True,exist_ok=True)
rows=[]
for d in range(8):
    outdir=base/f'idle_{d}'
    outdir.mkdir(exist_ok=True)
    hashes=set()
    alpha_counts=[]
    for f in range(5):
        cell=src.crop((f*96,d*128,(f+1)*96,(d+1)*128))
        alpha=cell.getchannel('A')
        opaque=sum(1 for v in alpha.getdata() if v>10)
        alpha_counts.append(opaque)
        digest=hashlib.sha256(cell.tobytes()).hexdigest()
        hashes.add(digest)
        cell.save(outdir/f'idle_{d}_{f+1:02d}.png',optimize=True)
    assert len(hashes)==5, (d,len(hashes))
    assert min(alpha_counts)>1000, (d,alpha_counts)
    rows.append({'direction':d,'frames':5,'unique':len(hashes),'alpha':alpha_counts})
print(json.dumps({'source_size':src.size,'output':str(base),'rows':rows},indent=2))

