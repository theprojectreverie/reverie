from pathlib import Path
from PIL import Image,ImageOps
import json,shutil
p=Path(r'C:\Users\quoth\Documents\Default Project\project-fantasy')
a=p/'assets/characters/elathra'
src=Image.open(a/'portrait.png').convert('RGBA')
# Preserve the whole original illustrated bust, without distorting or cropping the hat.
out=Image.new('RGBA',(512,683))
art=ImageOps.contain(src,(504,675),Image.Resampling.LANCZOS)
out.paste(art,((512-art.width)//2,(683-art.height)//2))
out.save(a/'portrait_512.png')
f=p/'resources/data/characters.json'
shutil.copy2(f,str(f)+'.before_elathra_summon_art')
data=json.loads(f.read_text(encoding='utf-8-sig'))
data['elathra']['assets']['portrait_status']='imported'
f.write_text(json.dumps(data,ensure_ascii=False,indent=4)+'\n',encoding='utf-8')
print('Collection portrait:',out.size,out.mode,'alpha:',out.getchannel('A').getextrema())
