use strings;

@test fn setup_is_disabled_when_base_cannot_be_created() void = {
	const c = setup(strings::toutf8("/nonexistent-godel-test/xyz"));
	assert(!c.enabled);
};

@test fn service_paths_stay_in_bounds() void = {
	let c = setup(strings::toutf8("/nonexistent-godel-test/xyz"));
	let path: [MAX_PATH]u8 = [0...];
	assert(service_dir(&c, strings::toutf8("svc"), &path) is void);
	let enabled = controller { enabled = false, ... };
	enabled.enabled = true;
	enabled.root_len = 20z;
	enabled.root[..20] = strings::toutf8("/sys/fs/cgroup/godel");
	const dir = service_dir(&enabled, strings::toutf8("web"), &path) as []u8;
	const want = strings::toutf8("/sys/fs/cgroup/godel/web");
	assert(len(want) == len(dir));
	for (let i = 0z; i < len(dir); i += 1) {
		assert(dir[i] == want[i]);
	};
	let long: [200]u8 = ['a'...];
	assert(service_dir(&enabled, long[..], &path) is void);
};
