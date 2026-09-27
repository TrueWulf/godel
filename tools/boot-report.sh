#!/bin/sh
# boot-report: extract boot and shutdown timings from a Godel supervisor
# log. Every supervisor line carries a [T+Nms] prefix (monotonic clock,
# roughly kernel-relative), so the whole timeline is computable offline:
#
#   sh tools/boot-report.sh /var/log/godel/supervisor.log
#   sh tools/boot-report.sh .image/soak/transcript.log
#
# Handles logs containing several boots (soak transcripts): one report
# block per "Godel <ver>: starting" segment. Exit 1 if no stamped lines
# are found (pre-0.9.4 logs).
set -eu

[ $# = 1 ] || { echo "usage: sh tools/boot-report.sh SUPERVISOR-LOG" >&2; exit 2; }
[ -r "$1" ] || { echo "boot-report: cannot read $1" >&2; exit 1; }

# AWK is replaceable so the busybox awk used by CI can be exercised on
# any host: AWK=busybox awk sh tools/test-boot-report.sh
AWK=${AWK:-awk}

exec "$AWK" '
function flush_boot(    n, names, k, total) {
	if (flushed || pid1_t < 0) return;
	flushed = 1;
	boot_n += 1;
	printf("boot %d: pid1=T+%dms", boot_n, pid1_t);
	if (ready_t >= 0) printf(" ready=T+%dms load=%dms", ready_t, ready_t - pid1_t);
	printf("\n");
	if (os_n > 0) {
		printf("  oneshots:");
		for (k = 1; k <= os_n; k += 1)
			printf(" %s %dms", os_order[k], oneshot[os_order[k]]);
		printf("\n");
	}
	if (svc_n > 0) {
		printf("  services:");
		for (k = 1; k <= svc_n; k += 1) {
			printf(" %s T+%dms", svc_order[k], svc_start[svc_order[k]]);
			if (svc_ready[svc_order[k]] >= 0)
				printf("(ready %dms)", svc_ready[svc_order[k]]);
		}
		printf("\n");
	}
	if (sd_begin >= 0) {
		total = (sd_end >= 0) ? sd_end - sd_begin : -1;
		printf("  shutdown: mode=%s begin=T+%dms", sd_mode, sd_begin);
		if (sd_deadline >= 0) printf(" deadline=%dms", sd_deadline);
		if (hung >= 0) printf(" hung=%d", hung);
		if (ro_ms >= 0) printf(" remount-ro=%dms", ro_ms);
		if (sync_ms >= 0) printf(" sync=%dms", sync_ms);
		if (total >= 0) printf(" total=%dms", total);
		printf("\n");
	}
}
function reset(   k) {
	pid1_t = -1; ready_t = -1;
	svc_n = 0; os_n = 0; sd_begin = -1; sd_end = -1; sd_deadline = -1;
	ro_ms = -1; sync_ms = -1; hung = -1; sd_mode = ""; flushed = 0;
	for (k in oneshot) delete oneshot[k];
	for (k in seen) delete seen[k];
	for (k in oseen) delete oseen[k];
	for (k in svc_ready) delete svc_ready[k];
}
BEGIN {
	reset();
	stamped = 0;
}
{
	if (match($0, /^\[T\+[0-9]+ms\] /)) {
		stamped = 1;
		t = substr($0, RSTART + 3, RLENGTH - 7) + 0;
		sub(/^\[T\+[0-9]+ms\] /, "");
	} else next;
	if (/^Godel [0-9][^ ]*: starting$/) { flush_boot(); reset(); pid1_t = t; next; }	if (pid1_t < 0) pid1_t = t;
	if (match($0, /^Godel: ready in [0-9]+ ms; /)) ready_t = t;
	if (match($0, /^godel: started [^ ]+ \(pid [0-9]+\)$/)) {
		name = $0;
		sub(/^godel: started /, "", name);
		sub(/ \(pid [0-9]+\)$/, "", name);
		if (!(name in seen)) {
			svc_n += 1;
			svc_order[svc_n] = name;
			seen[name] = 1;
			svc_ready[name] = -1;
		}
		svc_start[name] = t;
		next;
	}
	if (match($0, /^godel: [^ ]+ is ready after [0-9]+ ms$/)) {
		name = $0;
		sub(/^godel: /, "", name);
		sub(/ is ready after [0-9]+ ms$/, "", name);
		if (name in svc_ready) {
			ms = $0;
			sub(/^.* is ready after /, "", ms);
			sub(/ ms$/, "", ms);
			svc_ready[name] = ms + 0;
		}
		next;
	}
	if (match($0, /^godel: [^ ]+ exited cleanly after [0-9]+ ms$/)) {
		name = $0; ms = $0;
		sub(/^godel: /, "", name);
		sub(/ exited cleanly after [0-9]+ ms$/, "", name);
		sub(/^.* exited cleanly after /, "", ms);
		sub(/ ms$/, "", ms);
		if (!(name in oseen)) {
			os_n += 1;
			os_order[os_n] = name;
			oseen[name] = 1;
		}
		oneshot[name] = ms + 0;
		next;
	}
	if (match($0, /^Godel: shutting down \([a-z]+\)$/)) {
		mode = $0;
		sub(/^Godel: shutting down \(/, "", mode);
		sub(/\)$/, "", mode);
		sd_begin = t; sd_mode = mode; next;
	}
	if (match($0, /^godel: shutdown deadline in [0-9]+ ms$/)) {
		ms = $0; sub(/^.* deadline in /, "", ms); sub(/ ms$/, "", ms);
		sd_deadline = ms + 0; next;
	}
	if (match($0, /^godel: sending SIGKILL to remaining services \([0-9]+ hung\)$/)) {
		ms = $0; sub(/^.* \(/, "", ms); sub(/ hung\)$/, "", ms);
		hung = ms + 0; next;
	}
	if (match($0, /^godel: remount-ro took [0-9]+ ms; sync took [0-9]+ ms$/)) {
		ms = $0;
		ro_ms = ms;
		sub(/^godel: remount-ro took /, "", ro_ms);
		sub(/ ms; sync took [0-9]+ ms$/, "", ro_ms);
		ro_ms += 0;
		sync_ms = ms;
		sub(/^.* sync took /, "", sync_ms);
		sub(/ ms$/, "", sync_ms);
		sync_ms += 0;
		next;
	}
	if (/^Godel: rebooting now$/ || /^Godel: powering off now$/) sd_end = t;
}
END {
	if (!stamped) {
		print "boot-report: no [T+Nms] stamps found; logs are pre-0.9.4" > "/dev/stderr";
		exit 1;
	}
	flush_boot();
}
' "$1"
