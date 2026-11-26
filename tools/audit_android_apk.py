"""Release gate: validate the actual Android APK, not just editor assets."""
import argparse, hashlib, json, pathlib, re, sys, zipfile
p=argparse.ArgumentParser()
p.add_argument('apk', type=pathlib.Path)
p.add_argument('--root', type=pathlib.Path, default=pathlib.Path(__file__).resolve().parents[1])
args=p.parse_args()
root=args.root.resolve()
issues=[]
def verify(ok,message):
    if not ok: issues.append(message)
with zipfile.ZipFile(args.apk) as archive:
    names=set(archive.namelist())
    def packaged(ref):
        base='assets/'+ref.removeprefix('res://')
        return any(base+ext in names for ext in ('','.import','.remap'))
    verify(archive.testzip() is None,'ZIP CRC failure')
    verify('assets/project.binary' in names,'project.binary missing')
    verify('lib/arm64-v8a/libgodot_android.so' in names,'ARM64 runtime missing')
    import_count=0
    for entry in sorted(names):
        if not entry.startswith('assets/') or not entry.endswith(('.import','.remap')): continue
        data=archive.read(entry).decode('utf-8',errors='replace')
        paths=re.findall(r'"(res://\.godot/[^"]+)"',data)
        # Imports may list desktop GPU variants as well as mobile variants; at least
        # one target must be present. Every .remap target must be present.
        if paths:
            import_count+=1
            targets=['assets/'+s.removeprefix('res://') for s in paths]
            verify(any(t in names for t in targets),f'No imported target for {entry}: {targets}')
    required=['scenes/main.tscn','scenes/ui/title_screen.tscn','scenes/ui/main_menu.tscn','scenes/ui/opening_cinematic.tscn','scenes/world/tutorial_prologue/kael_diamond_bedroom.tscn','scenes/world/tutorial_prologue/training_ground_v02.tscn','scenes/ui/social_screen.tscn','scenes/ui/components/tutorial_touch_controls.tscn','scripts/online/connection_profile.gd']
    for path in required: verify(packaged(path),f'Required runtime resource missing: {path}')
    cinematic_count=0
    for entry in sorted(names):
        if not entry.startswith('assets/assets/cinematics/') or not entry.endswith('.json'):continue
        data=json.loads(archive.read(entry))
        refs=set(re.findall(r'res://[^"\\]+?\.(?:png|jpg|webp|ogg|wav|mp3|tscn|json|mp4)',json.dumps(data,ensure_ascii=False),re.I))
        for ref in refs:verify(packaged(ref),f'Cinematic asset missing: {entry}: {ref}')
        if entry.endswith('kael_prologue_sequence.json'):
            verify(len(data.get('shots',[]))==12,'Kael prologue must contain 12 approved shots')
        if refs:print(f'Cinematic {entry}: {len(refs)} asset references');cinematic_count+=len(refs)
    checked=0
    omitted={}
    pattern=re.compile(r'res://[^"\n\r]+?\.(?:png|jpg|jpeg|webp|ogg|wav|mp3|tscn|tres|gd|json|mp4|ogv|ttf|otf)(?=["\'])',re.I)
    for folder in ('scripts','scenes','resources/data'):
        for file in (root/folder).rglob('*'):
            if file.suffix not in ('.gd','.tscn','.json','.tres'):continue
            rel=file.relative_to(root).as_posix()
            if not packaged(rel):continue
            for ref in set(pattern.findall(file.read_text(encoding='utf-8-sig',errors='replace'))):
                # Ignore obsolete literal paths which do not exist in the source.
                # Check actual loadable source references against the exported APK.
                if (root/ref[6:]).is_file():
                    checked+=1
                    if not packaged(ref):omitted.setdefault(ref,[]).append(rel)
    for ref,parents in omitted.items():issues.append(f'Export excluded existing runtime reference {ref}: {parents}')
print(f'APK entries={len(names)} import/remap descriptors={import_count} cinematic refs={cinematic_count} source refs={checked}')
print('SHA256',hashlib.file_digest(args.apk.open('rb'),'sha256').hexdigest())
for item in issues:print('FAIL',item)
print('PASS Android APK resource gate' if not issues else f'FAIL {len(issues)} issues')
sys.exit(bool(issues))