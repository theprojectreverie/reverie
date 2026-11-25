from pathlib import Path
from PIL import Image
import numpy as np,cv2
from scipy import ndimage as ndi
root=Path(r"C:\Users\quoth\Documents\Default Project\project-fantasy\assets\royal_gate_isometric_cleaned\garden")
orig=np.asarray(Image.open(root/"tree.png").convert("RGBA")).copy()
prev=np.asarray(Image.open(root/"tree_cutout_candidate_final.png").convert("RGBA")).copy()
r=orig[:,:,0].astype('int16');g=orig[:,:,1].astype('int16');b=orig[:,:,2].astype('int16')
y,x=np.indices(r.shape)
gr=cv2.cvtColor(orig[:,:,:3],cv2.COLOR_RGB2GRAY).astype('float32')
m=cv2.blur(gr,(5,5));v=np.sqrt(np.maximum(0,cv2.blur(gr*gr,(5,5))-m*m))
wood=(r-b>30)&(r-g>18)&(g<175)&(r>55)
# Flowering clusters have saturated bright highlights or detailed violet petals.
petals=((r>175)&(b>148)&(v>10))|((b>r+8)&(r>75)&(v>14))
# Trunk interior should remain connected without capturing surrounding purple background.
core=(x>115)&(x<168)&(y>160)&(y<246)
bark=wood|(core & (r-b>12))
outline=(y<151)|petals|bark
# Preserve only pixels already in first cutout and remove detached petal flecks.
a=(outline & (prev[:,:,3]>0)).astype('uint8')
n,cc,stats,_=cv2.connectedComponentsWithStats(a,8)
for i in range(1,n):
 if stats[i,cv2.CC_STAT_AREA]<5:a[cc==i]=0
out=prev.copy();out[:,:,3]=a*255
name=root/"tree_cutout_v3_review.png";Image.fromarray(out).save(name)
for color,n in [((14,24,34,255),"dark"),((29,107,60,255),"grass")]:
 bg=Image.new("RGBA",(out.shape[1],out.shape[0]),color);bg.alpha_composite(Image.fromarray(out))
 bg.resize((825,810),Image.Resampling.NEAREST).convert("RGB").save(root/f"tree_cutout_v3_{n}.png")
print('saved',name)
