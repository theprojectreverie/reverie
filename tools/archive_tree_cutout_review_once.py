from pathlib import Path
import shutil
folder=Path(r"C:\Users\quoth\Documents\Default Project\project-fantasy\assets\royal_gate_isometric_cleaned\garden")
dst=Path(r"C:\Users\quoth\Downloads\royal_gate_tree_review_archive")
dst.mkdir(parents=True,exist_ok=True)
moved=[]
for f in folder.glob("tree_cutout_*"):
    if f.name in {"tree_cutout_candidate_final.png","tree_cutout_candidate_final.png.import"}:
        continue
    shutil.move(str(f),str(dst/f.name))
    moved.append(f.name)
print("archived",len(moved),"files")
print("kept:",[x.name for x in folder.glob("tree*")])
