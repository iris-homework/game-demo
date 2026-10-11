extends Node
var app: Control
var checks := 0
var failures := 0
const OUTPUT := "res://artifacts/qa/player-characters-2026-10-10/"

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)

func idle() -> void:
	for frame in 1800:
		await get_tree().process_frame
		if not Game.transition_locked and not Game.battle_busy: return
	check(false, "View animation timeout")
	get_tree().quit(1)

func has_label(text: String) -> bool:
	for item in app.view.find_children("*", "Label", true, false):
		if item.text == text: return true
	return false

func shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	var result := get_viewport().get_texture().get_image().save_png(OUTPUT + name + ".png")
	check(result == OK, "Screenshot " + name)

func show_character(id: String, prefix: String) -> Texture2D:
	Game.new_game(id)
	await idle()
	Game.advance(Game.revision)
	await idle()
	app.view.text_label.visible_characters = -1
	check(has_label(Game.display_name("@player")), prefix + " speaker label follows ID")
	var portrait: Texture2D = Game.texture(Game.player_asset_id())
	var visible_portrait := false
	for item in app.view.find_children("*", "TextureRect", true, false):
		if item.texture == portrait: visible_portrait = true
	check(visible_portrait, prefix + " dialogue portrait follows ID")
	await shot(prefix + "-dialogue")
	Game.go_map()
	await idle()
	check(has_label(Game.display_name("@player") + " / 城市总览"), prefix + " map label follows ID")
	var marker: Control = app.view.markers.bar
	var avatar: Texture2D = marker._avatar_pic.texture
	check(avatar != null, prefix + " map avatar rendered")
	await shot(prefix + "-map")
	Game.start_training("B12")
	await idle()
	check(app.view.player_portrait.texture == Game.texture(Game.player_asset_id("battlePortraitAssetId")), prefix + " battle portrait follows ID")
	check(has_label(Game.display_name("@player")), prefix + " battle label follows ID")
	check(app.view.model.max_hp == int(Game.player_definition().attributes.maxHp), prefix + " battle HP follows config")
	await shot(prefix + "-battle")
	Game.finish_training("surrender")
	await idle()
	return avatar

func _ready() -> void:
	Game.save_enabled = false
	Game.save_path = OUTPUT + "visual_checkpoint.json"
	Game.meta_path = OUTPUT + "visual_meta.json"
	app = load("res://scenes/main.tscn").instantiate()
	add_child(app)
	var first := await show_character("noren", "noren")
	Game.characters["qa_actor"] = {"displayName":"接入测试角色", "portraitAssetId":"reception", "battlePortraitAssetId":"mech_battle", "mapAvatarCrop":[0.25,0.0,0.5,0.3]}
	Game.player_characters["qa_actor"] = {"attributes":{"maxHp":137}, "startingDeck":["test_attack","test_attack","test_attack","test_attack","test_attack"], "skills":[]}
	var second := await show_character("qa_actor", "test-actor")
	check(first != second, "Map cache does not reuse Noren avatar for another character")
	Game.new_game("noren")
	await idle()
	Game.go_map()
	await idle()
	check(app.view.markers.bar._avatar_pic.texture == first, "Returning to Noren restores correct cached avatar")
	await shot("noren-map-return")
	Game.characters.erase("qa_actor")
	Game.player_characters.erase("qa_actor")
	print("PLAYER CHARACTER VISUAL: ", checks, " checks, ", failures, " failures")
	get_tree().quit(0 if failures == 0 else 1)
