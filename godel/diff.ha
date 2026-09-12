use bytes;

export fn argv_equal(
	a: *const set,
	aa: *const service,
	b: *const set,
	bb: *const service,
) bool = {
	if (aa.argc != bb.argc) return false;
	for (let i = 0z; i < aa.argc: size; i += 1) {
		if (!bytes::equal(svc_arg(a, aa, i), svc_arg(b, bb, i))) return false;
	};
	if (aa.notification_fd != bb.notification_fd) return false;
	if (aa.runas_len != bb.runas_len) return false;
	return bytes::equal(svc_runas(a, aa), svc_runas(b, bb));
};

export fn match_running(
	next: *const set,
	old: *const set,
	runtimes: []runtime,
	indices: *[MAX_SERVICES]u8,
	matched: *[MAX_SERVICES]bool,
) void = {
	for (let i = 0z; i < next.count; i += 1) {
		for (let j = 0z; j < old.count; j += 1) {
			if (matched[j]) continue;
			const r = &runtimes[j];
			const keepable = r.state == state::up
				|| (r.state == state::stopped && r.finished);
			if (!keepable) continue;
			if (bytes::equal(svc_name(&next.services[i]),
					svc_name(&old.services[j]))
					&& argv_equal(next, &next.services[i], old, &old.services[j])) {
				indices[i] = j: u8;
				matched[j] = true;
				break;
			};
		};
	};
};
