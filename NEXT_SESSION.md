# Next Session: Godel 0.9.5.1 — code quality, dynamic service capacity

## Language rule

All replies to the user must be in Russian. Code, commit messages, and
documentation stay in English.

## Access notes (owner-provided, session start)

- The owner has pre-approved this session's actions and will confirm
  anything interactive (browser prompts, doas re-auth) without further
  discussion. Run `gh auth login -h github.com` at session start: if
  the stored token is invalid, launch the web flow and wait for the
  owner to finish it. Never ask for, echo, or store passwords in this
  repository or its history.
- After authorization succeeds: push main and the v0.9.5 tag to both
  remotes (origin = Codeberg, github mirror). Verify divergence first;
  only the release commits should be missing on GitHub.
- Machine changes still go only through `~/godel-host/apply.sh`; dinit
  entries, GRUB default/timeout/hidden policy stay untouchable; QEMU
  on disposable images only; power only via `doas godelctl
  reboot/poweroff`.

## Current state (2026-10-02)

- 0.9.5 is committed on main (`ee0d71a`) and pushed to Codeberg only;
  GitHub push is blocked on the expired `gh` token (see above). Tag
  `v0.9.5` is not yet created.
- Dirty-shutdown root cause fixed: final stray sweep in finish_shutdown
  (SIGKILL every userland process except PID 1, kernel threads/zombies
  skipped by empty /proc/PID/cmdline, fixed 150 ms teardown wait),
  shutdown evidence persisted to /var/log/godel/shutdown.log with
  per-mount remount-ro outcomes.
- Full matrix green: 71 unit tests, 8-backend fixture matrix, 19 QEMU
  sessions (incl. stray-sweep), sh -n, git diff --check.
- Machine still runs 0.9.4 binaries; the stray-sweep metal check is
  pending (see open items).

## Session goals (0.9.5.1 theme: code quality, no new subsystems)

1. **Metal verification of 0.9.5 first**: apply.sh upgrade to 0.9.5
   binaries, evening `doas godelctl poweroff`, next boot must show
   /home clean (no "recovering journal" in mount-home.log), mount-home
   dropping from ~2500 ms toward ~100 ms in boot-report. Tag v0.9.5
   only after this passes.
2. **Remove the 64-service limit (the owner's headline ask)**.
   Design constraints:
   - The no-allocation-after-boot invariant is kept: allocate the
     runtime tables (svcs, dying, notify_r, reaped) once, at config
     load, sized to the actual service count. After boot they are
     plain fixed pointers.
   - Hidden trap already identified: epoll tag packing. TAG_DYING_BASE
     = 0x100 and TAG_NOTIFY_BASE = 0x200 currently cap the service
     index at 8 bits (256). Rebase the tag layout before raising
     MAX_SERVICES (u64 has room; e.g. move special tags to 1<<40+).
   - Pick the new ceiling deliberately (256 fits the current tag
     space after rebasing; going beyond needs no new machinery once
     tags are relocated). Unit tests must cover 64+ and 256 services;
     keep the existing `sixty_four_services_fit...` test as the floor
     and add a capacity test for the new ceiling.
   - Update docs (architecture.md) to state "no fixed small limit;
     capacity scales with config at boot".
3. **boot-report -> Hare** (`godelctl boot-report` subcommand), the
   shell version retires after the harness switches; awk version is
   verified byte-identical under busybox awk.
4. **Installer core -> Hare** (`cmd/godel-install`): detect, capability
   discovery, service generation, staging; five bootloader backends
   stay POSIX plugins behind the bl_* contract; fixture matrix is the
   safety net.
5. **Trim pass on cmd/godel + godel/**: dead code audit, no-alloc
   invariants re-checked, test count must not drop below 71+new.
6. **udev settle** (~1.7 s): bounded, documented readiness strategy if
   it remains a gate after the mount-home win; getty gate, autologin
   ordering, shutdown safety untouched; tests required.

## Session protocol (unchanged)

- Persistent evidence in /var/log/godel/ (mode 0600); supervisor lines
  carry [T+Nms] since 0.9.4; shutdown.log exists since 0.9.5.
- godelctl refuses to signal PID 1 without /run/godel/status; never
  godelctl reload under dinit.
- Commits go to both remotes; force-with-lease only after checking
  what diverged. Never suggest reboot -f.
