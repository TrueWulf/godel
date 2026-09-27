#!/bin/sh
# Fixture test for tools/boot-report.sh: verifies the extracted metrics
# on a synthetic supervisor transcript covering two boots, readiness
# timestamps, oneshot durations, and a full shutdown profile.
set -eu

root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
cd "$root"

fx=$(mktemp -d /tmp/godel-boot-report.XXXXXX)
trap 'rm -rf "$fx"' EXIT

cat > "$fx/supervisor.log" <<'EOF'
[T+90ms] Godel 0.9.4: starting
[T+91ms] godel: cgroup v2 enabled
[T+92ms] godel: started fsck-root (pid 376)
[T+95ms] Godel: ready in 5 ms; 4 service(s) configured
[T+137ms] godel: fsck-root exited cleanly after 45 ms
[T+140ms] godel: started dbus (pid 404)
[T+204ms] godel: dbus is ready after 64 ms
[T+1300ms] godel: started getty-tty1 (pid 596)
[T+3000ms] Godel: shutting down (poweroff)
[T+3001ms] godel: shutdown deadline in 1000 ms
[T+3100ms] godel: dbus stopped
[T+3250ms] godel: sending SIGKILL to remaining services (1 hung)
[T+3260ms] godel: stubborn stopped
[T+3261ms] Godel: remounting filesystems read-only
[T+3265ms] godel: remount-ro took 3 ms; sync took 1 ms
[T+3266ms] Godel: powering off now
[T+4000ms] Godel 0.9.4: starting
[T+4005ms] Godel: ready in 4 ms; 1 service(s) configured
[T+4100ms] godel: beacon exited cleanly after 95 ms
[T+4200ms] godel: all services finished; powering off
[T+4201ms] Godel: shutting down (poweroff)
[T+4300ms] Godel: powering off now
EOF

out=$(sh tools/boot-report.sh "$fx/supervisor.log")
echo "$out"

echo "$out" | grep -q '^boot 1: pid1=T+90ms ready=T+95ms load=5ms$'
echo "$out" | grep -q '^  oneshots: fsck-root 45ms$'
echo "$out" | grep -q 'dbus T+140ms(ready 64ms)'
echo "$out" | grep -q 'getty-tty1 T+1300ms'
echo "$out" | grep -q '^  shutdown: mode=poweroff begin=T+3000ms deadline=1000ms hung=1 remount-ro=3ms sync=1ms total=266ms$'
echo "$out" | grep -q '^boot 2: pid1=T+4000ms ready=T+4005ms load=5ms$'
[ "$(echo "$out" | grep -c '^boot ')" = 2 ] ||
	{ echo "test-boot-report: expected exactly two boot blocks" >&2; exit 1; }

# a pre-0.9.4 log (no stamps) must fail loudly
printf 'Godel 0.9.2: starting\nGodel: ready in 7 ms\n' > "$fx/old.log"
if sh tools/boot-report.sh "$fx/old.log" >/dev/null 2>&1; then
	echo "test-boot-report: unstamped log should fail" >&2
	exit 1
fi

# missing file must fail
if sh tools/boot-report.sh "$fx/nonexistent.log" >/dev/null 2>&1; then
	echo "test-boot-report: missing file should fail" >&2
	exit 1
fi

echo "test-boot-report: all checks passed"
