from pathlib import Path
import shutil,re
p=Path(r'C:\Users\quoth\Documents\Default Project\project-fantasy')
f=p/'scenes/ui/elathra_dialogue_box.tscn'
t=f.read_text(encoding='utf-8-sig')
shutil.copy2(f,str(f)+'.before_exact_panel_alignment')
# Preserve the base DialogueBox node paths, but remove container-driven placement.
def node(name,body,typ=None):
 global t
 pat=r'(?m)^\[node name="'+name+r'"[^\n]*\]\n.*?(?=\n\[node |\Z)'
 m=re.search(pat,t,re.S)
 if not m: raise RuntimeError(name)
 header=m.group(0).splitlines()[0]
 if typ: header=re.sub(r'type="[^"]+"','type="'+typ+'"',header)
 t=t[:m.start()]+header+'\n'+body.strip()+'\n\n'+t[m.end():]
def rect(l,top,r,b,al=0,at=0,ar=0,ab=0):
 return f'layout_mode = 1\nanchor_left = {al}.0\nanchor_top = {at}.0\nanchor_right = {ar}.0\nanchor_bottom = {ab}.0\noffset_left = {l}.0\noffset_top = {top}.0\noffset_right = {r}.0\noffset_bottom = {b}.0'
# Match the panel's precise bounds to an overlay with identical anchors.
node('DialoguePanel',rect(410,-345,-30,-25,0,1,1,1)+'\nmouse_filter = 2','Control')
node('ContentRow',rect(0,0,0,0,0,0,1,1)+'\nmouse_filter = 2','Control')
node('Portrait','visible = false\nmouse_filter = 2\nscript = ExtResource("2_portrait")')
node('PortraitSpacer','visible = false\nmouse_filter = 2')
node('TextColumn',rect(0,0,0,0,0,0,1,1)+'\nmouse_filter = 2','Control')
# Art nameplate from x~80 to 390 of 1060, y~5 to 60 of 322.
# At viewport 1280 panel width 840: center x~175, height 320.
node('Header',rect(85,8,300,58)+'\nmouse_filter = 2','Control')
node('SpeakerLabel',rect(0,0,0,0,0,0,1,1)+'\nmouse_filter = 2\ntheme_override_colors/font_color = Color(0.98, 0.89, 0.71, 1)\ntheme_override_font_sizes/font_size = 24\nhorizontal_alignment = 1\nvertical_alignment = 1\ntext = "Speaker"')
node('NameLabel','visible = false\nmouse_filter = 2')
node('HeaderSpacer','visible = false\nmouse_filter = 2')
node('TextLabel',rect(70,86,-120,165,0,0,1,0)+'\nmouse_filter = 2\ntheme_override_colors/default_color = Color(0.97, 0.93, 0.86, 1)\ntheme_override_font_sizes/normal_font_size = 20\ntheme_override_constants/line_separation = 5\nbbcode_enabled = true\nfit_content = false\nscroll_active = true')
node('ChoicesBox',rect(70,175,-120,267,0,0,1,0)+'\nmouse_filter = 2\ntheme_override_constants/separation = 8')
node('Footer',rect(70,175,-120,267,0,0,1,0)+'\nmouse_filter = 2','Control')
node('HintLabel','visible = false\nmouse_filter = 2')
node('FooterSpacer','visible = false\nmouse_filter = 2')
node('ContinueButton',rect(-155,45,0,85,1,0,1,0)+'\ntext = "Continue"')
f.write_text(t,encoding='utf-8')
g=p/'scripts/ui/elathra_dialogue_box.gd'
shutil.copy2(g,str(g)+'.before_exact_panel_alignment')
s=g.read_text(encoding='utf-8-sig')
s=s.replace('_name_label.hide()','_name_label.hide()\n\t_hint_label.hide()')
# Keep a one-choice reply at the same top edge as two choices.
g.write_text(s,encoding='utf-8')
print('Anchored text, title and choices to the panel itself; removed flow container drift.')
