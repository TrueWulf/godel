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

// The tag layout must never constrain the service index space: the
// special ranges are far apart and can absorb any plausible count.
@test fn tag_ranges_leave_room_for_service_indexes() void = {
	assert(TAG_SIGNAL & (TAG_SIGNAL - 1) == 0);
	assert(TAG_TIMER > TAG_SIGNAL);
	assert(TAG_RESCUE > TAG_TIMER);
	assert(TAG_CTL > TAG_RESCUE);
	assert(TAG_DYING_BASE > TAG_CTL);
	assert(TAG_NOTIFY_BASE > TAG_DYING_BASE + 4096);
	assert(TAG_NOTIFY_BASE + 4096 < 1 << 48);
};
