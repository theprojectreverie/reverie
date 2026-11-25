from pathlib import Path
import shutil
p=Path(r'C:\Users\quoth\Documents\Default Project\project-fantasy')
f=p/'scripts/ui/main_menu.gd'
t=f.read_text(encoding='utf-8-sig')
shutil.copy2(f,str(f)+'.before_profile_panel_fix')
t=t.replace('var level := maxi(1, int(GameState.profile.get("level", 1)))','var name_label := details.get_node_or_null("PlayerName") as Label\n\tif name_label != null:\n\t\tvar display_name := str(AuthGateway.current_player().get("name", "")) if AuthGateway.is_authenticated() else "Traveler"\n\t\tname_label.text = display_name if not display_name.is_empty() else "Traveler"\n\tvar level := maxi(1, int(GameState.profile.get("level", 1)))',1)
t=t.replace('account.call_deferred("show_registration")','account.call_deferred("show_registration")')
t=t.replace('func _on_profile_account_authenticated(player: Dictionary, account: Control) -> void:\n','func _on_profile_account_authenticated(player: Dictionary, account: Control) -> void:\n\t_refresh_profile_progress()\n\t_refresh_currency_counts()\n')
f.write_text(t,encoding='utf-8')
s=p/'scenes/ui/main_menu.tscn'
t=s.read_text(encoding='utf-8-sig')
shutil.copy2(s,str(s)+'.before_profile_panel_fix')
t=t.replace('text = "TRAVELER"','theme_override_colors/font_color = Color(0.98, 0.87, 0.68, 1)\ntheme_override_font_sizes/font_size = 20\ntext_overrun_behavior = 3\ntext = "Traveler"',1)
t=t.replace('text = "LEVEL 01"','theme_override_colors/font_color = Color(0.81, 0.76, 0.83, 1)\ntheme_override_font_sizes/font_size = 13\ntext = "LEVEL 01"',1)
s.write_text(t,encoding='utf-8')
print('Live authenticated name and profile panel typography installed.')
