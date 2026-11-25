from pathlib import Path
from PIL import Image
import numpy as np,cv2
from scipy import ndimage as ndi
root=Path(r"C:\Users\quoth\Documents\Default Project\project-fantasy\assets\royal_gate_isometric_cleaned\garden")
orig=np.asarray(Image.open(root/"tree.png").convert("RGBA")).copy()
prev=np.asarray(Image.open(root/"tree_cutout_candidate_final.png").convert("RGBA")).copy()
rr=orig[:,:,0].astype('int16');gg=orig[:,:,1].astype('int16');bb=orig[:,:,2].astype('int16')
y,x=np.indices(rr.shape)
wood=(rr-bb>28)&(rr-gg>18)&(rr>65)&(gg<180)
# The bark and branches are a large central connected mass; recover tiny dark crevices by morphological close.
wood2=cv2.morphologyEx(wood.astype('uint8'),cv2.MORPH_CLOSE,np.ones((7,7),np.uint8))
wood2=(ndi.binary_fill_holes(wood2)>0)
# Only apply bark cleanup beneath flower crown, and inside central branch/trunk envelope.
roi=((y>=132)&(x>=71)&(x<=207)) 
# preserve texture-bearing flowers while remove flat purple backdrop
gray=cv2.cvtColor(orig[:,:,:3],cv2.COLOR_RGB2GRAY).astype('float32')
m=cv2.blur(gray,(5,5));v=np.sqrt(np.maximum(0,cv2.blur(gray*gray,(5,5))-m*m))
flower=(rr>157)&(bb>120)&(v>25)&(rr>gg*1.23)
mask=(y<138)|wood2|flower
mask=np.where(roi,mask,(y<138)|flower|((y>215)&wood2))
# below canopy require original candidate silhouette as well
out=prev.copy();out[:,:,3]=np.where(mask,prev[:,:,3],0)
name=root/"tree_cutout_v2_review.png";Image.fromarray(out).save(name)
for bgcolor,n in [((15,25,34,255),"dark"),((29,107,60,255),"grass")]:
 bg=Image.new("RGBA",(out.shape[1],out.shape[0]),bgcolor);bg.alpha_composite(Image.fromarray(out))
 bg.resize((825,810),Image.Resampling.NEAREST).convert("RGB").save(root/f"tree_cutout_v2_{n}.png")
print('saved',name,'retained',np.count_nonzero(out[:,:,3]))
