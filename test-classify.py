#!/usr/bin/env python3
"""Does is_unpluggable() tell a drive you can yank from one that is bolted in?

Built against synthetic sysfs trees rather than real hardware, because the
cases that matter cannot be produced on demand: a loop device cannot be made
removable, and a USB SSD is not something a test can conjure. Every case runs
in both directions - the ones that must pass and the ones that must fail.
"""

import os
import shutil
import sys
import tempfile

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import importlib.machinery
import importlib.util

loader = importlib.machinery.SourceFileLoader(
    "ripcord_watch", os.path.join(os.path.dirname(os.path.abspath(__file__)),
                                  "ripcord-watch.py")
)
spec = importlib.util.spec_from_loader("ripcord_watch", loader)
watch = importlib.util.module_from_spec(spec)
loader.exec_module(watch)


def build(root, device, device_path, removable, parent=None):
    """Create a fake /sys/class/block/<device> symlink into a device tree."""
    full = os.path.join(root, "devices", device_path.strip("/"))
    os.makedirs(full, exist_ok=True)

    disk = parent or device
    disk_dir = full if parent is None else os.path.dirname(full)
    os.makedirs(disk_dir, exist_ok=True)
    with open(os.path.join(disk_dir, "removable"), "w") as handle:
        handle.write("%d\n" % removable)

    block = os.path.join(root, "class", "block")
    os.makedirs(block, exist_ok=True)
    link = os.path.join(block, device)
    if os.path.lexists(link):
        os.remove(link)
    os.symlink(full, link)
    return block


CASES = [
    # (name, sysfs device path, removable flag, has partition, expected)
    ("USB flash stick (partition)",
     "pci0000:00/0000:00:14.0/usb2/2-1/2-1:1.0/host0/target0:0:0/0:0:0:0/block/sdb/sdb1",
     1, True, True),

    ("USB flash stick (whole device)",
     "pci0000:00/0000:00:14.0/usb2/2-1/2-1:1.0/host0/target0:0:0/0:0:0:0/block/sdd",
     1, False, True),

    # The case the first version of this got wrong.
    ("USB SSD in an enclosure, removable=0",
     "pci0000:00/0000:00:14.0/usb2/2-3/2-3:1.0/host1/target1:0:0/1:0:0:0/block/sdc/sdc1",
     0, True, True),

    ("Internal NVMe",
     "pci0000:00/0000:00:1d.0/0000:03:00.0/nvme/nvme0/nvme0n1/nvme0n1p1",
     0, True, False),

    ("Internal SATA disk",
     "pci0000:00/0000:00:17.0/ata1/host0/target0:0:0/0:0:0:0/block/sda/sda1",
     0, True, False),

    ("Loop device",
     "virtual/block/loop0",
     0, False, False),

    # Traps: the letters u-s-b appearing somewhere that is not the USB bus.
    ("Internal disk on a vendor path containing 'usbridge'",
     "pci0000:00/0000:00:17.0/usbridge0/host0/target0:0:0/0:0:0:0/block/sde/sde1",
     0, True, False),

    ("Internal disk under a directory literally named 'usbstuff'",
     "pci0000:00/usbstuff/host0/target0:0:0/0:0:0:0/block/sdf/sdf1",
     0, True, False),
]


def main():
    root = tempfile.mkdtemp(prefix="ripcord-sysfs-")
    failures = 0
    try:
        for name, path, removable, has_partition, expected in CASES:
            device = os.path.basename(path)
            parent = os.path.basename(os.path.dirname(path)) if has_partition else None
            block = build(root, device, path, removable, parent)

            actual = watch.is_unpluggable(device, sys_block=block)
            ok = actual == expected
            if not ok:
                failures += 1
            print("  %s  %-52s expected=%-5s got=%-5s"
                  % ("PASS" if ok else "FAIL", name, expected, actual))
    finally:
        shutil.rmtree(root, ignore_errors=True)

    print()
    if failures:
        print("%d of %d cases FAILED" % (failures, len(CASES)))
        return 1
    print("all %d cases passed" % len(CASES))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
