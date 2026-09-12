Example service set for a small server or VM: network over
DHCP, ssh, cron, and local syslog.

Adapt before installing:

- sshd requires host keys and its privilege-separation
  directory: run `ssh-keygen -A` once and check that
  /var/empty (or your distribution's equivalent) exists.
- syslogd -n is busybox syntax; replace with your syslog
  daemon's foreground flag (syslog-ng -F, socklog, ...).
- daemon paths vary between distributions.

Install:

    cp *.conf /etc/godel/services.d/
    godel -t /etc/godel/services.d

Notes:

- sshd starts only after dhcpcd, so the machine is reachable
  on the network before the port opens.
- cronie and syslogd run foreground with their -n flags;
  daemons that insist on backgrounding cannot be supervised
  and should be started by a oneshot instead.
- A desktop variant of this set lives in ../desktop.
