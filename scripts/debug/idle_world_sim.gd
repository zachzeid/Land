extends SceneTree
# Dev tool: run 200 story rounds with no player input on a fresh WorldState and report drift.
# The game clock runs alongside (2 game hours per round, ~16 days), so The Tithe Night's calendar
# fixed points (tn_day_2..7, tn_collection_night) fire as they would in play.
# Run: godot --headless --path . -s res://scripts/debug/idle_world_sim.gd (loads no NPC scenes, writes no memories)
func _init():
	for i in 5: await process_frame
	var ws = root.get_node("WorldState")
	var d = root.get_node("StorylineDirector")
	ws.world_flags = {"tithe_drawing_witnessed": true}  # a new game opens at the drawing (OpeningSequence sets this)
	ws.npc_states = {}
	ws.set_idle_clock_rate(0.0)
	ws.reset_calendar(ws.start_minute)  # a new game: day 1, 20:00, nothing fired
	var fired = []
	root.get_node("EventBus").calendar_flag_fired.connect(func(flag, _at): fired.append("%s @ round %d" % [flag, d.get_round()]))
	d.round_boundaries_enabled = false
	d.load_content()
	d.evaluate_all()
	var reached = {}
	var violations = 0
	# Endings deliberately reachable through the player's absence (same list as tools/validate_world.py)
	const NEGLECT_ENDINGS = ["the_locked_room", "tn_the_cart_rolled"]
	var ending_ids = {}
	for r in 200:
		ws.advance_time(d.MINUTES_PER_ROUND, "sim")  # the clock a round's worth on; fixed points fire
		await d.advance_round("sim")
		for sid in d.get_storyline_ids():
			var e = d.get_ending(sid)
			if e and not reached.has(sid):
				reached[sid] = "%s @ round %d" % [e, r + 1]
				ending_ids[sid] = String(e)
	for sid in d.get_storyline_ids():
		var res = 0
		var act3 = []
		for b in d.get_beats(sid):
			if d.get_beat_status(sid, b.id) == "resolved":
				res += 1
				if int(b.get("act", 0)) == 3: act3.append(b.id)
		var neglected = ending_ids.get(sid, "") in NEGLECT_ENDINGS
		if not neglected and (not act3.is_empty() or reached.has(sid)): violations += 1
		print("SIM %s resolved=%d/%d ending=%s act3_resolved=%s" % [sid, res, d.get_beats(sid).size(), reached.get(sid, "none"), act3])
	print("SIM decisions=%d queue=%d" % [d.get_chronicle(0).size(), d.get_decision_queue().size()])
	print("SIM clock=%s calendar fired: %s" % [ws.get_time_string(), fired])
	# Acceptance: with no player, no Act III beat resolves and no story ends
	print("SIM %s (%d storylines finished or reached Act III resolution without the player)" % ["PASS" if violations == 0 else "FAIL", violations])
	quit(0 if violations == 0 else 1)
