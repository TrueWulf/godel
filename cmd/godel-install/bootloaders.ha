use fmt;
use fs;
use io;
use memio;
use os;
use os::exec;
use strings;

const BL_BEGIN: str = "# >>> godel begin";
const BL_END: str = "# <<< godel end";

fn install_usage() never = {
	die("usage: bin/godel-install --bootloader grub|limine|extlinux|systemd-boot|refind [--dry-run] [--force]");
};

fn bootloader_known(name: str) bool = {
	return switch (name) {
	case "grub", "limine", "extlinux", "systemd-boot", "refind" => yield true;
	case => yield false;
	};
};

fn bootloader_phase(c: *ctx, initrd: str, bootloader: str) void = {
	switch (bootloader) {
	case "grub" => bl_grub(c, initrd);
	case "limine" => bl_limine(c, initrd);
	case "extlinux" => bl_extlinux(c, initrd);
	case "systemd-boot" => bl_systemd_boot(c, initrd);
	case "refind" => bl_refind(c, initrd);
	case => void;
	};
};

fn bl_not_detected(c: *ctx, name: str) never = {
	let fbuf: [256]u8 = [0...];
	dief(fmt::bsprintf(fbuf,
		"bootloader '{}' not detected; refusing to guess", name)!);
};

fn bl_find_file(c: *ctx, paths: []str) (void | str) = {
	for (let i = 0z; i < len(paths); i += 1) {
		if (have(c, paths[i])) return paths[i];
	};
	return;
};

fn bl_find_dir(c: *ctx, paths: []str) (void | str) = {
	for (let i = 0z; i < len(paths); i += 1) {
		if (bl_have_dir(c, paths[i])) return paths[i];
	};
	return;
};

fn bl_have_dir(c: *ctx, p: str) bool = {
	const full = joined(c, p);
	defer free(full);
	match (os::stat(full)) {
	case let st: fs::filestat => return fs::isdir(st.mode);
	case => return false;
	};
};

fn bl_put(w: *memio::stream, s: str, args: fmt::field...) (size | io::error) = {
	const n = fmt::fprintf(w, s, args...)?;
	fmt::fprint(w, "\n")?;
	return n;
};

fn bl_dry(c: *ctx, msg: str) void = {
	fmt::printfln("  [dry-run] {}", msg)!;
};

fn bl_backup(c: *ctx, src: str, bakname: str) void = {
	const dst = strings::concat(c.root, "/etc/godel/backups/",
		bakname, "-", c.stamp)!;
	defer free(dst);
	if (c.dryrun) {
		bl_dry(c, "backup");
		return;
	};
	copy_file(src, dst, 0o644);
};

fn bl_read(path: str) str = {
	match (read_small_file(path)) {
	case void => {
		let fbuf: [256]u8 = [0...];
		dief(fmt::bsprintf(fbuf, "cannot read {}", path)!);
	};
	case let s: str => return s;
	};
};

fn bl_count_lines(path: str, needle: str) size = {
	const content = bl_read(path);
	defer free(content);
	const lines = strings::split(content, "\n")!;
	defer free(lines);
	let n = 0z;
	for (let i = 0z; i < len(lines); i += 1) {
		if (strings::contains(lines[i], needle)) n += 1;
	};
	return n;
};

fn bl_has_line(path: str, want: str) bool = {
	const content = bl_read(path);
	defer free(content);
	const lines = strings::split(content, "\n")!;
	defer free(lines);
	for (let i = 0z; i < len(lines); i += 1) {
		if (lines[i] == want) return true;
	};
	return false;
};

fn bl_has_prefix_line(path: str, prefix: str) bool = {
	const content = bl_read(path);
	defer free(content);
	const lines = strings::split(content, "\n")!;
	defer free(lines);
	for (let i = 0z; i < len(lines); i += 1) {
		if (strings::hasprefix(lines[i], prefix)) return true;
	};
	return false;
};

fn bl_rewrite(path: str, block: str, mode: fs::mode) void = {
	const content = bl_read(path);
	defer free(content);
	let out = memio::dynamic();
	defer io::close(&out)!;
	const lines = strings::split(content, "\n")!;
	defer free(lines);
	let skip = false;
	for (let i = 0z; i < len(lines); i += 1) {
		if (lines[i] == BL_BEGIN) {
			skip = true;
			continue;
		};
		if (skip && lines[i] == BL_END) {
			skip = false;
			continue;
		};
		if (!skip) fmt::fprintln(&out, lines[i])!;
	};
	fmt::fprint(&out, block)!;
	write_file(path, memio::string(&out)!, mode);
};

fn bl_is_mountpoint(p: str) bool = {
	const mi = match (read_small_file("/proc/self/mountinfo")) {
	case void => return false;
	case let s: str => yield s;
	};
	defer free(mi);
	const lines = strings::split(mi, "\n")!;
	defer free(lines);
	for (let i = 0z; i < len(lines); i += 1) {
		const f = strings::split(lines[i], " ")!;
		defer free(f);
		if (len(f) >= 5 && f[4] == p) return true;
	};
	return false;
};

fn bl_basename(s: str) str = {
	match (strings::rindex(s, '/')) {
	case let i: size => return strings::sub(s, i + 1);
	case void => return s;
	};
};

fn bl_grub_cmd() (void | str) = {
	const cmd = os::tryenv("GRUB_MKCONFIG", "grub-mkconfig");
	if (strings::contains(cmd, "/")) {
		match (os::access(cmd, os::amode::X_OK)) {
		case let ok: bool =>
			if (ok) return cmd;
		case =>
			return;
		};
	};
	match (exec::lookup(cmd)) {
	case let p: str => return p;
	case => return;
	};
};

fn bl_pair_on(conf_rel: str, kernel: str, initrd: str,
		mount: str, label: str) (str, str) = {
	if (strings::hasprefix(kernel, mount) && strings::hasprefix(initrd, mount)) {
		return (strings::trimprefix(kernel, mount),
			strings::trimprefix(initrd, mount));
	};
	let fbuf: [256]u8 = [0...];
	dief(fmt::bsprintf(fbuf,
		"{} config is on {} but kernel/initrd are not on that partition",
		label, mount)!);
};

fn bl_adjust_paths(conf_rel: str, c: *ctx, initrd: str, label: str) (str, str) = {
	if (strings::hasprefix(conf_rel, "/boot/efi/")) {
		return bl_pair_on(conf_rel, c.kernel, initrd, "/boot/efi/", label);
	};
	if (strings::hasprefix(conf_rel, "/efi/")) {
		return bl_pair_on(conf_rel, c.kernel, initrd, "/efi/", label);
	};
	if (strings::hasprefix(conf_rel, "/boot/") && bl_is_mountpoint(joined(c, "/boot"))) {
		return (strings::trimprefix(c.kernel, "/boot"),
			strings::trimprefix(initrd, "/boot"));
	};
	return (c.kernel, initrd);
};

fn bl_root_uuid(c: *ctx) str = {
	if (strings::hasprefix(c.rootarg, "UUID=")) {
		return strings::trimprefix(c.rootarg, "UUID=");
	};
	if (strings::hasprefix(c.rootarg, "/dev/")) {
		const child = match (exec::cmd("blkid", "-s", "UUID", "-o", "value",
				c.rootarg)) {
		case let ch: exec::command => yield ch;
		case => return "";
		};
		let mut = &child;
		const (read, write) = exec::pipe();
		exec::addfile(mut, os::stdout_file, write)!;
		const proc = match (exec::start(mut)) {
		case let p: exec::process => yield p;
		case => return "";
		};
		io::close(write)!;
		const data = match (io::drain(read)) {
		case let d: []u8 => yield d;
		case => return "";
		};
		defer free(data);
		io::close(read)!;
		let _ = exec::wait(&proc);
		const s = match (strings::fromutf8(data)) {
		case let s: str => yield s;
		case => return "";
		};
		return strings::dup(strings::trim(s))!;
	};
	return "";
};

fn bl_grub(c: *ctx, initrd: str) void = {
	const mk = match (bl_grub_cmd()) {
	case void => bl_not_detected(c, "grub");
	case let m: str => yield m;
	};
	if (!bl_have_dir(c, "/boot/grub") || !have(c, "/etc/grub.d/40_custom")) {
		bl_not_detected(c, "grub");
	};
	const custom = joined(c, "/etc/grub.d/40_custom");
	defer free(custom);
	const grubcfg = joined(c, "/boot/grub/grub.cfg");
	defer free(grubcfg);

	bl_backup(c, custom, "40_custom.bak");
	bl_backup(c, grubcfg, "grub.cfg.bak");

	const uuid = bl_root_uuid(c);
	let krel = c.kernel;
	let irel = initrd;
	if (bl_is_mountpoint(joined(c, "/boot"))) {
		krel = strings::trimprefix(c.kernel, "/boot");
		irel = strings::trimprefix(initrd, "/boot");
	};

	if (c.dryrun) {
		bl_dry(c, "add 'godel (test)' to the grub custom menu");
		return;
	};

	let b = memio::dynamic();
	defer io::close(&b)!;
	fmt::fprintln(&b, BL_BEGIN)!;
	fmt::fprintln(&b, "menuentry 'godel (test)' --class godel --id gnulinux-godel-test {")!;
	fmt::fprintln(&b, "\tload_video")!;
	fmt::fprintln(&b, "\tinsmod gzio")!;
	fmt::fprintln(&b, "\tinsmod part_msdos")!;
	fmt::fprintln(&b, "\tinsmod part_gpt")!;
	switch (c.rootfstype) {
	case "btrfs" => fmt::fprintln(&b, "\tinsmod btrfs")!;
	case "xfs" => fmt::fprintln(&b, "\tinsmod xfs")!;
	case "f2fs" => fmt::fprintln(&b, "\tinsmod f2fs")!;
	case => fmt::fprintln(&b, "\tinsmod ext2")!;
	};
	if (uuid != "") {
		bl_put(&b, "\tsearch --no-floppy --fs-uuid --set=root {}", uuid)!;
	};
	bl_put(&b, "\techo\t'Loading {} with godel as init ...'",
		bl_basename(c.kernel))!;
	bl_put(&b, "\tlinux\t{} root={} ro init=/usr/local/sbin/godel",
		krel, c.rootarg)!;
	fmt::fprintln(&b, "\techo\t'Loading initial ramdisk ...'")!;
	bl_put(&b, "\tinitrd\t{}", irel)!;
	fmt::fprintln(&b, "}")!;
	fmt::fprintln(&b, BL_END)!;
	bl_rewrite(custom, memio::string(&b)!, 0o755);
	info("entry appended to the grub custom menu");

	bl_run_or_die(c, mk, "-o", grubcfg);

	const n = bl_count_lines(grubcfg, "menuentry 'godel (test)'");
	if (n != 1) {
		let fbuf: [256]u8 = [0...];
		dief(fmt::bsprintf(fbuf,
			"expected exactly 1 'godel (test)' entry in grub.cfg, found {}",
			n)!);
	};
	info("verified: 1 'godel (test)' entry in grub.cfg");
};

fn bl_run_or_die(c: *ctx, cmd: str, args: str...) void = {
	if (c.dryrun) {
		let buf = memio::dynamic();
		defer io::close(&buf)!;
		fmt::fprintf(&buf, "  [dry-run] {}", cmd)!;
		for (let i = 0z; i < len(args); i += 1) {
			fmt::fprintf(&buf, " {}", args[i])!;
		};
		fmt::println(memio::string(&buf)!)!;
		return;
	};
	const child = match (exec::cmd(cmd, args...)) {
	case let ch: exec::command => yield ch;
	case => die("cannot execute the bootloader helper");
	};
	let mut = &child;
	const proc = match (exec::start(mut)) {
	case let p: exec::process => yield p;
	case => die("cannot execute the bootloader helper");
	};
	const st = match (exec::wait(&proc)) {
	case let s: exec::status => yield s;
	case => die("bootloader helper did not finish");
	};
	if (exec::check(&st) is exec::exit_status) {
		die("bootloader helper failed");
	};
};

const limine_paths: []str = [
	"/boot/limine/limine.conf", "/boot/limine.conf",
	"/limine/limine.conf", "/limine.conf",
	"/boot/efi/EFI/BOOT/limine.conf", "/boot/efi/limine/limine.conf",
	"/efi/EFI/BOOT/limine.conf", "/efi/limine/limine.conf",
	"/boot/limine/limine.cfg", "/boot/limine.cfg",
	"/limine/limine.cfg", "/limine.cfg",
];

fn bl_limine(c: *ctx, initrd: str) void = {
	const conf_rel = match (bl_find_file(c, limine_paths)) {
	case void => bl_not_detected(c, "limine");
	case let p: str => yield p;
	};
	const conf = joined(c, conf_rel);
	defer free(conf);

	bl_backup(c, conf, "limine.conf.bak");

	let legacy = false;
	if (bl_has_prefix_line(conf, "KERNEL_PATH=")
			|| bl_has_prefix_line(conf, "kernel_path=")) {
		legacy = true;
	};
	const (kpath, ipath) = bl_adjust_paths(conf_rel, c, initrd, "Limine");

	if (c.dryrun) {
		bl_dry(c, "add 'godel (test)' to the Limine config");
		return;
	};

	let b = memio::dynamic();
	defer io::close(&b)!;
	fmt::fprintln(&b, BL_BEGIN)!;
	if (legacy) {
		fmt::fprintln(&b, "/godel (test)")!;
		fmt::fprintln(&b, "PROTOCOL=linux")!;
		bl_put(&b, "KERNEL_PATH=boot():{}", kpath)!;
		bl_put(&b, "MODULE_PATH=boot():{}", ipath)!;
		bl_put(&b,
			"KERNEL_CMDLINE=root={} ro init=/usr/local/sbin/godel",
			c.rootarg)!;
	} else {
		fmt::fprintln(&b, "/godel (test)")!;
		fmt::fprintln(&b, "    protocol: linux")!;
		bl_put(&b, "    path: boot():{}", kpath)!;
		bl_put(&b, "    module_path: boot():{}", ipath)!;
		bl_put(&b, "    cmdline: root={} ro init=/usr/local/sbin/godel",
			c.rootarg)!;
	};
	fmt::fprintln(&b, BL_END)!;
	bl_rewrite(conf, memio::string(&b)!, 0o644);
	info("entry appended to the Limine config");

	if (!bl_has_line(conf, "/godel (test)")) {
		die("godel entry missing from the Limine config");
	};
	info("verified: 'godel (test)' in the Limine config");
};

const extlinux_paths: []str = [
	"/boot/extlinux/extlinux.conf",
	"/boot/syslinux/syslinux.cfg",
	"/boot/syslinux/syslinux.conf",
];

fn bl_extlinux(c: *ctx, initrd: str) void = {
	const conf_rel = match (bl_find_file(c, extlinux_paths)) {
	case void => bl_not_detected(c, "extlinux");
	case let p: str => yield p;
	};
	const conf = joined(c, conf_rel);
	defer free(conf);

	bl_backup(c, conf, "extlinux.conf.bak");

	if (c.dryrun) {
		bl_dry(c, "add 'godel (test)' to the extlinux config");
		return;
	};

	let b = memio::dynamic();
	defer io::close(&b)!;
	fmt::fprintln(&b, BL_BEGIN)!;
	fmt::fprintln(&b, "LABEL godel-test")!;
	fmt::fprintln(&b, "  MENU LABEL godel (test)")!;
	bl_put(&b, "  LINUX {}", c.kernel)!;
	bl_put(&b, "  INITRD {}", initrd)!;
	bl_put(&b, "  APPEND root={} ro init=/usr/local/sbin/godel",
		c.rootarg)!;
	fmt::fprintln(&b, BL_END)!;
	bl_rewrite(conf, memio::string(&b)!, 0o644);
	info("entry appended to the extlinux config");

	if (!bl_has_line(conf, "LABEL godel-test")) {
		die("godel entry missing from the extlinux config");
	};
	info("verified: LABEL godel-test in the extlinux config");
};

const sbt_dirs: []str = [
	"/boot/loader/entries",
	"/boot/efi/loader/entries",
	"/efi/loader/entries",
];

fn bl_systemd_boot(c: *ctx, initrd: str) void = {
	const dir_rel = match (bl_find_dir(c, sbt_dirs)) {
	case void => bl_not_detected(c, "systemd-boot");
	case let p: str => yield p;
	};
	const entry = strings::concat(c.root, dir_rel, "/godel-test.conf")!;
	defer free(entry);

	if (os::stat(entry) is fs::filestat) {
		bl_backup(c, entry, "godel-test.conf.bak");
	};

	let kpath = c.kernel;
	let ipath = initrd;
	if (dir_rel == "/boot/efi/loader/entries") {
		const (k, i) = bl_pair_on(dir_rel, c.kernel, initrd,
			"/boot/efi/", "systemd-boot");
		kpath = k;
		ipath = i;
	} else if (dir_rel == "/efi/loader/entries") {
		const (k, i) = bl_pair_on(dir_rel, c.kernel, initrd,
			"/efi/", "systemd-boot");
		kpath = k;
		ipath = i;
	} else {
		kpath = strings::trimprefix(c.kernel, "/boot");
		ipath = strings::trimprefix(initrd, "/boot");
	};

	if (c.dryrun) {
		bl_dry(c, "write the systemd-boot entry without changing loader.conf");
		return;
	};

	let b = memio::dynamic();
	defer io::close(&b)!;
	fmt::fprintln(&b, "title   godel (test)")!;
	bl_put(&b, "linux   {}", kpath)!;
	bl_put(&b, "initrd  {}", ipath)!;
	bl_put(&b, "options root={} ro init=/usr/local/sbin/godel",
		c.rootarg)!;
	write_file(entry, memio::string(&b)!, 0o644);
	info("entry written for systemd-boot");

	if (!bl_has_line(entry, "title   godel (test)")) {
		die("godel entry missing from the systemd-boot entry");
	};
	info("verified: systemd-boot entry");
};

const refind_paths: []str = [
	"/boot/EFI/refind/refind.conf",
	"/boot/efi/EFI/refind/refind.conf",
	"/efi/EFI/refind/refind.conf",
];

fn bl_refind(c: *ctx, initrd: str) void = {
	const conf_rel = match (bl_find_file(c, refind_paths)) {
	case void => bl_not_detected(c, "refind");
	case let p: str => yield p;
	};
	const conf = joined(c, conf_rel);
	defer free(conf);

	bl_backup(c, conf, "refind.conf.bak");

	const (kpath, ipath) = bl_adjust_paths(conf_rel, c, initrd, "rEFInd");

	if (c.dryrun) {
		bl_dry(c, "add 'godel (test)' to the rEFInd config");
		return;
	};

	let b = memio::dynamic();
	defer io::close(&b)!;
	fmt::fprintln(&b, BL_BEGIN)!;
	fmt::fprintln(&b, "menuentry \"godel (test)\" {")!;
	bl_put(&b, "    loader {}", kpath)!;
	bl_put(&b, "    initrd {}", ipath)!;
	bl_put(&b, "    options \"root={} ro init=/usr/local/sbin/godel\"",
		c.rootarg)!;
	fmt::fprintln(&b, "}")!;
	fmt::fprintln(&b, BL_END)!;
	bl_rewrite(conf, memio::string(&b)!, 0o644);
	info("entry appended to the rEFInd config");

	if (!bl_has_line(conf, "menuentry \"godel (test)\" {")) {
		die("godel entry missing from the rEFInd config");
	};
	info("verified: 'godel (test)' in the rEFInd config");
};
