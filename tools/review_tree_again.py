from PIL import Image
from pathlib import Path
folder=Path(r"C:\Users\quoth\Documents\Default Project\project-fantasy\assets\royal_gate_isometric_cleaned\garden")
im=Image.open(folder/"tree_cutout_candidate_final.png").convert("RGBA")
for color,name in [((30,96,61,255),"grass"),((245,244,235,255),"light")]:
 bg=Image.new("RGBA",im.size,color);bg.alpha_composite(im);bg.convert("RGB").resize((im.width*3,im.height*3),Image.Resampling.NEAREST).save(folder/f"tree_candidate_{name}_3x.png")
print("image size",im.size)
