from pathlib import Path
from PIL import Image
import numpy as np
root=Path(r"C:\Users\quoth\Documents\Default Project\project-fantasy\assets\royal_gate_isometric_cleaned\garden")
a=np.array(Image.open(root/"tree_cutout_v5_review.png").convert("RGBA"))
y,x=np.indices(a.shape[:2])
r=a[:,:,0].astype(int);g=a[:,:,1].astype(int);b=a[:,:,2].astype(int)
# Small isolated rectangular matte beside the inner right trunk
flat=(x>=155)&(x<=172)&(y>=181)&(y<=220)&(b>93)&(r-b<45)&(r<183)
a[:,:,3][flat]=0
# One detached blossom fragment below the right-hand hanging cluster.
a[:,:,3][(x>=186)&(x<=211)&(y>=208)&(y<=235)]=0
out=root/"tree_cutout_v6_review.png";Image.fromarray(a).save(out)
for color,name in [((15,25,34,255),"dark"),((29,107,60,255),"grass")]:
 bg=Image.new("RGBA",(a.shape[1],a.shape[0]),color);bg.alpha_composite(Image.fromarray(a))
 bg.resize((825,810),Image.Resampling.NEAREST).convert("RGB").save(root/f"tree_cutout_v6_{name}.png")
print(out,"removed",np.count_nonzero(flat))
