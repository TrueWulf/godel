use fmt;
use rt;

export fn main() void = {
	fmt::println("godel QEMU smoke test: worker started")!;
	for (true) rt::syscall(rt::SYS_pause);
};
