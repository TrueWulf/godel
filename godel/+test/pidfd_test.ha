use rt;

// The SIGCHLD fallback keeps working without a pidfd: wait_pid_nohang is
// the reap primitive and must report nothing for processes that are not
// our exited children. Live reaping is proven end to end by the basic
// QEMU session (SIGKILL of the beacon service, restart, restarts=1).
@test fn wait_pid_nohang_reports_nothing_for_non_children() void = {
	assert(wait_pid_nohang(rt::getpid()) is void);
	assert(wait_pid_nohang(1) is void);
	assert(wait_pid_nohang(-3) is void);
};

@test fn pidfd_open_rejects_invalid_pid() void = {
	assert(pidfd_open(-1) is void);
};

@test fn kill_process_group_tolerates_unknown_groups() void = {
	// Must not panic or signal anything when the group does not exist.
	kill_process_group(-1, rt::SIGTERM);
};

@test fn classify_reports_normal_exit_codes_through_the_fallback() void = {
	assert(classify(42 << 8) as u32 == 42);
	assert(classify(0) is void);
	assert(classify(9) as u8 == 9);
};
