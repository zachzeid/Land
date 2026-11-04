extends SceneTree

# Tests that the loading screen can't hang (Iron Hollow, no API key):
# - a backend that fails at once (no key) reaches asset_failed: the request is tracked before it starts
# - the preloader counts an asset that never reports back as failed after ASSET_TIMEOUT_MS, and completes
# Fakes only: no API calls, nothing generated, the asset cache is not written
# Run: godot --headless --path . -s res://scripts/debug/test_asset_preload.gd

var failures: int = 0

class NoKeyBackend extends Node:
	signal generation_failed(request_id: String, error: String)
	func generate(request) -> String:
		generation_failed.emit(request.id, "API key not configured")
		return ""

func _init():
	await process_frame
	await process_frame
	await _test_sync_failure()
	await _test_watchdog()
	print("")
	if failures == 0:
		print("✅ ALL TESTS PASSED")
	else:
		print("❌ %d CHECK(S) FAILED" % failures)
	quit(0 if failures == 0 else 1)

func _check(ok: bool, what: String) -> void:
	if ok:
		print("  ✓ " + what)
	else:
		print("  ✗ " + what)
		failures += 1

func _test_sync_failure() -> void:
	print("\n== a backend that fails at once still reports the failure")
	var gen = root.get_node("AssetGenerator")
	var saved_backend = gen.active_backend
	var fake = NoKeyBackend.new()
	root.add_child(fake)
	fake.generation_failed.connect(gen._on_generation_failed)
	gen.active_backend = fake
	var got: Array = []
	var on_failed = func(asset_id, _error): got.append(asset_id)
	gen.asset_failed.connect(on_failed)
	var started = gen.generate_asset("qa_no_key_asset", "a test barrel")
	_check(not started, "generate_asset says it did not start")
	_check(got == ["qa_no_key_asset"], "asset_failed reached listeners (%s)" % [got])
	_check(gen.pending.is_empty() or not gen.pending.values().any(func(p): return p.asset_id == "qa_no_key_asset"), "nothing left pending")
	gen.asset_failed.disconnect(on_failed)
	gen.active_backend = saved_backend
	fake.queue_free()

func _test_watchdog() -> void:
	print("\n== the loading screen gives up on an asset that never reports back")
	var pre = root.get_node("AssetPreloader")
	var done: Array = []
	var on_done = func(ok, failed): done.append([ok, failed])
	pre.preload_completed.connect(on_done)
	pre.is_loading = true
	pre.total_assets = 1
	pre.loaded_assets = 0
	pre.failed_assets = 0
	pre.pending_asset_ids = ["qa_silent_asset"] as Array[String]
	pre._last_progress_ms = Time.get_ticks_msec()
	pre._process(0.0)
	_check(pre.pending_asset_ids.size() == 1, "still waiting before the timeout")
	pre._last_progress_ms = Time.get_ticks_msec() - pre.ASSET_TIMEOUT_MS - 1
	pre._process(0.0)
	_check(pre.pending_asset_ids.is_empty() and pre.failed_assets == 1, "after the timeout it counts as failed")
	await create_timer(0.8).timeout   # _complete_loading waits 0.5 s before it signals
	_check(done == [[0, 1]], "preload_completed fired (%s)" % [done])
	_check(not pre.is_loading and not pre.loading_screen.visible, "the loading screen is down")
	pre.preload_completed.disconnect(on_done)
