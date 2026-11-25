from pathlib import Path
from PIL import Image
import numpy as np,cv2
root=Path(r"C:\Users\quoth\Documents\Default Project\project-fantasy\assets\royal_gate_isometric_cleaned\garden")
a=np.array(Image.open(root/"tree_cutout_v4_review.png").convert("RGBA"))
r=a[:,:,0].astype(int);g=a[:,:,1].astype(int);b=a[:,:,2].astype(int)
y,x=np.indices(r.shape)
# Remove the remaining flat lavender wedges on either side of the bark.
region=(y>=168)&(y<231)&((x<116)|(x>162))&(x>71)&(x<213)
bg=(r<185)&(b>77)&((r-b)<52)
a[:,:,3][region&bg]=0
# Detach stray ground decoration pixels away from the actual root footprint.
a[:,:,3][(y>229)&((x<82)|(x>192))]=0
out=root/"tree_cutout_v5_review.png";Image.fromarray(a).save(out)
for color,name in [((15,25,34,255),"dark"),((29,107,60,255),"grass")]:
 canvas=Image.new("RGBA",(a.shape[1],a.shape[0]),color);canvas.alpha_composite(Image.fromarray(a))
 canvas.resize((825,810),Image.Resampling.NEAREST).convert("RGB").save(root/f"tree_cutout_v5_{name}.png")
print(out)
