#!/usr/bin/env python3
"""Ripcord drive watcher.

Reports the set of removable filesystems currently attached, one JSON object
per line, whenever that set changes.

Two things worth knowing about how this is written:

  * It never interprets an inotify event. udev does not create the entries in
    /dev/disk/by-uuid directly - it writes a hidden temporary name and then
    renames it into place - so a watcher listening for "a file was created"
    sees only the temporary name and never learns the real drive arrived.
    Rather than encode that quirk, an event here means nothing more than "go
    and look again", and the truth always comes from reading the directory.
    That makes the watcher correct regardless of how udev chooses to publish.

  * The event wait has a timeout, so the directory is re-read every couple of
    seconds even if no event ever arrives. This is not the polling the plugin
    set out to avoid: it is a directory read inside a process that is already
    running, not a command spawned from the shell. For a trigger whose whole
    job is to notice a removal, a missed event has to be survivable.

Everything read here comes off a filesystem this process does not control, so
sizes are bounded and anything unexpected is dropped rather than reported.
"""

import ctypes
import ctypes.util
import errno
import json
import os
import re
import select
import sys

BY_UUID = "/dev/disk/by-uuid"
BY_LABEL = "/dev/disk/by-label"
SYS_BLOCK = "/sys/class/block"

# A machine with more than this many attached filesystems is not a machine
# this plugin is being useful on; the cap exists so a malformed or hostile
# /dev cannot make the reported line grow without limit.
MAX_DRIVES = 64
MAX_NAME = 256

# Re-read even without an event. See the note above.
BACKSTOP_SECONDS = 2.0

IN_ATTRIB = 0x00000004
IN_MOVED_FROM = 0x00000040
IN_MOVED_TO = 0x00000080
IN_CREATE = 0x00000100
IN_DELETE = 0x00000200

WATCH_MASK = IN_ATTRIB | IN_MOVED_FROM | IN_MOVED_TO | IN_CREATE | IN_DELETE


def load_libc():
    name = ctypes.util.find_library("c") or "libc.so.6"
    return ctypes.CDLL(name, use_errno=True)


class Inotify:
    """The smallest inotify wrapper that does this job.

    Used deliberately instead of inotifywait so the plugin has no external
    dependency: the syscalls are in libc, which is already there.
    """

    def __init__(self):
        self.libc = load_libc()
        self.fd = self.libc.inotify_init1(os.O_CLOEXEC)
        if self.fd < 0:
            raise OSError(ctypes.get_errno(), "inotify_init1 failed")
        self.wd = -1

    def watch(self, path):
        if self.wd >= 0:
            return True
        wd = self.libc.inotify_add_watch(
            self.fd, path.encode("utf-8"), ctypes.c_uint32(WATCH_MASK)
        )
        if wd < 0:
            return False
        self.wd = wd
        return True

    def drain(self):
        """Consume pending events without parsing them."""
        try:
            os.read(self.fd, 8192)
        except OSError as exc:
            if exc.errno not in (errno.EAGAIN, errno.EINTR):
                raise

    def wait(self, timeout):
        try:
            ready, _, _ = select.select([self.fd], [], [], timeout)
        except (OSError, select.error):
            return False
        if ready:
            self.drain()
            return True
        return False


_UDEV_ESCAPE = re.compile(rb"\\x([0-9a-fA-F]{2})")


def unescape_udev(name):
    """Turn udev's escaped link name back into the label the user gave it.

    udev cannot put a space or a slash in a symlink name, so it writes those
    bytes as \\xNN - a volume called "Pop_OS 24.04 amd64" appears on disk as
    "Pop_OS\\x2024.04\\x20amd64". Showing that raw makes the pairing list
    unreadable for any drive whose name has a space in it, which is most of
    them.

    Decoded a byte at a time and then read as UTF-8, because a non-ASCII
    character arrives as several escapes that only mean something together.
    """
    raw = name.encode("utf-8", "surrogateescape")
    decoded = _UDEV_ESCAPE.sub(lambda m: bytes([int(m.group(1), 16)]), raw)
    return decoded.decode("utf-8", "replace")


def device_of(link_dir, name):
    """Resolve one /dev/disk/by-* entry to its bare device name."""
    try:
        target = os.readlink(os.path.join(link_dir, name))
    except OSError:
        return None
    return os.path.basename(target)


def read_links(link_dir):
    """Map device name -> entry name for a /dev/disk/by-* directory."""
    found = {}
    try:
        names = os.listdir(link_dir)
    except OSError:
        return found
    for name in names[: MAX_DRIVES * 4]:
        if len(name) > MAX_NAME:
            continue
        device = device_of(link_dir, name)
        if device:
            found[device] = name
    return found


def is_unpluggable(device, sys_block=SYS_BLOCK):
    """True when the device can be physically pulled out of the machine.

    Pairing is restricted to these: letting someone pair the disk their system
    runs from would arm a trap that can only ever fire by accident.

    The kernel's `removable` flag is necessary but not sufficient. USB flash
    sticks set it; USB SSDs and hard drives in enclosures usually do not, and
    those are exactly the drives somebody would put on a lanyard. So a device
    also counts if its sysfs path runs through the USB bus, which is true of
    anything plugged into a USB port whatever it calls itself.
    """
    try:
        resolved = os.path.realpath(os.path.join(sys_block, device))
    except OSError:
        return False

    # A partition resolves to .../sdb/sdb1 and the flag lives on the parent
    # disk; a whole-device filesystem resolves straight to .../sdb.
    for candidate in (resolved, os.path.dirname(resolved)):
        flag = os.path.join(candidate, "removable")
        try:
            with open(flag, "rb") as handle:
                if handle.read(8).strip() == b"1":
                    return True
        except OSError:
            continue

    # Path components rather than a substring search: a volume label or a
    # device name containing the letters "usb" must not qualify a drive that
    # is bolted inside the machine.
    parts = resolved.split(os.sep)
    for part in parts:
        if part == "usb" or part.startswith("usb"):
            # /sys/devices/pci.../usb1/1-2/... - the controller and the ports
            # beneath it both match, and nothing on an internal bus does.
            if part[3:].isdigit() or part == "usb":
                return True
    return False


def read_first_line(path, limit=256):
    try:
        with open(path, "rb") as handle:
            return handle.read(limit).decode("utf-8", "replace").strip()
    except OSError:
        return ""


def usb_node_of(disk):
    """Walk up from a disk to the USB device it hangs off, if any.

    The serial lives there rather than on the block device: a USB stick's
    SCSI-level `serial` and `wwid` are usually empty (measured - both are
    empty for a SanDisk 3.2Gen1), while the USB descriptor carries a real one.
    """
    try:
        path = os.path.realpath(os.path.join(SYS_BLOCK, disk, "device"))
    except OSError:
        return None
    # Bounded rather than while-True: a symlink loop would otherwise spin here.
    for _ in range(12):
        if not path or path == "/":
            return None
        if os.path.exists(os.path.join(path, "idVendor")) and os.path.exists(
            os.path.join(path, "serial")
        ):
            return path
        path = os.path.dirname(path)
    return None


def drive_identity(disk, first_uuid):
    """A key for the physical drive that survives reformatting it.

    Preferred in this order, because each is more stable than the next: the USB
    descriptor serial, the SCSI serial, the wwid, and only then a partition
    UUID - which is stable enough day to day but changes the moment the drive
    is reformatted, silently breaking a pairing. The prefix says which was
    used so the two can never collide.
    """
    node = usb_node_of(disk)
    if node:
        serial = read_first_line(os.path.join(node, "serial"))
        if serial:
            return "usb:" + serial[:MAX_NAME]

    for attribute in ("serial", "wwid"):
        value = read_first_line(os.path.join(SYS_BLOCK, disk, "device", attribute))
        if value:
            return "dev:" + value[:MAX_NAME]

    if first_uuid:
        return "uuid:" + first_uuid[:MAX_NAME]
    return ""


def describe(disk):
    """A human name for the drive, and its size in bytes."""
    node = usb_node_of(disk)
    product = read_first_line(os.path.join(node, "product")) if node else ""
    model = read_first_line(os.path.join(SYS_BLOCK, disk, "device", "model"))
    name = product or model or disk

    sectors = read_first_line(os.path.join(SYS_BLOCK, disk, "size"))
    try:
        size = int(sectors) * 512
    except (TypeError, ValueError):
        size = 0
    return name, size


def partitions_of(disk):
    """The partition device names belonging to a disk, in order."""
    base = os.path.join(SYS_BLOCK, disk)
    found = []
    try:
        for entry in sorted(os.listdir(base)):
            if entry.startswith(disk) and os.path.exists(
                os.path.join(base, entry, "partition")
            ):
                found.append(entry)
    except OSError:
        pass
    return found[:64]


def scan():
    """The physical drives you can unplug, one entry each.

    Listing filesystems instead of drives was the first design and it was
    wrong: a single installer stick came out as three cryptic rows, two of them
    showing a UUID because the partition has no label. People think in drives,
    so the drive is the unit - and pairing to the drive rather than to one of
    its filesystems is also what makes a pairing survive a reformat.
    """
    uuids = read_links(BY_UUID)
    labels = read_links(BY_LABEL)

    try:
        candidates = sorted(os.listdir(SYS_BLOCK))
    except OSError:
        return []

    drives = []
    for disk in candidates:
        # Virtual devices never qualify, and skipping them by name keeps the
        # sysfs walk off a few hundred entries that cannot match.
        if disk.startswith(("loop", "ram", "zram", "dm-", "md", "sr")):
            continue
        # A partition is not a drive; only whole devices are considered.
        if os.path.exists(os.path.join(SYS_BLOCK, disk, "partition")):
            continue
        if not is_unpluggable(disk):
            continue

        members = partitions_of(disk) or [disk]
        member_labels = []
        first_uuid = ""
        for member in members:
            if not first_uuid and member in uuids:
                first_uuid = uuids[member]
            raw = labels.get(member, "")
            if raw:
                member_labels.append(unescape_udev(raw))

        identity = drive_identity(disk, first_uuid)
        if not identity:
            continue

        name, size = describe(disk)
        drives.append(
            {
                "id": identity,
                "device": disk,
                "name": name[:MAX_NAME],
                # The volume name is what people recognise the stick by, so it
                # leads when there is one and the hardware name backs it up.
                "label": (member_labels[0] if member_labels else "")[:MAX_NAME],
                "size": size,
                "partitions": len(members),
            }
        )
        if len(drives) >= MAX_DRIVES:
            break

    drives.sort(key=lambda d: d["id"])
    return drives


def emit(drives):
    # The ceiling belongs at the writer: the reader cannot bound a line it has
    # already been handed.
    line = json.dumps({"drives": drives}, separators=(",", ":"))
    if len(line) > 128 * 1024:
        line = json.dumps({"drives": [], "truncated": True}, separators=(",", ":"))
    sys.stdout.write(line + "\n")
    sys.stdout.flush()


def main():
    try:
        notifier = Inotify()
    except OSError:
        # Without inotify the backstop alone still works, just less promptly.
        notifier = None

    if notifier:
        notifier.watch(BY_UUID)

    previous = None
    while True:
        drives = scan()
        if drives != previous:
            emit(drives)
            previous = drives

        if notifier:
            # If the directory went away and came back, the watch died with
            # it; re-arming here costs nothing when it is already held.
            notifier.watch(BY_UUID)
            notifier.wait(BACKSTOP_SECONDS)
        else:
            import time

            time.sleep(BACKSTOP_SECONDS)


if __name__ == "__main__":
    try:
        main()
    except KeyboardInterrupt:
        pass
    except BrokenPipeError:
        pass
