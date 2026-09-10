use rt;

export type state = enum u8 { stopped, up, backoff, gave_up };

export def RESET_AFTER_MS: i64 = 10_000;
export def MAX_BACKOFF_MS: i64 = 30_000;

export type exitkind = (void | u32 | u8);

export fn classify(status: u32) exitkind = {
	if (status & 0x7f == 0) {
		const code = status >> 8;
		if (code == 0) return void;
		return code;
	};
	return (status & 0x7f): u8;
};

// A restart decision is represented directly by its payload.  This keeps the
// state machine exhaustive at every call site and avoids a meaningless delay
// field for stop/give-up decisions.
export type stopped = void;
export type restart_in = i64;
export type gave_up = void;
export type decision = (stopped | restart_in | gave_up);

export type runtime = struct {
	state: state,
	pid: int,
	pidfd: int,
	restarts: u32,
	started_at: i64,
	restart_at: i64,
};

export fn new_runtime() runtime = runtime { pidfd = -1, ... };

export fn on_exit(
	r: *runtime,
	cfg: *const service,
	status: u32,
	now: i64,
) decision = {
	if (now - r.started_at >= RESET_AFTER_MS) r.restarts = 0;
	if (cfg.kind == service_kind::oneshot && classify(status) is void) {
		r.state = state::stopped;
		return stopped;
	};
	const failed = !(classify(status) is void);
	const wants_restart = switch (cfg.restart) {
	case restart::none => yield false;
	case restart::on_failure => yield failed;
	case restart::always => yield true;
	};
	if (!wants_restart) {
		r.state = state::stopped;
		return stopped;
	};
	r.restarts += 1;
	if (r.restarts > cfg.restart_limit) {
		r.state = state::gave_up;
		return gave_up;
	};
	const n = r.restarts: i64;
	let shift: i64 = n - 1;
	if (shift > 5) shift = 5;
	let delay = cfg.restart_delay_ms;
	for (let i: i64 = 0; i < shift; i += 1) {
		delay <<= 1;
	};
	if (delay > MAX_BACKOFF_MS) delay = MAX_BACKOFF_MS;
	r.state = state::backoff;
	r.restart_at = now + delay;
	return delay: restart_in;
};
