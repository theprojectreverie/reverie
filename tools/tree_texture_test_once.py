from PIL import Image
import cv2,numpy as np
p=r"C:\Users\quoth\Documents\Default Project\project-fantasy\assets\royal_gate_isometric_cleaned\garden\tree.png"
a=np.array(Image.open(p).convert("RGB")).astype(np.float32)
gray=cv2.cvtColor(a.astype('uint8'),cv2.COLOR_RGB2GRAY).astype(np.float32)
m=cv2.blur(gray,(7,7));v=np.sqrt(np.maximum(0,cv2.blur(gray*gray,(7,7))-m*m))
for x,y in [(10,100),(130,200),(70,200),(90,210),(210,210),(100,190),(130,230),(150,170),(40,180),(220,180),(60,100),(135,70),(135,135)]:
 print(x,y,round(float(v[y,x]),1),list(a[y,x].astype(int)))
