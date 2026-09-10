use strings;

@test fn reload_matching_keeps_only_unchanged_running_services() void = {
	let old = set { ... };
	let next = set { ... };
	assert(parse(&old, strings::toutf8("[service \"web\"]
command = /bin/web --old

[service \"worker\"]
command = /bin/worker
")) is void);
	assert(parse(&next, strings::toutf8("[service \"worker\"]
command = /bin/worker

[service \"web\"]
command = /bin/web --new
")) is void);
	let runtimes: [MAX_SERVICES]runtime = [runtime { pidfd = -1, ... }...];
	runtimes[0].state = state::up;
	runtimes[1].state = state::up;
	let indices: [MAX_SERVICES]u8 = [NO_INDEX...];
	let matched: [MAX_SERVICES]bool = [false...];
	match_running(&next, &old, runtimes[..], &indices, &matched);
	assert(indices[0] == 1);
	assert(indices[1] == NO_INDEX);
	assert(matched[1]);
	assert(!matched[0]);
};
