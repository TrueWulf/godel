# Next Session: Godel 0.9.1 — soak toward 1.0.0

## Language rule

All replies to the user must be in Russian. Code, commit messages, and
documentation stay in English.

## Current state (2026-09-15)

- **0.9.1 is released**: pushed to Codeberg (`origin`) and GitHub,
  tagged `v0.9.1` (commit `7333ff2`). Highlights: plain oneshot
  dependencies now hold dependents until completion (boot-race fix),
  `godelctl status --json` and `uptime`, `--version` on both binaries,
  `godel(8)`/`godelctl(8)` man pages (installed by `make install`),
  GitHub Actions CI mirroring Woodpecker, 18 scripted QEMU sessions
  (new: `oneshot-gate`), 71 unit tests.
- The login race is fixed but **not yet verified on the real machine**:
  after the reboot into `Artix Godel v3 (zen)` the getty waits for
  `mount-home` completion, fish reads its config, and the autostart
  block (session bus + `exec niri --session`) must run by itself.
  `~/.config/fish/config.fish` still logs login diagnostics to
  `~/.cache/godel-login.log` — keep it until autologin is confirmed on
  both kernels, then strip the instrumentation.
- `apply.sh` changes since last session: `getty-tty1/2` now have
  `mount-home` in `after`; `swap.conf` keeps swapon stderr (was
  `2>/dev/null`, which is why the SwapTotal=0 boot left no evidence).
- The machine is booted under Godel (PID 1 = godel, 17 services,
  restarts 0). Portals verified healthy under dinit earlier; re-verify
  under Godel: one `pgrep -af xdg-desktop-portal` set, Steam Flatpak,
  screencast and file-chooser dialogs.

## Open items (in priority order)

1. **Verify autologin after reboot** (zen first, then lts): no error on
   tty1, no manual `niri`. If anything still prints, read
   `~/.cache/godel-login.log`; also compare getty/elogind timings in
   fresh `/var/log/godel/supervisor.log`.
2. **Bug 5 closure test**: in the evening `doas godelctl poweroff`
   (already running 0.9.1 with the remount-ro fix); the next morning
   the machine MUST boot clean with no fsck. Formal close of the
   data-integrity incident.
3. **Portals** (after relogin): single portal set (`pgrep -af`), Steam
   Flatpak starts, screencast + file dialogs work. On failure:
   `flatpak run --command=bash com.valvesoftware.Steam -c
   'flatpak-spawn -vv true'`.
4. **swap**: with the new stderr logging, the next Godel boot's
   `swap.log` shows a real error if swapon fails again; check
   `/proc/meminfo` SwapTotal on boot.
5. **suspend/resume and power button**: never tested.
   `doas loginctl suspend`, wake, then `godelctl status` (all up,
   restarts 0), network, clock, niri alive. Power button last (elogind
   HandlePowerKey). Lid N/A (desktop).
6. **zen login delay**: check whether it persists after the gate fix —
   the old "lands late" symptom may have been the same race.
7. **vpn-cli**: the user's own console client for happd.

## Roadmap to 1.0.0

Stage 4 soak (weeks of daily driving on the real machine), every
deviation recorded. Blockers are data-loss or boot-lock bugs (bug 5
class); the default GRUB entry stays on dinit until none remain. Near
the end of the soak: AUR package (`godel-bin`; man pages already ship),
more distro example sets (Alpine: mdev paths, Void). 1.0.0 = quiet
weeks + no open blockers + docs current.

## Session protocol on the user's machine

- Persistent evidence in `/var/log/godel/` (mode 0600); `/run/godel/*`
  is tmpfs and dies with the boot. Do not cite `supervisor.log.1` as
  evidence about a previous boot without checking (logsync only
  overwrites it when the current boot rotates).
- `godelctl` refuses to signal PID 1 without `/run/godel/status`
  (dual-init safety). Never run `godelctl reload` under dinit.
- Host safety rules unchanged: never touch the dinit entries, the
  default boot entry, or the working bootloader config; all machine
  changes go through `~/godel-host/apply.sh` with backups; QEMU
  testing uses disposable images under `.image/` or /tmp.
- Commits go to both remotes (origin = Codeberg, github mirror);
  force-with-lease only after checking what diverged.
