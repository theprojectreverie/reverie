from PIL import Image, ImageDraw
from pathlib import Path
import random, zipfile

OUT = Path(r"C:\Users\quoth\Documents\Default Project\project-fantasy\assets\environment\castle_gardens\royal_garden_v1\tiles")
OUT.mkdir(parents=True, exist_ok=True)
W=H=32
PAL={
 "outline":(43,57,48,255),"shade":(62,91,58,255),
 "grass":(94,142,76,255),"grass_hi":(137,177,91,255),"grass_dark":(67,112,66,255),
 "moss":(74,125,82,255),"moss_hi":(119,164,103,255),
 "soil":(137,96,66,255),"soil_hi":(171,126,83,255),"soil_dark":(104,72,57,255),
 "stone":(183,177,160,255),"stone_hi":(222,215,192,255),"stone_dark":(133,137,128,255),
 "water":(64,133,151,255),"water_hi":(111,184,190,255),"water_dark":(47,98,123,255),
 "sand":(197,174,123,255),"sand_hi":(225,204,151,255)
}
def base(kind, seed):
    rng=random.Random(seed)
    im=Image.new("RGBA",(32,32),(0,0,0,0)); d=ImageDraw.Draw(im)
    # Isometric diamond top with a one-pixel shaded front lip.
    top=[(16,4),(29,11),(16,19),(3,11)]
    d.polygon([(3,11),(16,19),(16,22),(3,14)],fill=PAL["shade"])
    d.polygon([(16,19),(29,11),(29,14),(16,22)],fill=PAL["grass_dark"] if kind.startswith("grass") else PAL["soil_dark"])
    d.polygon(top,fill=PAL["grass"] if kind.startswith("grass") else PAL["soil"] if kind in ("soil","dirt") else PAL["water"] if kind=="water" else PAL["sand"])
    d.line(top+[top[0]],fill=PAL["outline"],width=1)
    # restrained pixel texture contained within the diamond
    for _ in range(30):
        x=rng.randint(5,27); y=rng.randint(7,17)
        if abs(x-16)*8 + abs(y-11)*13 < 100:
            if kind.startswith("grass"):
                c=rng.choice([PAL["grass_hi"],PAL["grass_dark"],PAL["moss"]])
            elif kind in ("soil","dirt"):
                c=rng.choice([PAL["soil_hi"],PAL["soil_dark"]])
            elif kind=="water":
                c=rng.choice([PAL["water_hi"],PAL["water_dark"]])
            else: c=rng.choice([PAL["sand_hi"],PAL["soil_hi"]])
            d.point((x,y),fill=c)
    return im,d,rng

def make(name,kind,seed,decor):
    im,d,rng=base(kind,seed)
    if decor=="tufts":
        for x,y in [(9,10),(20,9),(15,14),(23,13),(10,15)]:
            d.point((x,y),fill=PAL["grass_hi"]); d.point((x+1,y-1),fill=PAL["grass_dark"])
    elif decor=="moss":
        for x,y in [(8,11),(9,12),(22,10),(21,11),(15,16)]:
            d.rectangle((x,y,x+1,y),fill=PAL["moss_hi"])
    elif decor=="flowers":
        for x,y,c in [(9,10,(236,190,207,255)),(21,12,(248,222,143,255)),(15,15,(197,183,235,255))]:
            d.point((x,y),fill=PAL["grass_dark"]); d.point((x,y-1),fill=c); d.point((x-1,y),fill=c); d.point((x+1,y),fill=c)
    elif decor=="cracks":
        d.line([(10,10),(12,11),(11,13)],fill=PAL["soil_dark"]); d.line([(21,9),(20,11)],fill=PAL["soil_dark"])
    elif decor=="ripples":
        d.line([(8,11),(11,11)],fill=PAL["water_hi"]); d.line([(18,14),(22,14)],fill=PAL["water_hi"]); d.point((14,9),fill=PAL["water_hi"])
    elif decor=="pebbles":
        for x,y in [(9,10),(21,12),(15,15),(24,9)]:
            d.point((x,y),fill=PAL["stone_hi"]); d.point((x+1,y),fill=PAL["stone_dark"])
    # preserve crisp pixel edges and transparent background
    im.save(OUT/f"{name}.png")
    
make("ground_grass_plain","grass",1101,"tufts")
make("ground_grass_moss","grass",1102,"moss")
make("ground_grass_blossom","grass",1103,"flowers")
make("ground_dirt_soft","dirt",1104,"cracks")
make("ground_water_shallow","water",1105,"ripples")
make("ground_sand_light","sand",1106,"pebbles")

# Preview sheet: 3 columns x 2 rows, enlarged nearest-neighbour for inspection.
preview=Image.new("RGBA",(32*3*4,32*2*4),(28,32,38,255))
names=["ground_grass_plain","ground_grass_moss","ground_grass_blossom","ground_dirt_soft","ground_water_shallow","ground_sand_light"]
for i,n in enumerate(names):
    tile=Image.open(OUT/f"{n}.png").resize((128,128),Image.Resampling.NEAREST)
    preview.alpha_composite(tile,((i%3)*128,(i//3)*128))
preview.save(OUT/"royal_garden_terrain_preview.png")
zip_path=OUT/"royal_garden_terrain_tiles_v1.zip"
with zipfile.ZipFile(zip_path,"w",zipfile.ZIP_DEFLATED) as z:
    for n in names: z.write(OUT/f"{n}.png",f"tiles/{n}.png")
print("Created 6 transparent 32x32 tiles, preview and zip:")
for n in names: print(f"{n}.png")
print(zip_path)
