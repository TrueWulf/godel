use rt;
use time;

@test fn now_ms_is_monotonic() void = {
	const first = now_ms();
	time::sleep(2 * time::MILLISECOND);
	const second = now_ms();
	assert(second >= first);
};

@test fn timerfd_fires_once_after_deadline() void = {
	let t = timer { fd = -1 };
	assert(timer_create(&t) is void);
	defer close_fd(t.fd);
	assert(!timer_read_tick(&t));
	timer_set_abs(&t, now_ms() + 5);
	let fired = false;
	let attempts: size = 0;
	for (attempts < 200; attempts += 1) {
		if (timer_read_tick(&t)) {
			fired = true;
			break;
		};
		time::sleep(1 * time::MILLISECOND);
	};
	assert(fired);
	timer_disable(&t);
	assert(!timer_read_tick(&t));
};

@test fn signal_mask_contains_expected_bits() void = {
	const mask = signal_mask();
	assert(mask.__val[0] & 1 != 0);
	assert(mask.__val[0] & 2 != 0);
	assert(mask.__val[0] & (1 << 9) != 0);
	assert(mask.__val[0] & (1 << 14) != 0);
	assert(mask.__val[0] & (1 << 16) != 0);
};
