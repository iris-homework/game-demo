extends Node
## Headless lifecycle regression; run only in a copied project with a QA user dir.
const Hooks := preload("res://scripts/audio/sfx_hooks.gd")
const Library := preload("res://scripts/card_library.gd")
const DrawFX := preload("res://scripts/combat/draw_fx.gd")
const DiscardFX := preload("res://scripts/combat/discard_fx.gd")
const ExhaustFX := preload("res://scripts/combat/exhaust_fx.gd")
const ShuffleFX := preload("res://scripts/combat/shuffle_fx.gd")

class CueBank extends Node:
	var cues: Array[String] = []
	func play_cue(cue: String) -> void: cues.append(cue)

var checks := 0
var failures: Array[String] = []
var output := OS.get_environment("QA_OUT_DIR")
var hooks: Node
var bank: CueBank
var host: Control
var library: Control

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures.append(message)
		push_error("SFX HOOK CLEANUP: " + message)

func settle() -> void:
	for i in 3: await get_tree().process_frame

func counts() -> Vector3i:
	return Vector3i(hooks.cards.size(), hooks.watched.size(), hooks.connections.size())

func button(parent: Node) -> Button:
	var result := Button.new()
	result.text = "测试"
	parent.add_child(result)
	return result

func check_live_records() -> void:
	var valid := true
	for reference in hooks.cards:
		var card: Object = reference.get_ref()
		valid = valid and is_instance_valid(card)
	for item in hooks.connections:
		var source: Object = item.source.get_ref()
		valid = valid and is_instance_valid(source)
		if is_instance_valid(source): valid = valid and source.is_connected(item.signal_name, item.callback)
	check(valid, "card and signal records reference only live connected sources")

func _ready() -> void:
	if not ProjectSettings.get_setting("application/config/custom_user_dir_name", "").to_lower().contains("qa") or not output.is_absolute_path():
		push_error("Requires copied project, QA user dir and absolute QA_OUT_DIR")
		get_tree().quit(2)
		return
	DirAccess.make_dir_recursive_absolute(output)
	get_tree().create_timer(120).timeout.connect(func(): push_error("SFX HOOK CLEANUP TIMEOUT"); get_tree().quit(2))
	Game.save_enabled = false
	Game.save_path = output.path_join("unused-checkpoint.json")
	Game.meta_path = output.path_join("unused-meta.json")
	Game.state = Game.initial_state("noren")
	Game.page = "card_library"
	host = Control.new()
	add_child(host)
	bank = CueBank.new()
	add_child(bank)
	hooks = Hooks.new()
	hooks.bank = bank
	hooks.ui_root = host
	add_child(hooks)
	hooks.set_process(false)
	library = Library.new()
	host.add_child(library)
	hooks.attach(library)
	await settle()
	var initial := counts()
	var survivor := button(host)
	await settle()
	var baseline := counts()
	check(baseline.y > initial.y and baseline.z == initial.z + 1, "root-level overlay button is registered")
	for iteration in 12:
		var group := Control.new()
		host.add_child(group)
		var card := CombatCard.new()
		card.setup("cleanup-%d" % iteration, Game.card_catalog.noren_01, true)
		group.add_child(card)
		var transient := button(group)
		var draw := DrawFX.new()
		group.add_child(draw)
		for fx in [DiscardFX.new(), ExhaustFX.new(), ShuffleFX.new()]: group.add_child(fx)
		await settle()
		check(bank.cues.count("card_discard") == 1 and bank.cues.count("card_exhaust") == 1 and bank.cues.count("card_shuffle") == 1, "FX registration preserves one initial feedback per effect %d" % iteration)
		bank.cues.clear()
		transient.pressed.emit()
		draw.departed.emit()
		card.hovered = true
		hooks._process(0)
		check(bank.cues.count("ui_click") == 1 and bank.cues.count("card_draw") == 1 and bank.cues.count("card_hover") == 1, "live card/button/draw feedback remains once per action %d" % iteration)
		var active := counts()
		hooks._watch(group)
		await settle()
		check(counts() == active, "repeated registration adds no records %d" % iteration)
		check(not bank.cues.has("card_discard") and not bank.cues.has("card_exhaust") and not bank.cues.has("card_shuffle"), "duplicate watch does not replay FX registration cues %d" % iteration)
		var reference: WeakRef = weakref(group)
		group.queue_free()
		await settle()
		check(reference.get_ref() == null, "exit callbacks do not retain destroyed subtree %d" % iteration)
		check(counts() == baseline, "destroying cards/buttons/FX restores record counts %d" % iteration)
		check_live_records()
		bank.cues.clear()
		survivor.pressed.emit()
		check(bank.cues == ["ui_click"], "unrelated live button remains connected %d" % iteration)
	# Deferred node_added must not register a detached but still alive subtree.
	var detached := button(host)
	host.remove_child(detached)
	await settle()
	check(counts() == baseline and detached.pressed.get_connections().is_empty(), "pending deferred registration ignores detached live nodes")
	host.add_child(detached)
	await settle()
	bank.cues.clear()
	detached.pressed.emit()
	check(bank.cues == ["ui_click"], "detached button reconnects once on re-entry")
	host.remove_child(detached)
	bank.cues.clear()
	detached.pressed.emit()
	check(bank.cues.is_empty(), "removed live sources lose their feedback signal connection")
	detached.free()
	await settle()
	check(counts() == baseline, "re-entry and second removal leave baseline records")
	# Exercise the actual production refresh path instead of synthetic containers only.
	for iteration in 8:
		library.set_scope(false)
		library.clear_filters()
		await settle()
		var all_counts := counts()
		check(hooks.cards.size() == library.card_views.size(), "actual all-card library has exactly its live cards %d" % iteration)
		library.set_filter("type", "attack")
		await settle()
		check(hooks.cards.size() == library.card_views.size(), "actual same-page filtering removes retired card records %d" % iteration)
		check_live_records()
		library.clear_filters()
		await settle()
		check(counts() == all_counts, "actual filter rebuild returns to stable full-library counts %d" % iteration)
	# Reattaching the same view must replace callbacks, not double them.
	hooks.attach(library)
	await settle()
	var reattached := counts()
	hooks.attach(library)
	await settle()
	check(counts() == reattached, "repeated attach on surviving view remains stable")
	bank.cues.clear()
	survivor.pressed.emit()
	check(bank.cues == ["ui_click"], "attach does not duplicate surviving feedback")
	var old_library := library
	host.remove_child(old_library)
	library = Library.new()
	host.add_child(library)
	hooks.attach(library)
	await settle()
	var switched := counts()
	check(hooks.cards.size() == library.card_views.size(), "switching view tracks only new library cards")
	old_library.queue_free()
	await settle()
	check(counts() == switched, "destroying previous view cannot remove new view observations")
	bank.cues.clear()
	survivor.pressed.emit()
	check(bank.cues == ["ui_click"], "persistent root overlay feedback survives view switch")
	hooks.attach(null)
	check(counts() == Vector3i.ZERO, "detach clears all observer records")
	bank.cues.clear()
	survivor.pressed.emit()
	check(bank.cues.is_empty(), "detach disconnects still-live button sources")
	host.queue_free()
	await settle()
	check(counts() == Vector3i.ZERO, "destroying former view cannot repopulate detached observer")
	hooks.free()
	bank.free()
	check(not FileAccess.file_exists(Game.save_path) and not FileAccess.file_exists(Game.meta_path), "no adventure checkpoint or meta was written")
	var report := {"checks": checks, "failures": failures, "scope": "headless live production card library filtering plus transient card/button/FX lifecycle; recording cue bank, no physical input or audio listening"}
	var file := FileAccess.open(output.path_join("result.json"), FileAccess.WRITE)
	if file: file.store_string(JSON.stringify(report, "\t")); file.close()
	print("SFX_HOOKS_CLEANUP checks=%d failures=%d" % [checks, failures.size()])
	get_tree().quit(0 if failures.is_empty() else 1)
