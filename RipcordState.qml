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
  // The key is the filesystem's unique identifier, not its name. A drive
  // labelled "Ripcord" is a label anybody can write onto their own stick; the
  // identifier is the drive.
  property string pairedUuid: ""
  property string pairedLabel: ""
  readonly property bool paired: root.pairedUuid.length > 0

  readonly property bool pairedPresent: {
    if (!root.paired) return false
    for (var i = 0; i < root.drives.length; i++) {
      if (root.drives[i].uuid === root.pairedUuid) return true
    }
    return false
  }

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
    if (!root.armed) return "Disarmed"
    if (root.awaitingReinsert) return "Tripped — reinsert to re-arm"
    if (!root.pairedPresent) return "Armed, drive missing"
    return root.rehearsal ? "Armed (rehearsal)" : "Armed"
  }

  function canArm() {
    return root.paired && root.pairedPresent && !root.armed
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

  function pair(uuid, label) {
    if (typeof uuid !== "string" || uuid.length === 0) return
    if (uuid.length > root.maxFieldLength) return
    // Changing the key while the trap is set would leave it watching for a
    // drive the user never armed against.
    root.disarm()
    root.pairedUuid = uuid
    root.pairedLabel = (typeof label === "string") ? label.slice(0, root.maxFieldLength) : ""
    root.scheduleSettingsSave()
  }

  function unpair() {
    root.disarm()
    root.pairedUuid = ""
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
    if (!Array.isArray(parsed.drives)) return

    var cleaned = []
    var list = parsed.drives.slice(0, root.maxDrives)
    for (var i = 0; i < list.length; i++) {
      var entry = list[i]
      if (!entry || typeof entry !== "object") continue
      if (typeof entry.uuid !== "string" || entry.uuid.length === 0) continue
      if (entry.uuid.length > root.maxFieldLength) continue
      cleaned.push({
        uuid: entry.uuid,
        label: (typeof entry.label === "string")
          ? entry.label.slice(0, root.maxFieldLength) : "",
        device: (typeof entry.device === "string")
          ? entry.device.slice(0, root.maxFieldLength) : ""
      })
    }

    root.drives = cleaned
    root.restartDelay = 1000
    // pairedPresent is derived, so its change handler runs the trap; this
    // covers the case where the set changed without that binding flipping.
    root.evaluate()
  }

  // --------------------------------------------------------- theme palette
  //
  // The shell keeps only five colours live in memory - foreground, background,
  // accent, urgent and muted - and throws the named hues away. Arm and Disarm
  // want a real green and a real red, so the palette is read from the theme's
  // own file and the plugin tracks whatever theme is active rather than
  // hardcoding two colours that will clash with half of them.
  readonly property string palettePath: root.stateHome + "/omarchy/current/theme/colors.toml"
  readonly property int paletteCeiling: 64 * 1024

  // Fallbacks are the two the shell does keep, so the panel is never colourless
  // even on a theme that ships no named hues.
  property color themeRed: Color.urgent
  property color themeGreen: Color.accent
  property color themeAmber: Color.accent
  property bool paletteLoaded: false

  property Process paletteReader: Process {
    command: ["python3", "-c", root.safeRead,
              root.palettePath, String(root.paletteCeiling)]
    stdout: StdioCollector {
      id: paletteOut
      waitForEnd: true
      onStreamFinished: if (paletteOut.text !== "") root.applyPalette(paletteOut.text)
    }
  }

  function applyPalette(text) {
    if (typeof text !== "string" || text.length > root.paletteCeiling) return

    var found = ({})
    var lines = text.split("\n").slice(0, 400)
    for (var i = 0; i < lines.length; i++) {
      // key = "#rrggbb", which is the whole of the format this needs.
      var match = /^\s*([A-Za-z0-9_]+)\s*=\s*"(#[0-9A-Fa-f]{3,8})"/.exec(lines[i])
      if (match) found[match[1].toLowerCase()] = match[2]
    }

    // Omarchy's own themes name their hues; many third-party themes ship the
    // ANSI numbering instead. Both are read, words first.
    function pick(named, ansi, bright, fallback) {
      if (found[named]) return found[named]
      if (found[ansi]) return found[ansi]
      if (found[bright]) return found[bright]
      return fallback
    }

    root.themeRed = pick("red", "color1", "bright_red", Color.urgent)
    root.themeGreen = pick("green", "color2", "bright_green", Color.accent)
    root.themeAmber = pick("yellow", "color3", "orange", Color.accent)
    root.paletteLoaded = true
  }

  // A file watch on the theme directory does not survive a theme switch: the
  // whole directory is replaced, so the watch dies with the old inode. The
  // shell does keep its own five colours current, so a change in those is the
  // signal to go and read the file again.
  property Connections themeWatch: Connections {
    target: Color
    function onForegroundChanged() { root.reloadPalette() }
    function onBackgroundChanged() { root.reloadPalette() }
    function onAccentChanged() { root.reloadPalette() }
  }

  function reloadPalette() {
    root.paletteReader.running = false
    root.paletteReader.running = true
  }

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
      if (typeof parsed.pairedUuid === "string"
          && parsed.pairedUuid.length <= root.maxFieldLength)
        root.pairedUuid = parsed.pairedUuid
      if (typeof parsed.pairedLabel === "string")
        root.pairedLabel = parsed.pairedLabel.slice(0, root.maxFieldLength)
      if (typeof parsed.lockOnPull === "boolean") root.lockOnPull = parsed.lockOnPull
      if (typeof parsed.suspendOnPull === "boolean") root.suspendOnPull = parsed.suspendOnPull
      if (typeof parsed.rehearsal === "boolean") root.rehearsal = parsed.rehearsal
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
      pairedUuid: root.pairedUuid,
      pairedLabel: root.pairedLabel,
      lockOnPull: root.lockOnPull,
      suspendOnPull: root.suspendOnPull,
      rehearsal: root.rehearsal
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

  Component.onCompleted: {
    root.ensureStateDir.running = true
    root.settingsReader.running = true
    root.startWatcher()
  }
}
