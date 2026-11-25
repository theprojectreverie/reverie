from PIL import Image
from pathlib import Path
d=Path(r"C:\Users\quoth\Documents\Default Project\project-fantasy\assets\royal_gate_isometric_cleaned\garden")
a=Image.open(d/"tree.png").convert("RGBA"); b=Image.open(d/"tree_cutout_v4_review.png").convert("RGBA")
for yy in (165,175,185,195,205,215):
 print(yy,[(xx,a.getpixel((xx,yy)),b.getpixel((xx,yy))[3]) for xx in (90,98,105,110,115,120,125,130,170,175,180,185)])
