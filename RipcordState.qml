pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
// For the Color singleton: the palette fallbacks and the theme-change signal
// both come from it.
import qs.Commons

// The single owner of the drive watcher, the pairing, and the trap itself.
//
// A bar widget is instantiated once per monitor, so a watcher started from the
// widget would run once per screen and a removal would fire the trap as many
// times as there are bars. This singleton exists so there is exactly one
// watcher and exactly one trigger no matter how many displays are attached.
QtObject {
  id: root

  readonly property string homeDir: Quickshell.env("HOME") || ""
  readonly property string stateHome: {
    var xdg = Quickshell.env("XDG_STATE_HOME")
    return (xdg && xdg.length > 0) ? xdg : (root.homeDir + "/.local/state")
  }
  readonly property string pluginDir: root.homeDir + "/.config/omarchy/plugins/io.github.weedwhitesandwine.ripcord"
  readonly property string stateDir: root.stateHome + "/omarchy/ripcord"
  readonly property string settingsPath: root.stateDir + "/settings.json"

  // ---------------------------------------------------------------- limits
  readonly property int lineCeiling: 128 * 1024
  readonly property int settingsCeiling: 64 * 1024
  readonly property int maxDrives: 64
  readonly property int maxFieldLength: 256

  // ------------------------------------------------------------ what is on
  //
  // Only drives that can physically be pulled out; the watcher does that
  // filtering, because pairing the disk the system runs from would arm a trap
  // that can only fire by accident.
  property var drives: []
  property bool watcherUp: false

  // ---------------------------------------------------------- the pairing
  //
  // The key is the physical drive, taken from its USB serial where there is
  // one. Not its name - a drive labelled "Ripcord" is a label anybody can
  // write onto their own stick - and not one of its filesystems either, since
  // a partition UUID changes the moment the drive is reformatted and would
  // break the pairing silently.
  property string pairedId: ""
  property string pairedLabel: ""
  readonly property bool paired: root.pairedId.length > 0

  readonly property int pairedMatches: {
    if (!root.paired) return 0
    var found = 0
    for (var i = 0; i < root.drives.length; i++) {
      if (root.drives[i].id === root.pairedId) found = found + 1
    }
    return found
  }

  readonly property bool pairedPresent: root.pairedMatches > 0

  // More than one attached drive answering to the paired identity means the
  // trap can no longer tell them apart - pull the real key and the impostor
  // holds the match open, so nothing fires. Cheap flash drives are routinely
  // shipped with duplicate or absent serials, so this is a thing that happens
  // by accident far more often than by design. It cannot be resolved from
  // here, so it is surfaced rather than guessed at.
  readonly property bool pairedAmbiguous: root.pairedMatches > 1

  // ------------------------------------------------------------- settings
  property bool lockOnPull: true
  // Off by default, on purpose. Locking your own session is unremarkable;
  // putting the machine to sleep is the part that deserves a deliberate
  // decision rather than arriving switched on.
  property bool suspendOnPull: false
  // On by default, also on purpose: nobody should have to get locked out of
  // their own laptop to discover whether they configured this correctly.
  property bool rehearsal: true
  property bool settingsLoaded: false

  // ---------------------------------------------------------------- arming
  //
  // Deliberately not persisted and deliberately not restored. The shell
  // reloads a plugin on every file write, so an armed state that survived a
  // reload would suspend the machine during development; and after a reboot,
  // silently re-arming would fire the first time an old paired drive was
  // unplugged by someone who had forgotten all about it.
  property bool armed: false

  // After the trap fires it does not re-arm on its own: the drive has to come
  // back first. Without this, unlocking after a trigger walks straight into
  // the next one.
  property bool awaitingReinsert: false

  property string lastEvent: ""

  readonly property string statusText: {
    if (!root.paired) return "No drive paired"
    if (root.pairedAmbiguous) return "Two drives share this identity"
    if (!root.armed) return "Disarmed"
    if (root.awaitingReinsert) return "Tripped — reinsert to re-arm"
    if (!root.pairedPresent) return "Armed, drive missing"
    return root.rehearsal ? "Armed (rehearsal)" : "Armed"
  }

  function canArm() {
    // Refuses while the identity is ambiguous. Arming into that would set a
    // trap that cannot fire, which is worse than not arming at all: the panel
    // would say ARMED and mean nothing.
    return root.paired && root.pairedPresent && !root.armed
           && !root.pairedAmbiguous
  }

  function arm() {
    if (!root.canArm()) return
    root.awaitingReinsert = false
    root.armed = true
    root.lastEvent = "Armed at " + Qt.formatTime(new Date(), "HH:mm")
  }

  function disarm() {
    root.armed = false
    root.awaitingReinsert = false
    root.lastEvent = "Disarmed at " + Qt.formatTime(new Date(), "HH:mm")
  }

  function pair(id, label) {
    if (typeof id !== "string" || id.length === 0) return
    if (id.length > root.maxFieldLength) return
    // Changing the key while the trap is set would leave it watching for a
    // drive the user never armed against.
    root.disarm()
    root.pairedId = id
    root.pairedLabel = (typeof label === "string") ? label.slice(0, root.maxFieldLength) : ""
    root.scheduleSettingsSave()
  }

  function unpair() {
    root.disarm()
    root.pairedId = ""
    root.pairedLabel = ""
    root.scheduleSettingsSave()
  }

  // ------------------------------------------------------------ the trap

  onPairedPresentChanged: root.evaluate()

  function evaluate() {
    if (root.pairedPresent) {
      // The drive is back, so a tripped trap can be set again.
      if (root.awaitingReinsert) {
        root.awaitingReinsert = false
        root.lastEvent = "Drive reinserted — ready to arm"
      }
      return
    }
    if (!root.armed) return
    if (root.awaitingReinsert) return
    root.trip()
  }

  function trip() {
    root.awaitingReinsert = true
    var stamp = Qt.formatTime(new Date(), "HH:mm:ss")

    if (root.rehearsal) {
      root.lastEvent = "Rehearsal: would have responded at " + stamp
      root.notify("Ripcord (rehearsal)",
                  "Drive removed. Nothing was done — rehearsal mode is on.")
      return
    }

    root.lastEvent = "Triggered at " + stamp
    if (root.lockOnPull) root.locker.running = true
    if (root.suspendOnPull) root.suspender.running = true
    if (!root.lockOnPull && !root.suspendOnPull) {
      root.notify("Ripcord", "Drive removed, but no response is enabled.")
    }
  }

  // Both halves of a notification are a text sink that interprets markup, and
  // the summary is not stripped by the shell the way the body is - so angle
  // brackets come out of anything that reached us from outside. The -- keeps
  // a value beginning with a dash from being read as an option.
  function notify(summary, body) {
    var clean = function (text) {
      return String(text).replace(/[<>]/g, "").slice(0, 512)
    }
    root.notifier.command = ["notify-send", "-a", "Ripcord", "--",
                             clean(summary), clean(body)]
    root.notifier.running = true
  }

  property Process notifier: Process { running: false }

  // omarchy-system-lock is the one that works on Omarchy Quattro: it drives
  // the shell's own lock service and also locks 1Password, which is exactly
  // what someone walking off with the machine should not find open.
  //
  // loginctl is second and not first for a measured reason: on Quattro it
  // exits 0 while doing nothing at all, so it is neither a working lock nor a
  // detectable failure. Ordering by what actually locks, rather than by what
  // is most standard, is the difference between locking and only appearing to.
  property Process locker: Process {
    command: ["sh", "-c", [
      'if command -v omarchy-system-lock >/dev/null 2>&1; then',
      '  exec omarchy-system-lock',
      'elif command -v hyprlock >/dev/null 2>&1; then',
      '  exec hyprlock',
      'elif command -v loginctl >/dev/null 2>&1; then',
      '  exec loginctl lock-session',
      'else',
      '  exit 127',
      'fi'
    ].join("\n")]
    running: false
    onExited: function (code, status) {
      if (code !== 0) {
        root.lastEvent = "Lock failed — the session did not lock"
        root.notify("Ripcord", "The drive was removed but the session could not be locked.")
        return
      }
      // Exit 0 is not proof: the check below is what decides.
      root.lockVerifyTimer.restart()
    }
  }

  // A lock command that succeeds and leaves the session unlocked is the worst
  // outcome this plugin has, because everything looks like it worked. Asking
  // the compositor afterwards turns that into something the user is told about.
  property Timer lockVerifyTimer: Timer {
    repeat: false
    interval: 1500
    onTriggered: {
      root.lockVerifier.running = false
      root.lockVerifier.running = true
    }
  }

  property Process lockVerifier: Process {
    command: ["sh", "-c",
              "command -v omarchy-hyprland-session-locked >/dev/null 2>&1 "
              + "&& omarchy-hyprland-session-locked; exit $?"]
    running: false
    onExited: function (code, status) {
      // 0 locked, 1 unlocked, 2 undetermined, 127 no such command. Only a
      // definite "unlocked" is worth shouting about; the rest cannot tell us
      // anything and a false alarm would train the user to ignore it.
      if (code === 1) {
        root.lastEvent = "Lock did not take — session is still unlocked"
        root.notify("Ripcord",
                    "The drive was removed and the lock was requested, but the session is still unlocked.")
      }
    }
  }

  property Process suspender: Process {
    command: ["systemctl", "suspend"]
    running: false
  }

  // -------------------------------------------------------- the watcher

  property int restartDelay: 1000

  property Process watcher: Process {
    // setpriv --pdeathsig means the watcher cannot outlive the shell even if
    // the shell dies without cleaning up: the kernel signals it directly.
    command: ["setpriv", "--pdeathsig", "TERM",
              "python3", root.pluginDir + "/ripcord-watch.py"]
    running: false

    stdout: SplitParser {
      splitMarker: "\n"
      onRead: function (line) { root.ingest(line) }
    }
    // Collected and discarded deliberately: an unread stderr pipe fills and
    // then blocks the writer, which would stop the watcher dead.
    stderr: SplitParser {
      splitMarker: "\n"
      onRead: function (line) {}
    }

    onStarted: {
      root.restartDelay = 1000
      root.watcherUp = true
    }
    onExited: function (code, status) { root.watcherStopped() }
  }

  property Timer restartTimer: Timer {
    repeat: false
    interval: root.restartDelay
    onTriggered: root.startWatcher()
  }

  function startWatcher() {
    if (root.watcher.running) return
    root.watcher.running = true
  }

  function watcherStopped() {
    root.watcherUp = false
    // A watcher that cannot start - no python3, a deleted script - must not be
    // restarted in a tight loop for the life of the shell.
    root.restartDelay = Math.min(60000, Math.max(1000, root.restartDelay * 2))
    root.restartTimer.interval = root.restartDelay
    root.restartTimer.restart()

    // The trap cannot see anything while the watcher is down, and silently
    // staying "armed" would be a lie. Say so rather than pretend.
    if (root.armed) {
      root.lastEvent = "Watcher stopped — protection is not active"
      root.notify("Ripcord", "The drive watcher stopped. Ripcord is not watching.")
    }
  }

  function ingest(line) {
    if (typeof line !== "string" || line.length === 0) return
    // The ceiling is here rather than inside the parse: a line this long is
    // not a drive list, and parsing it would already have cost the memory.
    if (line.length > root.lineCeiling) return

    var parsed = null
    try {
      parsed = JSON.parse(line)
    } catch (error) {
      return
    }
    if (!parsed || typeof parsed !== "object" || Array.isArray(parsed)) return
    // The watcher says when it could not describe the drives. That is not the
    // same as there being none, and acting on it would fire the trap.
    if (parsed.unreportable === true) return
    if (!Array.isArray(parsed.drives)) return

    var cleaned = []
    var list = parsed.drives.slice(0, root.maxDrives)
    for (var i = 0; i < list.length; i++) {
      var entry = list[i]
      if (!entry || typeof entry !== "object") continue
      if (typeof entry.id !== "string" || entry.id.length === 0) continue
      if (entry.id.length > root.maxFieldLength) continue
      cleaned.push({
        id: entry.id,
        name: (typeof entry.name === "string")
          ? entry.name.slice(0, root.maxFieldLength) : "",
        label: (typeof entry.label === "string")
          ? entry.label.slice(0, root.maxFieldLength) : "",
        device: (typeof entry.device === "string")
          ? entry.device.slice(0, root.maxFieldLength) : "",
        size: (typeof entry.size === "number" && isFinite(entry.size) && entry.size >= 0)
          ? entry.size : 0,
        partitions: (typeof entry.partitions === "number" && isFinite(entry.partitions))
          ? entry.partitions : 0
      })
    }

    root.drives = cleaned
    root.restartDelay = 1000
    // pairedPresent is derived, so its change handler runs the trap; this
    // covers the case where the set changed without that binding flipping.
    root.evaluate()
  }

  // ------------------------------------------------------------ appearance
  //
  // Ripcord paints its own surface rather than sitting on the theme's popup
  // background. That is a deliberate break from the rest of the shell: the
  // panel's whole job is to be unmistakable at a glance, and it cannot promise
  // that when the ground under it changes with every theme.
  //
  // Two modes, chosen by the user with the sun/moon in the panel header rather
  // than inferred, so it never disagrees with what they wanted.
  property string appearance: "dark"      // dark | light
  readonly property bool lightMode: root.appearance === "light"

  function toggleAppearance() {
    root.appearance = root.lightMode ? "dark" : "light"
  }

  readonly property color surfaceColor: root.lightMode ? "#f7f5f1" : "#0f1b2e"
  readonly property color textColor: root.lightMode ? "#10151c" : "#eef2f7"
  readonly property color mutedTextColor: root.lightMode ? "#41505f" : "#b9c4d4"

  // Every one of these clears 4.5:1 against its own background - checked
  // against the two surfaces above rather than assumed, which is the whole
  // advantage of owning the background instead of borrowing it.
  readonly property color liveColor: root.lightMode ? "#b3121f" : "#ff6b78"
  readonly property color goColor: root.lightMode ? "#116b33" : "#5ddb7f"
  readonly property color holdColor: root.lightMode ? "#8a5000" : "#ffb454"

  // -------------------------------------------------------------- settings
  //
  // Reading a file this process does not hold open means it can be anything by
  // the time it is opened - a link elsewhere, a pipe, or something far too
  // large. The open refuses on its own terms and the ceiling is applied to the
  // read, so a bad file yields nothing rather than something.
  readonly property string safeRead: [
    'import os, stat, sys',
    'path = sys.argv[1]; ceiling = int(sys.argv[2])',
    'try:',
    '    fd = os.open(path, os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK)',
    'except FileNotFoundError:',
    '    raise SystemExit(2)',
    'except OSError:',
    '    raise SystemExit(1)',
    'try:',
    '    if not stat.S_ISREG(os.fstat(fd).st_mode):',
    '        raise SystemExit(1)',
    '    with os.fdopen(fd, "rb") as handle:',
    '        fd = None',
    '        raw = handle.read(ceiling + 1)',
    'except OSError:',
    '    raise SystemExit(1)',
    'finally:',
    '    if fd is not None:',
    '        os.close(fd)',
    'if len(raw) > ceiling:',
    '    raise SystemExit(1)',
    'sys.stdout.buffer.write(raw)'
  ].join("\n")

  property Process ensureStateDir: Process {
    command: ["mkdir", "-p", "-m", "700", root.stateDir]
  }

  property Process settingsReader: Process {
    command: ["python3", "-c", root.safeRead,
              root.settingsPath, String(root.settingsCeiling)]
    stdout: StdioCollector {
      id: settingsOut
      waitForEnd: true
      onStreamFinished: if (settingsOut.text !== "") root.applySettings(settingsOut.text)
    }
    onExited: function (code, status) {
      // 2 is "no file yet", so the defaults are the truth and saving is safe.
      // 1 is a refusal - too large, a link, not a plain file - and the gate
      // stays shut, because writing over a file we could not read destroys it.
      if (root.settingsLoaded) return
      if (code === 2) root.settingsLoaded = true
    }
  }

  function applySettings(text) {
    var parsed = null
    try {
      parsed = JSON.parse(text)
    } catch (error) {
      parsed = null
    }
    if (parsed && typeof parsed === "object" && !Array.isArray(parsed)) {
      // Deliberately does not read the old pairedUuid: it named a filesystem,
      // not a drive, so carrying it over would leave a pairing that can never
      // match. An upgrade re-pairs once, and says so rather than pretending.
      if (typeof parsed.pairedId === "string"
          && parsed.pairedId.length <= root.maxFieldLength)
        root.pairedId = parsed.pairedId
      if (typeof parsed.pairedLabel === "string")
        root.pairedLabel = parsed.pairedLabel.slice(0, root.maxFieldLength)
      if (typeof parsed.lockOnPull === "boolean") root.lockOnPull = parsed.lockOnPull
      if (typeof parsed.suspendOnPull === "boolean") root.suspendOnPull = parsed.suspendOnPull
      if (typeof parsed.rehearsal === "boolean") root.rehearsal = parsed.rehearsal
      if (parsed.appearance === "dark" || parsed.appearance === "light")
        root.appearance = parsed.appearance
    }
    root.settingsLoaded = true
  }

  property bool savingNow: false

  property Timer settingsSaveTimer: Timer {
    repeat: false
    interval: 250
    onTriggered: root.flushSettings()
  }

  function scheduleSettingsSave() {
    // Gated on the load having happened, or the defaults get written over the
    // user's real choices before their file has been read.
    if (root.settingsLoaded) root.settingsSaveTimer.restart()
  }

  function flushSettings() {
    root.savingNow = true
    // `armed` is absent on purpose. See the note on it above.
    root.settingsFile.setText(JSON.stringify({
      pairedId: root.pairedId,
      pairedLabel: root.pairedLabel,
      lockOnPull: root.lockOnPull,
      suspendOnPull: root.suspendOnPull,
      rehearsal: root.rehearsal,
      appearance: root.appearance
    }, null, 2) + "\n")
  }

  // The writer only. Reads go through safeRead above, because FileView cannot
  // stop short of the end of a file: by the time its text exists, whatever was
  // on disk is already in the shell.
  property FileView settingsFile: FileView {
    path: root.settingsPath
    atomicWrites: true
    blockAllReads: true
    preload: false
    printErrors: false
    watchChanges: true
    onFileChanged: {
      if (root.savingNow) { root.savingNow = false; return }
      root.settingsReader.running = false
      root.settingsReader.running = true
    }
  }

  onLockOnPullChanged: root.scheduleSettingsSave()
  onSuspendOnPullChanged: root.scheduleSettingsSave()
  onRehearsalChanged: root.scheduleSettingsSave()
  onAppearanceChanged: root.scheduleSettingsSave()

  Component.onCompleted: {
    root.ensureStateDir.running = true
    root.settingsReader.running = true
    root.startWatcher()
  }
}
