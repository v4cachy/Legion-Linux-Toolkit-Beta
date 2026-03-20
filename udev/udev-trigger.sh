#!/usr/bin/env bash
# Called by udev when platform_profile changes (Fn+Q press)
# The daemon is already watching via polling — this is a belt-and-suspenders
# trigger that forces an immediate re-check without waiting for the poll interval.

# Read the new profile
PROFILE=$(cat /sys/firmware/acpi/platform_profile 2>/dev/null || echo "balanced")

# Apply it immediately via the daemon CLI
/usr/lib/legion-toolkit/legion-daemon.py "$PROFILE" &

exit 0
