use fmt;
use fs;
use io;
use memio;
use os;
use os::exec;
use strings;
use time;
use time::date;
use types;

type ctx = struct {
	root: str,
	cmdline_file: str,
	kernel: str,
	rootarg: str,
	rootdev: str,
	rootfstype: str,
	dryrun: bool,
	force: bool,
	stamp: str,
	stage: str,
	enabled: []str,
	skipped: []str,
	openrc_extra: []str,
};

fn die(msg: str) never = {
	fmt::errorfln("install: {}", msg)!;
	os::exit(1);
};

fn dief(buf: []u8, msg: str) never = {
	fmt::errorfln("install: {}", msg)!;
	os::exit(1);
};

fn fmsg(buf: []u8, msg: str) str = fmt::bsprintf(buf, msg)!;

fn info(msg: str) void = {
	let _ = fmt::printfln("install: {}", msg);
};

fn joined(c: *ctx, a: str) str = strings::concat(c.root, a)!;

fn have(c: *ctx, p: str) bool = {
	const full = joined(c, p);
	defer free(full);
	match (os::stat(full)) {
	case let st: fs::filestat => return fs::isfile(st.mode);
	case => return false;
	};
};

fn path_of(c: *ctx, p: str) str = joined(c, p);

fn read_small_file(path: str) (void | str) = {
	const f = match (os::open(path)) {
	case let f: io::file => yield f;
	case => return;
	};
	defer io::close(f)!;
	const d = match (io::drain(f)) {
	case let d: []u8 => yield d;
	case => return;
	};
	defer free(d);
	const text = match (strings::fromutf8(d)) {
	case let s: str => yield s;
	case => return;
	};
	return strings::dup(text)!;
};

fn release_value(content: str, key: str) str = {
	const lines = strings::split(content, "\n")!;
	defer free(lines);
	let result = "";
	for (let i = 0z; i < len(lines); i += 1) {
		const line = lines[i];
		if (!strings::hasprefix(line, key)) continue;
		const rest = strings::sub(line, len(key), strings::end);
		if (!strings::hasprefix(rest, "=")) continue;
		result = strings::trim(strings::sub(rest, 1, strings::end), '"');
	};
	return result;
};

fn distro_ok(id: str, id_like: str) bool = {
	const known = ["artix", "arch", "void", "alpine", "debian", "ubuntu",
		"fedora", "gentoo"];
	for (let i = 0z; i < len(known); i += 1) {
		if (id == known[i]) return true;
	};
	return strings::hasprefix(id, "opensuse")
		|| strings::contains(id_like, "arch")
		|| strings::contains(id_like, "debian");
};

const openrc_mapped = [
	"devfs", "mdev", "mdevd", "udev", "udev-trigger", "hwdrivers",
	"sysctl", "sysfs", "sysfsconf", "hostname", "swap", "localmount",
	"root", "fsck", "procfs", "loopback", "net.lo", "hwclock", "swclock",
	"urandom", "seedrng", "savecache", "dmesg", "klogd", "termencoding",
	"keymaps", "consolefont",
];

fn openrc_mapped_entry(name: str) bool = {
	for (let i = 0z; i < len(openrc_mapped); i += 1) {
		if (name == openrc_mapped[i]) return true;
	};
	return false;
};

fn dir_names_sorted(path: str) []str = {
	let names: []str = [];
	const entries = match (os::readdir(path)) {
	case let e: []fs::dirent => yield e;
	case => return names;
	};
	defer fs::dirents_free(entries);
	for (let i = 0z; i < len(entries); i += 1) {
		append(names, strings::dup(entries[i].name)!)!;
	};
	for (let i = 1z; i < len(names); i += 1) {
		const key = names[i];
		let j = i;
		for (j > 0 && strings::compare(names[j - 1], key) > 0) {
			names[j] = names[j - 1];
			j -= 1;
		};
		names[j] = key;
	};
	return names;
};

fn openrc_report(c: *ctx) void = {
	const rl_root = path_of(c, "/etc/runlevels");
	if (!(os::stat(rl_root) is fs::filestat)) return;
	info("OpenRC runlevels found; reading them as a capability source (never executed)");
	const levels = ["sysinit", "boot", "default"];
	for (let l = 0z; l < len(levels); l += 1) {
		const rl_path = strings::concat("/etc/runlevels/", levels[l])!;
		defer free(rl_path);
		const rl_dir = joined(c, rl_path);
		const names = dir_names_sorted(rl_dir);
		if (len(names) == 0) continue;
		let line = strings::concat("  runlevel ", levels[l], ": ")!;
		let used = len(line);
		let truncated = false;
		for (let i = 0z; i < len(names); i += 1) {
			const piece = strings::concat(" ", names[i])!;
			defer free(piece);
			if (used + len(piece) > 160) {
				truncated = true;
				break;
			};
			const grown = strings::concat(line, piece)!;
			free(line);
			line = grown;
			used += len(piece);
		};
		if (truncated) {
			const dots = strings::concat(line, " ...")!;
			free(line);
			line = dots;
		};
		fmt::printfln("install: {}", line)!;
		free(line);
		for (let i = 0z; i < len(names); i += 1) {
			if (!openrc_mapped_entry(names[i])) {
				append(c.openrc_extra, strings::dup(names[i])!)!;
			};
		};
	};
	if (len(c.openrc_extra) > 0) {
		info("  not transferred by this profile (OpenRC-only capabilities):");
		let joined_names = strings::concat("    ",
			strings::join(" ", c.openrc_extra...)!)!;
		defer free(joined_names);
		if (len(joined_names) > 202) {
			joined_names = strings::concat(
				strings::sub(joined_names, 0, 202), " ...")!;
		};
		fmt::printfln("install: {}", joined_names)!;
		info("  add godel services for these or accept the capability loss");
	};
};

fn first_token_prefix(content: str, prefix: str) (void | str) = {
	const tokens = strings::split(content, " ")!;
	defer free(tokens);
	for (let i = 0z; i < len(tokens); i += 1) {
		const tok = strings::trim(tokens[i], '\n', '\r', '\t');
		if (strings::hasprefix(tok, prefix)) {
			return strings::sub(tok, len(prefix), strings::end);
		};
	};
};

fn initramfs_for(c: *ctx, kernel: str) (void | str) = {
	const parts = strings::rsplitn(kernel, "/", 2)!;
	defer free(parts);
	let kname = if (len(parts) == 2) parts[1] else kernel;
	kname = strings::trimprefix(kname, "vmlinuz-");
	const candidates = [
		"/boot/initramfs-NAME.img",
		"/boot/initramfs-NAME",
		"/boot/initrd.img-NAME",
		"/boot/initrd-NAME.img",
		"/boot/initramfs.img",
		"/boot/initrd.img",
	];
	for (let i = 0z; i < len(candidates); i += 1) {
		const path = strings::replace(candidates[i], "NAME", kname)!;
		defer free(path);
		const full = joined(c, path);
		defer free(full);
		match (os::stat(full)) {
		case let st: fs::filestat =>
			if (fs::isfile(st.mode)) return strings::dup(path)!;
		case => continue;
		};
	};
};

fn in_list(list: []str, v: str) bool = {
	for (let i = 0z; i < len(list); i += 1) {
		if (list[i] == v) return true;
	};
	return false;
};

fn opts_have(opts: str, want: str) bool = {
	const fields = strings::split(opts, ",")!;
	defer free(fields);
	return in_list(fields, want);
};

type fstab = struct {
	mounts: []str,
	swaps: []str,
};

fn split_fields(line: str) []str = {
	let out: []str = [];
	const b = strings::toutf8(line);
	let start: (void | size) = void;
	for (let i = 0z; i <= len(b); i += 1) {
		const sp = i == len(b) || b[i] == ' ' || b[i] == '\t';
		if (!sp && start is void) {
			start = i;
		} else if (sp && start is size) {
			const word = strings::sub(line, start: size, i);
			append(out, strings::dup(word)!)!;
			start = void;
		};
	};
	return out;
};

const pseudo_fs = [
	"tmpfs", "devtmpfs", "proc", "procfs", "sysfs", "efivarfs", "devpts",
	"mqueue", "cgroup2",
];

fn parse_fstab(c: *ctx) fstab = {
	let out = fstab { mounts = [], swaps = [] };
	const path = path_of(c, "/etc/fstab");
	defer free(path);
	const content = match (read_small_file(path)) {
	case void => return out;
	case let s: str => yield s;
	};
	defer free(content);
	const lines = strings::split(content, "\n")!;
	defer free(lines);
	for (let i = 0z; i < len(lines); i += 1) {
		const line = strings::trim(lines[i], ' ', '\t', '\r');
		if (len(line) == 0 || strings::hasprefix(line, "#")) continue;
		const fields = split_fields(line);
		defer strings::freeall(fields);
		if (len(fields) < 3) continue;
		const opts = if (len(fields) >= 4) fields[3] else "";
		if (fields[2] == "swap") {
			if (!opts_have(opts, "noauto")) {
				append(out.swaps, strings::dup(fields[0])!)!;
			};
			continue;
		};
		if (fields[1] == "/") continue;
		if (in_list(pseudo_fs, fields[2])) continue;
		if (opts_have(opts, "noauto") || opts_have(opts, "bind")) continue;
		append(out.mounts, strings::dup(fields[1])!)!;
	};
	return out;
};

fn find_first(c: *ctx, paths: []str) (void | str) = {
	for (let i = 0z; i < len(paths); i += 1) {
		if (have(c, paths[i])) return paths[i];
	};
};

fn detect_root_fs(c: *ctx) void = {
	if (c.rootdev != "") return;
	if (find_first(c, ["/usr/bin/findmnt", "/bin/findmnt"]) is str) {
		c.rootdev = probe_findmnt("SOURCE");
		c.rootfstype = probe_findmnt("FSTYPE");
	};
};

fn probe_findmnt(field: str) str = {
	const child = match (exec::cmd("findmnt", "-n", "-o", field, "/")) {
	case let c: exec::command => yield c;
	case => return "";
	};
	let mut = &child;
	const (pipe_r, pipe_w) = exec::pipe();
	exec::addfile(mut, os::stdout_file, pipe_w)!;
	const proc = match (exec::start(mut)) {
	case let p: exec::process => yield p;
	case => exec::finish(mut);
		return "";
	};
	io::close(pipe_w)!;
	const out = match (io::drain(pipe_r)) {
	case let d: []u8 => yield d;
	case => yield []: []u8;
	};
	io::close(pipe_r)!;
	const st = match (exec::wait(&proc)) {
	case let s: exec::status => yield s;
	case => free(out);
		return "";
	};
	defer free(out);
	const text = match (strings::fromutf8(out)) {
	case let s: str => yield s;
	case => return "";
	};
	const lines = strings::split(text, "\n")!;
	defer free(lines);
	let result = "";
	if (len(lines) > 0) {
		result = strings::trim(lines[0], ' ', '\t');
	};
	exec::check(&st) as void;
	return result;
};

fn conf(c: *ctx, name: str, contents: str) void = {
	const path = strings::concat(c.stage, "/", name, ".conf")!;
	defer free(path);
	match (os::create(path, 0o644)) {
	case let f: io::file => {
		defer io::close(f)!;
		io::write(f, strings::toutf8(contents)) as size;
		io::write(f, ['\n']: []u8) as size;
	};
	case => {
		let fbuf: [256]u8 = [0...];
		dief(fbuf, fmt::bsprintf(fbuf, "cannot write {}", path)!);
	};
	};
	append(c.enabled, name)!;
};

fn skip(c: *ctx, name: str, reason: str) void = {
	append(c.skipped, strings::concat("[", name, ": ", reason, "]")!)!;
};

fn dir_entry_count(path: str) size = {
	const entries = match (os::readdir(path)) {
	case let e: []fs::dirent => yield e;
	case => return 0;
	};
	defer fs::dirents_free(entries);
	return len(entries);
};

fn write_file(path: str, contents: str, mode: fs::mode) void = {
	match (os::create(path, mode)) {
	case let f: io::file => {
		defer io::close(f)!;
		io::write(f, strings::toutf8(contents)) as size;
	};
	case let e: fs::error => {
		let fbuf: [512]u8 = [0...];
		dief(fbuf, fmt::bsprintf(fbuf, "cannot write {}: {}", path,
			fs::strerror(e))!);
	};
	};
};

fn copy_file(src: str, dst: str, mode: fs::mode) void = {
	const srcf = match (os::open(src)) {
	case let f: io::file => yield f;
	case => dief_read_fail(src);
	};
	defer io::close(srcf)!;
	const data = match (io::drain(srcf)) {
	case let d: []u8 => yield d;
	case => dief_read_fail(src);
	};
	defer free(data);
	ensure_parent(dst);
	match (os::create(dst, mode)) {
	case let f: io::file => {
		defer io::close(f)!;
		io::write(f, data) as size;
	};
	case let e: fs::error => {
		let fbuf: [512]u8 = [0...];
		dief(fbuf, fmt::bsprintf(fbuf, "cannot write {}: {}", dst,
			fs::strerror(e))!);
	};
	};
};

fn dief_read_fail(src: str) never = {
	let fbuf: [256]u8 = [0...];
	dief(fbuf, fmt::bsprintf(fbuf, "cannot read {}", src)!);
};

fn ensure_parent(dst: str) void = {
	const parts = strings::rsplitn(dst, "/", 2)!;
	defer free(parts);
	if (len(parts) == 2 && len(parts[0]) > 0) {
		os::mkdirs(parts[0], 0o755) is void;
	};
};

fn write_mount_helper(c: *ctx, path: str, mounts: []str) void = {
	let buf = memio::dynamic();
	defer io::close(&buf)!;
	fmt::fprintf(&buf, "#!/bin/sh\n")!;
	fmt::fprintf(&buf,
		"# generated by cmd/godel-install; mounts every fstab entry godel needs\n")!;
	fmt::fprintf(&buf, "for mp in")!;
	for (let i = 0z; i < len(mounts); i += 1) {
		fmt::fprintf(&buf, " '{}'", mounts[i])!;
	};
	fmt::fprintf(&buf, "; do\n")!;
	fmt::fprintf(&buf,
		"\tmountpoint -q \"$mp\" || {{ mount \"$mp\" || echo \"mount-fstab: failed $mp\"; }}\n")!;
	fmt::fprintf(&buf, "done\nexit 0\n")!;
	match (os::create(path, 0o755)) {
	case let f: io::file => {
		defer io::close(f)!;
		io::write(f, memio::buffer(&buf)) as size;
	};
	case => {
		let fbuf: [256]u8 = [0...];
		dief(fbuf, fmt::bsprintf(fbuf, "cannot write {}", path)!);
	};
	};
};

fn generate_profile(c: *ctx, fb: *fstab) void = {
	const mps = fb.mounts;
	const swaps = fb.swaps;

	const agetty = find_first(c, ["/usr/bin/agetty", "/sbin/agetty",
		"/bin/agetty"]);
	const dmesg = find_first(c, ["/usr/bin/dmesg", "/bin/dmesg"]);
	const ip = find_first(c, ["/usr/bin/ip", "/sbin/ip", "/bin/ip"]);

	let fsck_ok = false;
	const ext_types = ["ext2", "ext3", "ext4"];
	if (in_list(ext_types, c.rootfstype)
			&& find_first(c, ["/usr/sbin/fsck.ext4", "/sbin/fsck.ext4"])
				is str) {
		fsck_ok = true;
	};

	let after_fsck = "";
	if (fsck_ok) {
		const body = strings::concat([
			"[service \"fsck-root\"]\n",
			"command = /bin/sh -c \"fsck.ext4 -p ", c.rootdev,
			" 2>/dev/null || echo 'fsck-root: root mounted or unfixable; kernel journal recovery owns dirty state'\"\n",
			"type = oneshot\nrestart = never",
		]...)!;
		defer free(body);
		conf(c, "fsck-root", body);
		after_fsck = "after = fsck-root";
	};
	{
		const body = strings::concat([
			"[service \"rootfs-rw\"]\n",
			"command = /bin/mount -o remount,rw /\n",
			"type = oneshot\nrestart = never\n",
			after_fsck,
		]...)!;
		defer free(body);
		conf(c, "rootfs-rw", body);
	};

	if (len(mps) > 0) {
		conf(c, "mount-fstab",
			"[service \"mount-fstab\"]\ncommand = /bin/sh /etc/godel/lib/mount-fstab.sh\ntype = oneshot\nrestart = never\nafter = rootfs-rw");
	} else {
		skip(c, "mount-fstab", "no extra fstab mounts");
	};

	if (len(swaps) > 0) {
		conf(c, "swap-fstab",
			"[service \"swap-fstab\"]\ncommand = /bin/sh -c \"swapon -a 2>&1 || echo 'swap: swapon -a failed'\"\ntype = oneshot\nrestart = never\nafter = rootfs-rw");
	} else {
		skip(c, "swap-fstab", "no swap in fstab");
	};

	if (ip is str) {
		const body = strings::concat([
			"[service \"net-lo\"]\ncommand = ", ip: str,
			" link set up dev lo\ntype = oneshot\nrestart = never\nafter = rootfs-rw",
		]...)!;
		defer free(body);
		conf(c, "net-lo", body);
	} else {
		skip(c, "net-lo", "ip(8) not found");
	};

	let udev_trigger = false;
	const udevd = find_first(c, ["/usr/bin/udevd", "/sbin/udevd",
		"/usr/lib/udev/udevd", "/usr/lib/systemd/systemd-udevd"]);
	if (udevd is str) {
		const body = strings::concat([
			"[service \"udev\"]\ncommand = ", udevd: str,
			"\nrestart = on-failure\nrestart_delay = 1s\nafter = rootfs-rw",
		]...)!;
		defer free(body);
		conf(c, "udev", body);
		const udevadm = find_first(c, ["/usr/bin/udevadm", "/sbin/udevadm"]);
		if (udevadm is str) {
			udev_trigger = true;
			const body = strings::concat([
				"[service \"udev-trigger\"]\ncommand = /bin/sh -c \"",
				udevadm: str,
				" trigger -c add && ", udevadm: str,
				" settle\"\ntype = oneshot\nrestart = never\nafter = udev",
			]...)!;
			defer free(body);
			conf(c, "udev-trigger", body);
		} else {
			skip(c, "udev-trigger", "udevadm not found");
		};
	} else {
		const mdev = find_first(c, ["/bin/mdev", "/sbin/mdev",
			"/usr/bin/mdev", "/usr/sbin/mdev"]);
		if (mdev is str) {
			const mdev_conf = if (os::stat(path_of(c, "/etc/mdev.conf"))
					is fs::filestat) "present" else "missing";
			if (os::stat(path_of(c, "/proc/sys/kernel/hotplug"))
					is fs::filestat) {
				info("mdev hotplug helper: available");
			} else {
				info("mdev hotplug helper: unavailable (kernel without CONFIG_UEVENT_HELPER); devtmpfs + mdev -s cover device nodes");
			};
			const body = strings::concat([
				"[service \"mdev\"]\ncommand = /bin/sh -c \"if [ -e /proc/sys/kernel/hotplug ]; then echo ",
				mdev: str,
				" > /proc/sys/kernel/hotplug; fi; ", mdev: str,
				" -s\"\ntype = oneshot\nrestart = never\nafter = rootfs-rw",
			]...)!;
			defer free(body);
			conf(c, "mdev", body);
			fmt::printfln(
				"install: device manager: mdev ({}), /etc/mdev.conf {}",
				mdev: str, mdev_conf)!;
		} else {
			skip(c, "device-manager", "neither udevd nor mdev found");
		};
	};

	const sysctl = find_first(c, ["/usr/bin/sysctl", "/sbin/sysctl",
		"/usr/sbin/sysctl"]);
	if (sysctl is str) {
		const gate = if (udev_trigger) "udev-trigger" else "rootfs-rw";
		const body = strings::concat([
			"[service \"sysctl\"]\ncommand = ", sysctl: str,
			" --system\ntype = oneshot\nrestart = never\nafter = ", gate,
		]...)!;
		defer free(body);
		conf(c, "sysctl", body);
	} else {
		skip(c, "sysctl", "sysctl not found");
	};

	const dbus_daemon = find_first(c, ["/usr/bin/dbus-daemon",
		"/bin/dbus-daemon", "/usr/sbin/dbus-daemon"]);
	let after_desktop = "rootfs-rw";
	if (dbus_daemon is str) {
		const after_dbus = if (stage_has(c, "net-lo.conf"))
			"rootfs-rw net-lo" else "rootfs-rw";
		const body = strings::concat([
			"[service \"dbus\"]\ncommand = /bin/sh -c \"mkdir -p /run/dbus && exec ",
			dbus_daemon: str,
			" --system --nofork --nopidfile --print-address=3\"\nnotification-fd = 3\nreadiness_timeout = 15s\nrestart = on-failure\nrestart_delay = 1s\nafter = ",
			after_dbus,
		]...)!;
		defer free(body);
		conf(c, "dbus", body);
		after_desktop = "dbus";
	} else {
		skip(c, "dbus", "dbus-daemon not found");
	};

	const elogind = find_first(c, ["/usr/lib/elogind/elogind",
		"/usr/libexec/elogind/elogind", "/usr/lib64/elogind/elogind",
		"/usr/sbin/elogind"]);
	if (elogind is str) {
		const body = strings::concat([
			"[service \"elogind\"]\ncommand = ", elogind: str,
			"\nrestart = always\nrestart_delay = 1s\nshutdown_timeout = 2s\nlog = no\nafter = ",
			after_desktop,
		]...)!;
		defer free(body);
		conf(c, "elogind", body);
	} else {
		skip(c, "elogind", "elogind not found");
	};

	const nm = find_first(c, ["/usr/bin/NetworkManager",
		"/usr/sbin/NetworkManager"]);
	if (nm is str) {
		const body = strings::concat([
			"[service \"networkmanager\"]\ncommand = ", nm: str,
			" -n\nrestart = on-failure\nrestart_delay = 2s\nafter = ",
			after_desktop,
		]...)!;
		defer free(body);
		conf(c, "networkmanager", body);
	} else {
		const dhcpcd = find_first(c, ["/usr/bin/dhcpcd", "/sbin/dhcpcd",
			"/usr/sbin/dhcpcd"]);
		if (dhcpcd is str) {
			const body = strings::concat([
				"[service \"dhcpcd\"]\ncommand = ", dhcpcd: str,
				" -B -q\nrestart = on-failure\nrestart_delay = 2s\nafter = rootfs-rw",
			]...)!;
			defer free(body);
			conf(c, "dhcpcd", body);
		} else {
			skip(c, "network", "NetworkManager and dhcpcd not found");
		};
	};

	if (agetty is str) {
		let after_getty = strings::concat("rootfs-rw")!;
		if (udev_trigger) {
			const grown = strings::concat(after_getty, " udev-trigger")!;
			free(after_getty);
			after_getty = grown;
		};
		if (stage_has(c, "mdev.conf")) {
			const grown = strings::concat(after_getty, " mdev")!;
			free(after_getty);
			after_getty = grown;
		};
		if (stage_has(c, "mount-fstab.conf")) {
			const grown = strings::concat(after_getty, " mount-fstab")!;
			free(after_getty);
			after_getty = grown;
		};
		for (let tty = 1z; tty <= 2; tty += 1) {
			const digit = ['1', '2'][tty - 1];
			let namebuf: [16]u8 = [0...];
			const svcname = fmt::bsprintf(namebuf,
				"getty-tty{}", digit)!;
			let ttybuf: [8]u8 = [0...];
			const ttyname = fmt::bsprintf(ttybuf, "tty{}", digit)!;
			const body = strings::concat([
				"[service \"", svcname, "\"]\ncommand = ", agetty: str,
				" -L 38400 ", ttyname,
				" linux\nrestart = always\nrestart_delay = 1s\nshutdown_timeout = 2s\nlog = no\nafter = ",
				after_getty,
			]...)!;
			defer free(body);
			conf(c, svcname, body);
		};
		free(after_getty);
	} else {
		skip(c, "getty", "agetty not found");
	};

	if (dmesg is str) {
		const body = strings::concat([
			"[service \"logsync\"]\ncommand = /bin/sh -c \"while :; do cp -f /run/godel/godel.log /var/log/godel/supervisor.log 2>/dev/null; cp -f /run/godel/godel.log.1 /var/log/godel/supervisor.log.1 2>/dev/null; ",
			dmesg: str,
			" > /var/log/godel/dmesg.log 2>/dev/null; sleep 5; done\"\nrestart = always\nrestart_delay = 2s\nafter = rootfs-rw",
		]...)!;
		defer free(body);
		conf(c, "logsync", body);
	} else {
		skip(c, "logsync", "dmesg not found");
	};
};

fn stage_has(c: *ctx, name: str) bool = {
	const p = strings::concat(c.stage, "/", name)!;
	defer free(p);
	return os::stat(p) is fs::filestat;
};

fn validate(c: *ctx) void = {
	const child = match (exec::cmd("./bin/godel", "-t", c.stage)) {
	case let c: exec::command => yield c;
	case => die("cannot run bin/godel -t; run make first");
	};
	let mut = &child;
	const proc = match (exec::start(mut)) {
	case let p: exec::process => yield p;
	case => die("cannot run bin/godel -t; run make first");
	};
	const st = match (exec::wait(&proc)) {
	case let s: exec::status => yield s;
	case => die("bin/godel -t did not finish");
	};
	if (exec::check(&st) is exec::exit_status) {
		die("generated configuration failed validation");
	};
};

fn commit(c: *ctx) void = {
	const services = path_of(c, "/etc/godel/services.d");
	defer free(services);
	const backups = path_of(c, "/etc/godel/backups");
	defer free(backups);
	if (dir_entry_count(services) > 0) {
		const bak = strings::concat(backups, "/services.d.", c.stamp)!;
		defer free(bak);
		copy_tree(services, bak);
	};
	os::rmdirall(services) is void;
	const new_stage = strings::concat(services, ".new")!;
	defer free(new_stage);
	match (os::rename(new_stage, services)) {
	case void => void;
	case => die("cannot commit services.d");
	};
	copy_file("bin/godel", joined(c, "/usr/local/sbin/godel"), 0o755);
	copy_file("bin/godelctl", joined(c, "/usr/local/bin/godelctl"), 0o755);
	copy_file("man/godel.8",
		joined(c, "/usr/local/share/man/man8/godel.8"), 0o644);
	copy_file("man/godelctl.8",
		joined(c, "/usr/local/share/man/man8/godelctl.8"), 0o644);
};

fn copy_tree(src: str, dst: str) void = {
	os::mkdirs(dst, 0o755) is void;
	const entries = match (os::readdir(src)) {
	case let e: []fs::dirent => yield e;
	case => return;
	};
	defer fs::dirents_free(entries);
	for (let i = 0z; i < len(entries); i += 1) {
		const from = strings::concat(src, "/", entries[i].name)!;
		defer free(from);
		const to = strings::concat(dst, "/", entries[i].name)!;
		defer free(to);
		copy_file(from, to, 0o644);
	};
};

fn report(c: *ctx, kernel: str, initrd: str, rootarg: str,
		mkinit: (void | str)) void = {
	fmt::println("----------------------------------------------------------")!;
	info("godel installed:");
	fmt::printfln("install:   kernel/initrd : {} / {}", kernel, initrd)!;
	fmt::printfln("install:   root arg      : {}", rootarg)!;
	if (mkinit is str) {
		fmt::printfln("install:   initramfs gen : {} (already built: {})",
			mkinit: str, initrd)!;
	};
	let enabled = strings::join(" ", c.enabled...)!;
	defer free(enabled);
	fmt::printfln("install:   services      : {}", enabled)!;
	if (len(c.skipped) > 0) {
		let skipped = strings::join(" ", c.skipped...)!;
		defer free(skipped);
		fmt::printfln("install:   skipped       : {}", skipped)!;
	};
	info("next steps:");
	info("  1. reboot and pick 'godel (test)' in the boot menu");
	info("  2. log in on tty1; check: godelctl list");
	info("  3. to undo: remove the godel block from the bootloader config,");
	info("     regenerate it; backups are in /etc/godel/backups");
};

fn stamp_now() str = {
	const d = date::now();
	let buf = memio::dynamic();
	defer io::close(&buf)!;
	date::format(&buf, "%Y%m%d-%H%M%S", &d)!;
	const t = time::now(time::clock::REALTIME);
	fmt::fprintf(&buf, ".{}", t.nsec)!;
	return strings::concat(memio::string(&buf)!)!;
};

export fn main() void = {
	const args = os::args;
	let bootloader = "";
	let dryflag = false;
	let forceflag = false;
	let i = 1z;
	for (i < len(args); i += 1) {
		if (args[i] == "--bootloader") {
			if (i + 1 >= len(args)) install_usage();
			bootloader = args[i + 1];
			i += 1;
		} else if (args[i] == "--dry-run") {
			dryflag = true;
		} else if (args[i] == "--force") {
			forceflag = true;
		} else {
			install_usage();
		};
	};
	if (bootloader == "") install_usage();
	if (!bootloader_known(bootloader)) {
		let fbuf: [256]u8 = [0...];
		dief(fbuf, fmt::bsprintf(fbuf,
			"unknown bootloader '{}' (available: grub, limine, extlinux, systemd-boot, refind)",
			bootloader)!);
	};

	let c = ctx {
		root = os::tryenv("ROOT", ""),
		cmdline_file = os::tryenv("CMDLINE_FILE", "/proc/cmdline"),
		kernel = os::tryenv("KERNEL", ""),
		rootarg = os::tryenv("ROOTARG", ""),
		rootdev = os::tryenv("ROOTDEV", ""),
		rootfstype = os::tryenv("ROOTFSTYPE", ""),
		dryrun = dryflag || os::tryenv("GODEL_DRYRUN", "") == "1",
		force = forceflag || os::tryenv("GODEL_FORCE", "") == "1",
		stamp = os::tryenv("GODEL_STAMP", ""),
		stage = "",
		enabled = [],
		skipped = [],
		openrc_extra = [],
	};
	if (c.stamp == "") c.stamp = stamp_now();

	if (c.root == "") {
		os::mkdirs("/etc/godel", 0o755) is void;
		match (os::create("/etc/godel/.install-probe", 0o644)) {
		case let f: io::file =>
			io::close(f)!;
			os::remove("/etc/godel/.install-probe") is void;
		case =>
			die("must run as root (or set ROOT=<fixture> for a test run)");
		};
	};
	{
		const g = os::stat("bin/godel");
		const gc = os::stat("bin/godelctl");
		if (!(g is fs::filestat) || !(gc is fs::filestat)) {
			die("bin/godel or bin/godelctl missing; run make first");
		};
	};

	const release_path = path_of(&c, "/etc/os-release");
	defer free(release_path);
	const release = match (read_small_file(release_path)) {
	case void => die("/etc/os-release not readable");
	case let s: str => yield s;
	};
	defer free(release);
	const id = strings::dup(release_value(release, "ID"))!;
	defer free(id);
	const id_like = strings::dup(release_value(release, "ID_LIKE"))!;
	defer free(id_like);
	if (id == "nixos") {
		die("NixOS manages boot and services declaratively; use a native module, not this installer");
	};
	if (!distro_ok(id, id_like)) {
		if (!c.force) {
			die("unsupported distro; pass --force only after reviewing the generated dry-run");
		};
		info("continuing on unrecognised distro because --force was supplied");
	};
	fmt::printfln("install: detected distro: {}",
		if (id != "") id else "unknown")!;

	openrc_report(&c);

	if (c.kernel == "") {
		const cmdline = match (read_small_file(c.cmdline_file)) {
		case void => {
			let fbuf: [256]u8 = [0...];
			dief(fbuf, fmt::bsprintf(fbuf, "cannot read {}", c.cmdline_file)!);
		};
		case let s: str => yield s;
		};
		defer free(cmdline);
		const boot_image = match (first_token_prefix(cmdline, "BOOT_IMAGE=")) {
		case void => {
			let fbuf: [256]u8 = [0...];
			dief(fbuf, fmt::bsprintf(fbuf, "cannot detect BOOT_IMAGE in {}", c.cmdline_file)!);
		};
		case let k: str => yield strings::dup(k)!;
		};
		c.kernel = if (strings::hasprefix(boot_image, "/boot/")) {
			yield boot_image;
		} else if (strings::hasprefix(boot_image, "/")) {
			let fbuf: [256]u8 = [0...];
			dief(fbuf, fmt::bsprintf(fbuf,
				"unexpected BOOT_IMAGE path: {}", boot_image)!);
		} else {
			yield strings::concat("/boot/",
				strings::trimprefix(boot_image, "boot/"))!;
		};
		const root = match (first_token_prefix(cmdline, "root=")) {
		case void => die("cannot detect root= in the command line");
		case let r: str => yield strings::dup(r)!;
		};
		c.rootarg = root;
	};
	{
		const kfull = joined(&c, c.kernel);
		defer free(kfull);
		match (os::stat(kfull)) {
		case let st: fs::filestat =>
			if (!fs::isfile(st.mode)) {
				let fbuf: [256]u8 = [0...];
				dief(fbuf, fmt::bsprintf(fbuf, "kernel {} not found", kfull)!);
			};
		case => {
			let fbuf: [256]u8 = [0...];
			dief(fbuf, fmt::bsprintf(fbuf, "kernel {} not found", kfull)!);
		};
		};
	};
	const initrd = match (initramfs_for(&c, c.kernel)) {
	case void =>
		die("cannot find an initramfs for the kernel under /boot");
	case let p: str => yield p;
	};
	defer free(initrd);

	const mkinit = find_first(&c, ["/usr/sbin/mkinitfs", "/sbin/mkinitfs"]);

	{
		const cg = joined(&c, "/sys/fs/cgroup/cgroup.controllers");
		defer free(cg);
		if (!(os::stat(cg) is fs::filestat)) {
			die("cgroup v2 unavailable (no cgroup.controllers); godel requires a unified hierarchy");
		};
	};
	{
		const fst = joined(&c, "/etc/fstab");
		defer free(fst);
		if (!(os::stat(fst) is fs::filestat)) {
			let fbuf: [256]u8 = [0...];
			dief(fbuf, fmt::bsprintf(fbuf, "{} missing", fst)!);
		};
	};

	detect_root_fs(&c);
	const fb = parse_fstab(&c);
	defer {
		for (let i = 0z; i < len(fb.mounts); i += 1) free(fb.mounts[i]);
		free(fb.mounts);
		for (let i = 0z; i < len(fb.swaps); i += 1) free(fb.swaps[i]);
		free(fb.swaps);
	};

	{
		const services = joined(&c, "/etc/godel/services.d");
		defer free(services);
		if (!c.force && dir_entry_count(services) > 0) {
			die("/etc/godel/services.d is not empty; pass --force to replace it (a backup is kept)");
		};
	};

	if (c.dryrun) {
		const tmp = "/tmp/godel-install-core";
		os::rmdirall(tmp) is void;
		const helper_dir = strings::concat(tmp, "/helper")!;
		defer free(helper_dir);
		os::mkdirs(helper_dir, 0o755) is void;
		const sd_dir = strings::concat(tmp, "/services.d")!;
		defer free(sd_dir);
		os::mkdirs(sd_dir, 0o755) is void;
		c.stage = strings::concat(tmp, "/services.d")!;
	} else {
		const new_stage = joined(&c, "/etc/godel/services.d.new");
		os::rmdirall(new_stage) is void;
		os::mkdirs(new_stage, 0o755) is void;
		free(new_stage);
		const lib = joined(&c, "/etc/godel/lib");
		defer free(lib);
		os::mkdirs(lib, 0o755) is void;
		const backups = joined(&c, "/etc/godel/backups");
		defer free(backups);
		os::mkdirs(backups, 0o755) is void;
		const logdir = joined(&c, "/var/log/godel");
		defer free(logdir);
		os::mkdirs(logdir, 0o755) is void;
		c.stage = joined(&c, "/etc/godel/services.d.new");
	};

	generate_profile(&c, &fb);
	{
		const helper_path = if (c.dryrun) {
			const tmp = strings::sub(c.stage, 0,
				len(c.stage) - len("/services.d"));
			yield strings::concat(tmp, "/helper/mount-fstab.sh")!;
		} else {
			yield joined(&c, "/etc/godel/lib/mount-fstab.sh");
		};
		defer free(helper_path);
		write_mount_helper(&c, helper_path, fb.mounts);
	};

	const count = dir_entry_count(c.stage);
	if (count == 0) die("profile generated no services; aborting");
	validate(&c);
	fmt::printfln("install: profile validated: {} service(s)", count)!;

	if (!c.dryrun) commit(&c);

	report(&c, c.kernel, initrd, c.rootarg, mkinit);
	bootloader_phase(&c, initrd, bootloader);
};
