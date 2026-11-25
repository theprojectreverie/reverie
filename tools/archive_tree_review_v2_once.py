from pathlib import Path
import shutil
folder=Path(r"C:\Users\quoth\Documents\Default Project\project-fantasy\assets\royal_gate_isometric_cleaned\garden")
archive=Path(r"C:\Users\quoth\Downloads\royal_gate_tree_review_archive")
archive.mkdir(parents=True,exist_ok=True)
moved=[]
for f in folder.glob("tree_cutout_v*"):
 if f.is_file():
  shutil.move(str(f),str(archive/f.name))
  moved.append(f.name)
for f in folder.glob("tree_candidate_*"):
 if f.is_file():
  shutil.move(str(f),str(archive/f.name))
  moved.append(f.name)
print("archived review files:",len(moved))
print("active tree PNGs:",[x.name for x in folder.glob("tree*.png")])
