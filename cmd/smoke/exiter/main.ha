use fmt;
use os;

export fn main() void = {
	fmt::println("godel QEMU smoke test: exiter exiting with code 3")!;
	os::exit(3);
};
