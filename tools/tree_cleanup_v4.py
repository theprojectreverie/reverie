from pathlib import Path
from PIL import Image
import numpy as np,cv2
root=Path(r"C:\Users\quoth\Documents\Default Project\project-fantasy\assets\royal_gate_isometric_cleaned\garden")
a=np.array(Image.open(root/"tree.png").convert("RGBA"))
previous=np.array(Image.open(root/"tree_cutout_v3_review.png").convert("RGBA"))
r=a[:,:,0].astype(int);g=a[:,:,1].astype(int);b=a[:,:,2].astype(int)
yy,xx=np.indices(r.shape)
gray=cv2.cvtColor(a[:,:,:3],cv2.COLOR_RGB2GRAY).astype("float32")
m=cv2.blur(gray,(7,7));v=np.sqrt(np.maximum(0,cv2.blur(gray*gray,(7,7))-m*m))
# Purple filled background is medium/dark, fairly uniform, and blue-heavy relative to amber bark.
patch=(yy>152)&(xx>75)&(xx<210)&(b>108)&(r<183)&((r-b)<39)&(v<28)
# Avoid clipping the flower tips; only remove patch in inner trunk gap.
patch &= ((xx>88)&(xx<194)&(yy>159)&(yy<235))
previous[:,:,3][patch]=0
out=root/"tree_cutout_v4_review.png";Image.fromarray(previous).save(out)
for color,name in [((15,25,34,255),"dark"),((29,107,60,255),"grass")]:
 bg=Image.new("RGBA",(previous.shape[1],previous.shape[0]),color)
 bg.alpha_composite(Image.fromarray(previous))
 bg.resize((825,810),Image.Resampling.NEAREST).convert("RGB").save(root/f"tree_cutout_v4_{name}.png")
print("removed",np.count_nonzero(patch),"review",out)
