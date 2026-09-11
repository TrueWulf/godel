// qemu-session drives scripted serial-console sessions for the Godel test
// image: it boots QEMU with the image's serial console on pipes, replays an
// expect/send script, and records the full console transcript to a log
// file. Exit status 0 means every expectation matched in the transcript,
// which is the evidence for the system tests.
//
// Script format, one action per line; blank lines and #comments ignored:
//   expect PATTERN [timeout=SECONDS]   wait for PATTERN in unread output
//   send TEXT                          write TEXT plus a newline
//   write TEXT                         write TEXT verbatim (no newline)
//   verify PATTERN                     PATTERN must exist in the transcript
//   sleep SECONDS                      pause the replay, output still logged
//   comment TEXT                       only recorded in the transcript log
//
// Patterns are plain substrings matched against the raw console bytes.
use bytes;
use fmt;
use fs;
use io;
use os;
use os::exec;
use strings;
use time;
use unix::poll;

type kind = enum u8 { expect, send, write, verify, sleep, comment };

type action = struct {
	kind: kind,
	text: str,
	timeout: i64,
};

type state = struct {
	out_r: io::file,
	in_w: io::file,
	proc: exec::process,
	log: io::file,
	transcript: []u8,
	consumed: size,
};

def CHUNK: size = 4096;
def TAIL: size = 1500;

fn fail(msg: str) never = {
	fmt::errorfln("qemu-session: FAIL: {}", msg)!;
	os::exit(1);
};

fn usage() never = {
	fmt::errorln(
		"usage: qemu-session -k KERNEL -d DISK -s SCRIPT -l LOG [-a APPEND] [-m MEM] [-x] [-n]")!;
	os::exit(1);
};

fn next_arg(args: []str, i: *size) str = {
	*i += 1;
	if (*i >= len(args)) usage();
	return args[*i];
};

fn parse_seconds(s: str) (i64 | void) = {
	if (len(s) == 0) return;
	let acc: i64 = 0;
	const b = strings::toutf8(s);
	for (let i = 0z; i < len(b); i += 1) {
		if (b[i] < '0' || b[i] > '9') return;
		if (acc > 1000000) return;
		acc = acc * 10 + (b[i] - '0'): i64;
	};
	return acc;
};

fn has_prefix(s: str, prefix: str) bool =
	bytes::hasprefix(strings::toutf8(s), strings::toutf8(prefix));

fn concat2(a: str, b: str) str = {
	return match (strings::concat(a, b)) {
	case let s: str => yield s;
	case => abort("out of memory");
	};
};

fn parse_script(path: str) []action = {
	const f = match (os::open(path)) {
	case let f: io::file => yield f;
	case => fail("script not found");
	};
	defer io::close(f)!;
	const raw = match (io::drain(f)) {
	case let b: []u8 => yield b;
	case => fail("cannot read script");
	};
	let actions: []action = [];
	const text = strings::fromutf8_unsafe(raw);
	const lines = match (strings::split(text, "\n")) {
	case let l: []str => yield l;
	case => abort("out of memory");
	};
	for (let i = 0z; i < len(lines); i += 1) {
		const line = strings::trim(lines[i], ' ', '\t', '\r');
		if (len(line) == 0 || has_prefix(line, "#")) {
			continue;
		};
		const sp = match (strings::index(line, " ")) {
		case void => continue;
		case let n: size => yield n;
		};
		const verb = strings::sub(line, 0, sp);
		const rest = strings::trim(strings::sub(line, sp), ' ', '\t');
		switch (verb) {
		case "expect" =>
			let timeout: i64 = 60;
			let pattern = rest;
			match (strings::rindex(rest, " timeout=")) {
			case void => void;
			case let at: size =>
				pattern = strings::trim(
					strings::sub(rest, 0, at), ' ', '\t');
				const tv = strings::sub(rest, at + 9);
				match (parse_seconds(tv)) {
				case void => fail("bad timeout in script");
				case let s: i64 => timeout = s;
				};
			};
			if (len(pattern) == 0) fail("expect needs a pattern");
			append(actions, action {
				kind = kind::expect,
				text = pattern,
				timeout = timeout,
			})!;
		case "send" =>
			append(actions, action {
				kind = kind::send,
				text = concat2(rest, "\n"),
				timeout = 0,
			})!;
		case "write" =>
			append(actions, action {
				kind = kind::write,
				text = rest,
				timeout = 0,
			})!;
		case "verify" =>
			if (len(rest) == 0) fail("verify needs a pattern");
			append(actions, action {
				kind = kind::verify,
				text = rest,
				timeout = 0,
			})!;
		case "sleep" =>
			match (parse_seconds(rest)) {
			case void => fail("sleep needs seconds");
			case let s: i64 =>
				append(actions, action {
					kind = kind::sleep,
					text = "",
					timeout = s,
				})!;
			};
		case "comment" =>
			append(actions, action {
				kind = kind::comment,
				text = rest,
				timeout = 0,
			})!;
		case =>
			fail("unknown script action");
		};
	};
	if (len(actions) == 0) fail("script is empty");
	return actions;
};

fn now_ms() i64 = {
	const t = time::now(time::clock::MONOTONIC);
	return t.sec * 1000 + t.nsec / 1_000_000;
};

fn tail_text(q: *state) str = {
	const start = if (len(q.transcript) > TAIL) len(q.transcript) - TAIL
		else 0z;
	return strings::fromutf8_unsafe(q.transcript[start..]);
};

fn stop(q: *state) void = {
	exec::kill(q.proc)!;
	let _ = exec::wait(&q.proc)!;
};

// Reads console output for up to `ms` milliseconds. Returns false on EOF.
// Data always lands in the transcript, so the caller re-checks its pattern
// after every call.
fn pump(q: *state, ms: i64) bool = {
	let fds = [poll::pollfd {
		fd = q.out_r,
		events = poll::event::POLLIN: i16,
		revents = 0,
	}];
	match (poll::poll(fds, ms * time::MILLISECOND)) {
	case let n: uint =>
		if (n == 0) return true;
		let buf: [CHUNK]u8 = [0...];
		match (io::read(q.out_r, buf)) {
		case let got: size =>
			if (got == 0) return false;
			io::writeall(q.log, buf[..got])!;
			append(q.transcript, buf[..got]...)!;
			return true;
		case io::EOF => return false;
		case => return false;
		};
	case => return true;
	};
};

fn run_expect(q: *state, act: action) void = {
	const needle = strings::toutf8(act.text);
	const deadline = now_ms() + act.timeout * 1000;
	for (true) {
		const rest = q.transcript[q.consumed..];
		match (bytes::index(rest, needle)) {
		case let at: size =>
			q.consumed += at + len(needle);
			return;
		case void => void;
		};
		if (now_ms() >= deadline) {
			fail("timeout waiting for pattern");
		};
		if (!pump(q, 200)) {
			if (bytes::index(q.transcript[q.consumed..], needle)
					is void) {
				fail("console closed while waiting");
			};
			return;
		};
	};
};

export fn main() void = {
	let kernel = "";
	let disk = "";
	let script_path = "";
	let log_path = "";
	let cmdline = "console=ttyS0,115200 root=/dev/vda rw init=/sbin/godel panic=-1";
	let memory = "256M";
	let extras = false;
	let noreboot = false;

	const args = os::args;
	let i = 1z;
	for (i < len(args); i += 1) {
		const a = args[i];
		if (a == "-k" || a == "--kernel") {
			kernel = next_arg(args, &i);
		} else if (a == "-d" || a == "--disk") {
			disk = next_arg(args, &i);
		} else if (a == "-s" || a == "--script") {
			script_path = next_arg(args, &i);
		} else if (a == "-l" || a == "--log") {
			log_path = next_arg(args, &i);
		} else if (a == "-a" || a == "--append") {
			cmdline = next_arg(args, &i);
		} else if (a == "-m" || a == "--memory") {
			memory = next_arg(args, &i);
		} else if (a == "-x" || a == "--extras") {
			extras = true;
		} else if (a == "-n" || a == "--no-reboot") {
			noreboot = true;
		} else {
			usage();
		};
	};
	if (kernel == "" || disk == "" || script_path == "" || log_path == "") {
		usage();
	};
	if (os::stat(kernel) is fs::error) fail("kernel not found");
	if (os::stat(disk) is fs::error) fail("disk not found");

	const actions = parse_script(script_path);

	// Child stdin comes from one pipe; stdout and stderr merge into the
	// other so the transcript is a single stream.
	const (in_r, in_w) = exec::pipe();
	const (out_r, out_w) = exec::pipe();
	defer io::close(in_r)!;
	defer io::close(out_w)!;

	let qemu_args: []str = [];
	append(qemu_args, "-m")!;
	append(qemu_args, memory)!;
	append(qemu_args, "-kernel")!;
	append(qemu_args, kernel)!;
	append(qemu_args, "-drive")!;
	append(qemu_args, concat2(concat2("file=", disk), ",format=raw,if=virtio"))!;
	append(qemu_args, "-append")!;
	append(qemu_args, cmdline)!;
	append(qemu_args, "-nographic")!;
	if (extras) {
		append(qemu_args, "-drive")!;
		append(qemu_args, "file=.image/home.ext4,format=raw,if=virtio")!;
		append(qemu_args, "-drive")!;
		append(qemu_args, "file=.image/var.ext4,format=raw,if=virtio")!;
	};
	if (noreboot) {
		append(qemu_args, "-no-reboot")!;
	};

	let cmd = exec::cmd("qemu-system-x86_64", qemu_args...)!;
	exec::addfile(&cmd, os::stdin_file, in_r)!;
	exec::addfile(&cmd, os::stdout_file, out_w)!;
	exec::addfile(&cmd, os::stderr_file, out_w)!;

	const logf = match (os::create(log_path, 0o644)) {
	case let f: io::file => yield f;
	case => fail("cannot create transcript log");
	};

	let q = state {
		out_r = out_r,
		in_w = in_w,
		proc = match (exec::start(&cmd)) {
		case let p: exec::process => yield p;
		case => fail("cannot start QEMU");
		},
		log = logf,
		transcript = [],
		consumed = 0,
	};

	for (let ai = 0z; ai < len(actions); ai += 1) {
		const act = actions[ai];
		switch (act.kind) {
		case kind::comment =>
			io::writeall(q.log, strings::toutf8(
				concat2("---- ", concat2(act.text, "\n"))))!;
		case kind::sleep =>
			time::sleep(act.timeout * time::SECOND);
		case kind::send, kind::write =>
			match (io::writeall(q.in_w, strings::toutf8(act.text))) {
			case size => void;
			case => fail("console closed before write");
			};
		case kind::verify =>
			// Drain whatever arrived while we were not reading
			// (e.g. during a sleep), then check the transcript.
			let found = false;
			for (let attempt = 0; attempt < 4; attempt += 1) {
				if (bytes::contains(q.transcript,
						strings::toutf8(act.text))) {
					found = true;
					break;
				};
				if (!pump(&q, 300)) {
					break;
				};
			};
			if (!found) fail("verify failed");
			io::writeall(q.log, strings::toutf8(
				concat2(concat2("---- verified: ", act.text), "\n")))!;
		case kind::expect =>
			run_expect(&q, act);
		};
	};

	// Give trailing output a moment, then terminate QEMU unless it
	// already exited (a poweroff in the script exits QEMU by itself).
	if (pump(&q, 1000)) {
		stop(&q);
	} else {
		let _ = exec::wait(&q.proc)!;
	};
	io::close(q.log)!;
	fmt::errorfln("qemu-session: OK ({} bytes transcript)",
		len(q.transcript): i64)!;
};
