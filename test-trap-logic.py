#!/usr/bin/env python3
"""Does the trap fire on the drive it was armed against?

This models the decision logic in RipcordState.qml rather than executing it -
the QML needs the shell's own types and cannot run standalone. So it is a
regression test for the reasoning, not proof that the QML matches it; the two
have to be kept in step by hand, and the expressions below are written to
mirror trapSeesKey/evaluate line for line.

It exists because a review found that counting matching drives is not the same
as watching the drive you armed on, and every test up to that point had used a
single stick, where the two are indistinguishable.
"""


class Trap:
    """Mirrors trapSeesKey / evaluate / arm / disarm in RipcordState.qml."""

    def __init__(self, paired_id):
        self.paired_id = paired_id
        self.drives = []
        self.armed = False
        self.armed_device = ""
        self.awaiting_reinsert = False
        self.tripped = 0

    # --- mirrors of the QML bindings -----------------------------------
    @property
    def paired_matches(self):
        return sum(1 for d in self.drives if d["id"] == self.paired_id)

    @property
    def paired_present(self):
        return self.paired_matches > 0

    @property
    def paired_ambiguous(self):
        return self.paired_matches > 1

    @property
    def trap_sees_key(self):
        if not self.armed or not self.armed_device:
            return self.paired_present
        return any(d["id"] == self.paired_id and d["device"] == self.armed_device
                   for d in self.drives)

    def can_arm(self):
        return (self.paired_id and self.paired_present
                and not self.armed and not self.paired_ambiguous)

    # --- mirrors of the QML functions ----------------------------------
    def device_for_paired_id(self):
        for d in self.drives:
            if d["id"] == self.paired_id:
                return d["device"]
        return ""

    def arm(self):
        if not self.can_arm():
            return False
        self.awaiting_reinsert = False
        self.armed_device = self.device_for_paired_id()
        self.armed = True
        return True

    def set_drives(self, drives):
        self.drives = drives
        self.evaluate()

    def evaluate(self):
        if self.trap_sees_key:
            self.awaiting_reinsert = False
            return
        if not self.armed:
            return
        if self.awaiting_reinsert:
            return
        self.tripped += 1
        self.awaiting_reinsert = True


KEY = "usb:REALKEY"
real = {"id": KEY, "device": "sda"}
impostor = {"id": KEY, "device": "sdb"}       # same serial, different device
other = {"id": "usb:SOMETHINGELSE", "device": "sdc"}

CASES = []


def case(name):
    def wrap(fn):
        CASES.append((name, fn))
        return fn
    return wrap


@case("plain pull fires the trap")
def _():
    t = Trap(KEY); t.set_drives([real]); assert t.arm()
    t.set_drives([])
    return t.tripped == 1


@case("pulling an unrelated drive does not fire")
def _():
    t = Trap(KEY); t.set_drives([real, other]); assert t.arm()
    t.set_drives([real])
    return t.tripped == 0


# The finding. With an impostor attached, the match count never reaches zero,
# so anything keyed on "is something matching still present" stays quiet.
@case("impostor attached, real key pulled -> STILL fires")
def _():
    t = Trap(KEY); t.set_drives([real]); assert t.arm()
    t.set_drives([real, impostor])          # impostor appears after arming
    before = t.tripped
    t.set_drives([impostor])                # the real key is yanked
    return before == 0 and t.tripped == 1


@case("impostor alone does not keep the trap satisfied")
def _():
    t = Trap(KEY); t.set_drives([real]); assert t.arm()
    t.set_drives([real, impostor])
    t.set_drives([impostor])
    return not t.trap_sees_key


@case("arming refused while two drives share the identity")
def _():
    t = Trap(KEY); t.set_drives([real, impostor])
    return t.arm() is False and t.paired_ambiguous


@case("no re-fire until the key comes back")
def _():
    t = Trap(KEY); t.set_drives([real]); assert t.arm()
    t.set_drives([])
    t.set_drives([])                        # still absent, must not re-fire
    return t.tripped == 1


@case("reinsert then pull fires again")
def _():
    t = Trap(KEY); t.set_drives([real]); assert t.arm()
    t.set_drives([])
    t.set_drives([real])                    # back: clears awaiting_reinsert
    t.set_drives([])
    return t.tripped == 2


@case("disarmed drive removal never fires")
def _():
    t = Trap(KEY); t.set_drives([real])
    t.set_drives([])
    return t.tripped == 0


def main():
    failures = 0
    for name, fn in CASES:
        try:
            ok = fn()
        except Exception as exc:                      # noqa: BLE001
            ok, name = False, "%s (raised %s)" % (name, exc)
        if not ok:
            failures += 1
        print("  %s  %s" % ("PASS" if ok else "FAIL", name))
    print()
    if failures:
        print("%d of %d cases FAILED" % (failures, len(CASES)))
        return 1
    print("all %d cases passed" % len(CASES))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
