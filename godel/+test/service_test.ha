
fn mkcfg(r: restart, limit: u32, delay_ms: i64) service = {
	let cfg = new_service();
	cfg.restart = r;
	cfg.restart_limit = limit;
	cfg.restart_delay_ms = delay_ms;
	return cfg;
};

@test fn classify_decodes_exit_codes_and_signals() void = {
	assert(classify(0) is void);
	assert(classify(3 << 8) as u32 == 3);
	assert(classify(15) as u8 == 15);
	assert(classify(128 + 11 & 0x7f) as u8 == 11);
};

@test fn always_policy_restarts_with_doubling_backoff() void = {
	let r = new_runtime();
	r.started_at = 0;
	const cfg = mkcfg(restart::always, 10, 250);
	const first = on_exit(&r, &cfg, 0, 200);
	assert(first as restart_in == 250);
	const second = on_exit(&r, &cfg, 0, 300);
	assert(second as restart_in == 500);
	assert(r.state == state::backoff);
};

@test fn on_failure_allows_clean_exits() void = {
	let r = new_runtime();
	r.started_at = 0;
	const cfg = mkcfg(restart::on_failure, 10, 250);
	assert(on_exit(&r, &cfg, 0, 200) is stopped);
	assert(r.state == state::stopped);
	assert(on_exit(&r, &cfg, 3 << 8, 300) is restart_in);
};

@test fn never_policy_never_restarts() void = {
	let r = new_runtime();
	r.started_at = 0;
	const cfg = mkcfg(restart::none, 10, 250);
	assert(on_exit(&r, &cfg, 3 << 8, 200) is stopped);
};

@test fn oneshot_stops_after_clean_exit() void = {
	let r = new_runtime();
	r.started_at = 0;
	let cfg = mkcfg(restart::always, 10, 250);
	cfg.kind = service_kind::oneshot;
	assert(on_exit(&r, &cfg, 0, 200) is stopped);
	assert(r.state == state::stopped);
	assert(on_exit(&r, &cfg, 3 << 8, 300) is restart_in);
};

@test fn gives_up_after_limit_is_exceeded() void = {
	let r = new_runtime();
	r.started_at = 0;
	const cfg = mkcfg(restart::always, 2, 100);
	let _ = on_exit(&r, &cfg, 0, 100);
	let _ = on_exit(&r, &cfg, 0, 200);
	assert(on_exit(&r, &cfg, 0, 300) is gave_up);
	assert(r.state == state::gave_up);
};

@test fn restart_counter_resets_after_stable_uptime() void = {
	let r = new_runtime();
	r.started_at = 0;
	const cfg = mkcfg(restart::always, 1, 100);
	let _ = on_exit(&r, &cfg, 0, 100);
	let _ = on_exit(&r, &cfg, 0, 100 + RESET_AFTER_MS + 500);
	assert(on_exit(&r, &cfg, 0, 100 + 2 * RESET_AFTER_MS + 1000) is restart_in);
};

@test fn backoff_is_capped() void = {
	let r = new_runtime();
	r.started_at = 0;
	const cfg = mkcfg(restart::always, 100, 1000);
	let last: i64 = 0;
	let now: i64 = 0;
	for (let i = 0z; i < 20; i += 1) {
		const d = on_exit(&r, &cfg, 3 << 8, now);
		last = d as restart_in;
		now += 1;
	};
	assert(last == MAX_BACKOFF_MS);
};
