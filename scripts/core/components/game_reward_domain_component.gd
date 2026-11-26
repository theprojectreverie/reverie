class_name GameRewardDomainComponent
extends Node
## Owns banner roll orchestration and battle reward application.

var pity: Dictionary = {}

const DAILY_REWARDS := [
	{"gold": 300},
	{"crystals": 100},
	{"items": {"glade_sap": 2}},
	{"gold": 500},
	{"items": {"gothic_shard": 1}},
	{"crystals": 200},
	{"crystals": 500, "ancient_coins": 1, "items": {"moonpetal": 2}}
]


func daily_reward_status() -> Dictionary:
	var today := _local_day_key()
	var saved: Dictionary = GameState.daily_rewards
	var last_claim := str(saved.get("last_claim_date", ""))
	var day := clampi(int(saved.get("cycle_day", 1)), 1, DAILY_REWARDS.size())
	return {
		"can_claim": last_claim != today,
		"day": day,
		"last_claim_date": last_claim,
		"today": today,
		"reward": DAILY_REWARDS[day - 1].duplicate(true)
	}


func claim_daily_reward() -> Dictionary:
	var status := daily_reward_status()
	if not bool(status.can_claim):
		return {"ok": false, "reason": "Today's reward has already been claimed."}
	var reward: Dictionary = status.reward
	var next_day := int(status.day) + 1
	if next_day > DAILY_REWARDS.size():
		next_day = 1
	if int(reward.get("gold", 0)) > 0:
		GameState.inventory_domain.add_currency("gold", int(reward.gold))
	if int(reward.get("crystals", 0)) > 0:
		GameState.inventory_domain.add_currency("crystals", int(reward.crystals))
	if int(reward.get("ancient_coins", 0)) > 0:
		GameState.inventory_domain.add_currency("ancient_coins", int(reward.ancient_coins))
	var items: Dictionary = reward.get("items", {})
	if not items.is_empty():
		GameState.inventory_domain.grant_reward_items(items)
	GameState.daily_rewards = {
		"last_claim_date": str(status.today),
		"cycle_day": next_day,
		"last_claimed_day": int(status.day)
	}
	GameState.save_now()
	return {"ok": true, "day": int(status.day), "reward": reward, "next_day": next_day}


const DAILY_TASKS := [
	{"id":"blessing","title":"Daily Blessing","description":"Claim today's login reward.","target":1,"gold":150,"crystals":0},
	{"id":"victories","title":"Guardian's Duty","description":"Win three rewarded solo encounters.","target":3,"gold":300,"crystals":40},
	{"id":"explore","title":"Wanderer's Road","description":"Visit two different unlocked story areas.","target":2,"gold":250,"crystals":25},
	{"id":"bonus","title":"Daily Devotion","description":"Claim all three daily quest rewards.","target":3,"gold":500,"crystals":75}
]

func _daily_quest_enabled() -> bool:
	return bool(GameState.quest_domain.flags.get("tutorial_complete",false)) and MultiplayerGateway.standalone_expedition_id.is_empty()

func _daily_quest_day() -> Dictionary:
	var today:=_local_day_key()
	var saved: Dictionary=GameState.daily_quests
	if str(saved.get("date",""))!=today:
		saved={"date":today,"victories":0,"regions":[],"claimed":[]}
		GameState.daily_quests=saved
		GameState.queue_save()
	return saved

func daily_quest_status() -> Dictionary:
	var enabled:=_daily_quest_enabled()
	var saved:=_daily_quest_day()
	var claimed: Array=saved.get("claimed",[])
	var rows: Array=[]
	for task in DAILY_TASKS:
		var row: Dictionary=task.duplicate(true)
		var progress:=0
		match str(task.id):
			"blessing":progress=0 if bool(daily_reward_status().can_claim) else 1
			"victories":progress=int(saved.get("victories",0))
			"explore":progress=saved.get("regions",[]).size()
			"bonus":
				for id in ["blessing","victories","explore"]:
					if id in claimed:progress+=1
		row["progress"]=clampi(progress,0,int(task.target))
		row["claimed"]=str(task.id) in claimed
		row["can_claim"]=enabled and not row.claimed and row.progress>=int(task.target)
		rows.append(row)
	return {"date":saved.date,"enabled":enabled,"rows":rows}

func record_daily_victory(group_id: String) -> void:
	if not _daily_quest_enabled() or group_id=="tutorial_fairy_spar" or ContentDB.get_enemy_group(group_id).is_empty():return
	var saved:=_daily_quest_day()
	var count:=int(saved.get("victories",0))
	if count>=3:return
	saved["victories"]=count+1
	GameState.queue_save()

func record_daily_visit(region: String) -> void:
	if not _daily_quest_enabled() or region.is_empty():return
	var saved:=_daily_quest_day()
	var regions: Array=saved.get("regions",[])
	if region in regions or regions.size()>=2:return
	regions.append(region)
	saved["regions"]=regions
	GameState.queue_save()

func claim_daily_quest(id: String) -> bool:
	for row in daily_quest_status().rows:
		if str(row.id)!=id or not bool(row.can_claim):continue
		var saved:=_daily_quest_day()
		saved.claimed.append(id)
		GameState.inventory_domain.add_currency("gold",int(row.gold))
		GameState.inventory_domain.add_currency("crystals",int(row.crystals))
		GameState.save_now()
		EventBus.toast_requested.emit("Daily quest reward claimed: "+str(row.title))
		return true
	return false

func daily_quest_claimable_count() -> int:
	var total:=0
	for row in daily_quest_status().rows:
		if bool(row.can_claim):total+=1
	return total

func _local_day_key() -> String:
	var date := Time.get_date_dict_from_system()
	return "%04d-%02d-%02d" % [int(date.year), int(date.month), int(date.day)]



func pull_banner(banner_id: String, count: int, paid: bool = false) -> Dictionary:
	var banner: Dictionary = ContentDB.get_banner(banner_id)
	if banner.is_empty():
		return {"ok": false, "error": "Unknown banner."}
	if count != 1 and count != 10:
		return {"ok": false, "error": "Invalid summon count."}
	var cost_data: Dictionary = banner.get("cost", {})
	var currency_id := "paid_moonstones" if paid else str(cost_data.get("currency", "crystals"))
	var cost := int(cost_data.get("ten" if count == 10 else "single", 0))
	if not GameState.inventory_domain.spend_currency(currency_id, cost):
		return {"ok": false, "error": "Not enough %s." % ContentDB.get_item(currency_id).get("name", currency_id)}

	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var pity_state: Dictionary = pity.get(banner_id, GachaService.empty_pity())
	var paid_progress := int(GameState.profile.get("paid_summon_progress", 0)) % 100
	var outcome := GachaService.pull(banner, rng, pity_state, count, paid_progress if paid else -1)
	if paid:
		GameState.profile["paid_summon_progress"] = (paid_progress + count) % 100
	pity[banner_id] = outcome.pity
	var results: Array = []
	for roll in outcome.results:
		if roll.get("kind", "") == "upgrade_card":
			var card_id := str(roll.character_id)
			roll["fusions"] = preload("res://scripts/gacha/character_upgrade_card.gd").grant(card_id)
			roll["card_count"] = GameState.inventory_domain.item_count(card_id)
			roll["is_new"] = false
			roll["awakening_gain"] = 0
			results.append(roll)
			continue
		if roll.get("kind", "") == "mob_reward":
			GameState.inventory_domain.grant_reward_items(roll.items)
			roll["is_new"] = false
			roll["awakening_gain"] = 0
			results.append(roll)
			continue
		var added: Dictionary = GameState.roster_domain.add_character(str(roll.character_id))
		roll["is_new"] = bool(added.get("is_new", false))
		roll["awakening_gain"] = int(added.get("awakening_gain", 0))
		var helper = preload("res://scripts/gacha/character_upgrade_card.gd")
		var recipe: Dictionary = helper.mythic_recipe(str(roll.character_id))
		if not recipe.is_empty():
			roll["fusions"] = helper.record_legendary(str(roll.character_id))
			roll["mythic_count"] = GameState.inventory_domain.item_count(str(recipe.item))
		var ascension_recipe: Dictionary = helper.ascension_recipe(str(roll.character_id))
		if not ascension_recipe.is_empty():
			roll["fusions"] = helper.record_mythic(str(roll.character_id))
			roll["ascended_count"] = GameState.inventory_domain.item_count(str(ascension_recipe.item))
		results.append(roll)
	if paid:
		GameState.save_now()
	else:
		GameState.queue_save()
	return {"ok": true, "results": results, "pity": outcome.pity, "spent": cost, "currency": currency_id}


func build_battle_rewards(group_id: String, roll_bonus_drops: bool = false) -> Dictionary:
	var group: Dictionary = ContentDB.get_enemy_group(group_id)
	var rewards: Dictionary = group.get("rewards", {})
	var level_mult := 1.0 + 0.12 * maxi(0, int(group.get("level", 1)) - 1)
	var items: Dictionary = rewards.get("items", {}).duplicate(true)
	if roll_bonus_drops:
		var rng := RandomNumberGenerator.new()
		rng.randomize()
		for drop in group.get("drops", []):
			if typeof(drop) != TYPE_DICTIONARY:
				continue
			var chance := clampf(float(drop.get("chance", 0.0)), 0.0, 1.0)
			if chance >= 1.0 or (chance > 0.0 and rng.randf() < chance):
				var item_id := str(drop.get("item", ""))
				var minimum := maxi(1, int(drop.get("min", 1)))
				var maximum := maxi(minimum, int(drop.get("max", minimum)))
				var amount := rng.randi_range(minimum, maximum)
				if not item_id.is_empty():
					items[item_id] = int(items.get(item_id, 0)) + amount
	return {
		"gold": int(round(float(rewards.get("gold", 0)) * level_mult)),
		"crystals": int(round(float(rewards.get("crystals", 0)) * level_mult)),
		"ancient_coins": int(rewards.get("ancient_coins", 0)),
		"xp": int(round(float(rewards.get("xp", 0)) * level_mult)),
		"items": items,
	}


func apply_battle_result(group_id: String, victory: bool, precomputed_rewards: Dictionary = {}) -> Dictionary:
	if not victory:
		return {"applied": false}
	# The solo story boss is a one-time encounter. Legacy saves that already
	# defeated her must not receive a second payout either.
	if group_id == "revienna_encounter":
		var flags = GameState.quest_domain.flags
		if bool(flags.get("revienna_solo_reward_claimed", false)) or bool(flags.get("revienna_defeated", false)):
			return {"applied": false, "reason": "already_claimed"}
		flags["revienna_solo_reward_claimed"] = true
	var group: Dictionary = ContentDB.get_enemy_group(group_id)
	var rewards: Dictionary = precomputed_rewards.duplicate(true) if not precomputed_rewards.is_empty() else build_battle_rewards(group_id, true)
	GameState.inventory_domain.add_currency("gold", int(rewards.get("gold", 0)))
	GameState.inventory_domain.add_currency("crystals", int(rewards.get("crystals", 0)))
	GameState.inventory_domain.add_currency("ancient_coins", int(rewards.get("ancient_coins", 0)))
	var granted_items: Dictionary = rewards.get("items", {}).duplicate(true)
	GameState.inventory_domain.grant_reward_items(granted_items)
	rewards["items"] = granted_items
	GameState.roster_domain.add_party_xp(int(rewards.get("xp", 0)))
	for uid in GameState.roster_domain.party:
		GameState.roster_domain.add_bond(uid, 2)
	for enemy_id in group.get("quest_kills", {}).keys():
		GameState.quest_domain.record_kill(str(enemy_id), int(group["quest_kills"][enemy_id]))
	var reward_toast := "Victory — +%d gold, +%d crystals" % [int(rewards.get("gold", 0)), int(rewards.get("crystals", 0))]
	if int(rewards.get("ancient_coins", 0)) > 0:
		reward_toast += ", +%d Ancient Coins" % int(rewards.get("ancient_coins", 0))
	EventBus.toast_requested.emit(reward_toast)
	record_daily_victory(group_id)
	GameState.queue_save()
	return {"applied": true, "rewards": rewards}
