import QtQuick
import QtQuick.Window
import QtQuick.Layouts
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import "../"
import "layouts.js" as Layouts

// Settings (dashboard header button / SUPER+SHIFT+S). Sidebar + four pages:
//   General   UI scale, workspaces, windows, keyboard & mouse, idle, weather  -> settings.json / calendar/.env
//   Keybinds  built-in (Lua) binds read-only, your binds editable             -> settings.json "keybinds"
//   Display   resolution, refresh, scale, rotation, VRR, projection           -> live via hyprctl, kept in "monitors"
//   Startup   login commands; the ones the desktop needs are locked           -> settings.json "startup"
// scripts/settings_watcher.sh turns settings.json into config/*.lua and hypridle.conf.
Item {
    id: root
    focus: true

    property var notifModel
    property var liveNotifs
    property real layoutWidth
    property real layoutHeight

    Scaler { id: scaler; currentWidth: Screen.width; currentHeight: Screen.height }
    // Settings is text-heavy, so it runs 15% larger than the other popups
    function s(v) { return scaler.s(v * 1.15); }

    MatugenColors { id: _theme }
    readonly property color base: _theme.base
    readonly property color text: _theme.text
    readonly property color subtext0: _theme.subtext0
    readonly property color overlay0: _theme.overlay0
    readonly property color red: _theme.red
    readonly property color green: _theme.green
    readonly property string ui: "SF Pro Display"
    readonly property string icons: "Maple Mono Normal NF"
    function tint(a) { return Qt.rgba(root.text.r, root.text.g, root.text.b, a); }
    function sh(cmd) { Quickshell.execDetached(["bash", "-c", cmd]); }
    function close() { Quickshell.execDetached(["bash", Quickshell.env("HOME") + "/.config/hypr/scripts/qs_manager.sh", "close"]); }

    // ---------------- pages ----------------
    property int page: 0
    readonly property var pages: [
        { label: "General",  icon: "󰒓", title: "General" },
        { label: "Keybinds", icon: "󰌌", title: "Keybinds" },
        { label: "Display",  icon: "󰍹", title: "Display" },
        { label: "Startup",  icon: "󰐥", title: "Startup" }
    ]
    onPageChanged: if (page === 2) monPoll.running = true

    Keys.onEscapePressed: (e) => { if (root.recording) return; root.close(); e.accepted = true; }
    Keys.onTabPressed: (e) => { root.page = (root.page + 1) % 4; e.accepted = true; }
    Keys.onBacktabPressed: (e) => { root.page = (root.page + 3) % 4; e.accepted = true; }

    // ---------------- intro (replays on every open: Settings stays loaded) ----------------
    property real introMain: 0
    property real introSide: 0
    property real introContent: 0
    ParallelAnimation {
        id: introAnim
        running: true
        NumberAnimation { target: root; property: "introMain"; from: 0; to: 1; duration: 700; easing.type: Easing.OutExpo }
        SequentialAnimation {
            PauseAnimation { duration: 80 }
            NumberAnimation { target: root; property: "introSide"; from: 0; to: 1; duration: 700; easing.type: Easing.OutBack; easing.overshoot: 1.1 }
        }
        SequentialAnimation {
            PauseAnimation { duration: 180 }
            NumberAnimation { target: root; property: "introContent"; from: 0; to: 1; duration: 750; easing.type: Easing.OutExpo }
        }
    }
    onVisibleChanged: if (visible) {
        introAnim.restart();
        root.loadAll();
        if (root.page === 2) monPoll.running = true;
        root.forceActiveFocus();
    }

    // =====================================================================
    // DATA
    // =====================================================================
    ListModel { id: kbModel }
    ListModel { id: startupModel }
    property bool generalDirty: false
    property bool kbDirty: false
    property bool startupDirty: false

    function loadAll() {
        if (!root.kbDirty) {
            kbModel.clear();
            for (let b of Config.keybindsData)
                kbModel.append({ type: b.type, mods: b.mods, key: b.key, dispatcher: b.dispatcher, command: b.command });
            root.kbRevision++;
        }
        if (!root.startupDirty) {
            startupModel.clear();
            for (let c of Config.startupData) startupModel.append({ command: c.command });
        }
        apiKeyField.text = Config.weatherApiKey;
        cityField.text = Config.weatherCityId;
    }
    Connections {
        target: Config
        function onKeybindsLoaded() { root.loadAll(); }
        function onStartupLoaded() { root.loadAll(); }
        function onWeatherApiKeyChanged() { if (!apiKeyField.editing) apiKeyField.text = Config.weatherApiKey; }
        function onWeatherCityIdChanged() { if (!cityField.editing) cityField.text = Config.weatherCityId; }
    }
    Component.onCompleted: if (Config.dataReady) root.loadAll()

    function saveGeneral() {
        Config.saveAppSettings();
        Config.saveWeatherConfig(true);
        root.generalDirty = false;
    }
    function saveKeybinds() {
        let arr = [];
        for (let i = 0; i < kbModel.count; i++) {
            let b = kbModel.get(i);
            if (b.key.trim() === "") continue;
            arr.push({ type: b.type, mods: b.mods.trim(), key: b.key.trim(), dispatcher: b.dispatcher.trim(), command: b.command });
        }
        Config.saveAllKeybinds(arr);
        root.kbDirty = false;
        root.kbEditing = -1;
    }
    function saveStartup() {
        let arr = [];
        for (let i = 0; i < startupModel.count; i++) {
            let c = startupModel.get(i).command.trim();
            if (c !== "") arr.push({ command: c });
        }
        Config.saveAllStartup(arr);
        root.startupDirty = false;
    }

    // ---------------- keybind helpers ----------------
    property int kbEditing: -1
    property string kbFilter: ""
    property bool recording: false
    property int kbRevision: 0     // bumped on every edit so bindings that read rows refresh

    function modList(mods) {
        let out = [];
        for (let m of (mods || "").split(/[\s+]+/)) {
            if (m === "") continue;
            let u = m.toUpperCase();
            if (u === "$MAINMOD" || u === "SUPER" || u === "SUPER_L" || u === "WIN") u = "SUPER";
            else if (u.indexOf("SHIFT") === 0) u = "SHIFT";
            else if (u.indexOf("CTRL") === 0 || u.indexOf("CONTROL") === 0) u = "CTRL";
            else if (u.indexOf("ALT") === 0) u = "ALT";
            if (out.indexOf(u) < 0) out.push(u);
        }
        return out;
    }
    function modsFrom(list) {
        let order = ["SUPER", "SHIFT", "CTRL", "ALT"], out = [];
        for (let m of order) if (list.indexOf(m) >= 0) out.push(m === "SUPER" ? "$mainMod" : m);
        return out.join(" ");
    }
    function keyLabel(k) {
        let map = { "RETURN": "Enter", "SPACE": "Space", "TAB": "Tab", "PRINT": "Print", "LEFT": "←", "RIGHT": "→", "UP": "↑", "DOWN": "↓",
                    "XF86AUDIORAISEVOLUME": "Vol +", "XF86AUDIOLOWERVOLUME": "Vol −", "XF86AUDIOMUTE": "Mute", "XF86AUDIOMICMUTE": "Mic mute",
                    "XF86AUDIOPLAY": "Play", "XF86AUDIOPAUSE": "Pause", "XF86MONBRIGHTNESSUP": "Bright +", "XF86MONBRIGHTNESSDOWN": "Bright −",
                    "XF86POWEROFF": "Power", "CAPS_LOCK": "Caps Lock" };
        let u = (k || "").toUpperCase();
        return map[u] || (k.length === 1 ? k.toUpperCase() : k);
    }
    function signature(b) { return root.modList(b.mods).sort().join("+") + "|" + (b.key || "").toUpperCase(); }
    readonly property var kbConflicts: {
        root.kbRevision;
        let seen = {}, dup = {};
        for (let i = 0; i < kbModel.count; i++) {
            let b = kbModel.get(i);
            if ((b.key || "") === "") continue;
            let sig = root.signature(b);
            if (seen[sig]) dup[sig] = true;
            seen[sig] = true;
        }
        return dup;
    }

    readonly property var popupNames: ({ calendar: "Calendar", battery: "Battery", wifi: "Wi-Fi", bluetooth: "Bluetooth",
        volume: "Volume", clipboard: "Clipboard", settings: "Settings", focustime: "Focus time", dash: "Dashboard",
        autoclicker: "Autoclicker", vicinae: "App launcher", notifications: "Notifications", power: "Power menu", tools: "Tools", claude: "Claude" })
    function describe(b) {
        let c = (b.command || "").trim(), d = b.dispatcher;
        if (d === "exec") {
            let m = c.match(/qs_manager\.sh (?:toggle|open) (\w+)/);
            if (m) return "Open " + (root.popupNames[m[1]] || m[1]);
            m = c.match(/qs_manager\.sh (\d+)( move)?/);
            if (m) return (m[2] ? "Move window to workspace " : "Go to workspace ") + m[1];
            if (/screenshot\.sh/.test(c)) return "Screenshot" + (/--full/.test(c) ? " (full screen)" : " (area)") + (/--edit/.test(c) ? ", then edit" : "");
            if (/lock\.sh/.test(c)) return "Lock screen";
            if (/playerctl play-pause/.test(c)) return "Play / pause";
            if (/output-volume raise/.test(c)) return "Volume up";
            if (/output-volume lower/.test(c)) return "Volume down";
            if (/output-volume mute/.test(c)) return "Mute";
            if (/input-volume mute/.test(c)) return "Mute microphone";
            if (/brightness raise/.test(c)) return "Brightness up";
            if (/brightness lower/.test(c)) return "Brightness down";
            if (/caps-lock/.test(c)) return "Caps Lock indicator";
            m = c.match(/rotate_screen\.sh (\w+)/);
            if (m) return "Rotate screen " + m[1];
            if (/focus_next_monitor/.test(c)) return "Focus next monitor";
            if (/reload\.sh/.test(c)) return "Reload shell";
            if (/killactive/.test(c)) return "Close window";
            if (/togglefloating/.test(c)) return "Toggle floating";
            if (/autoclicker toggle/.test(c)) return "Start / stop autoclicker";
            let first = c.split(" ")[0].split("/").pop();
            return first ? "Run " + first : "Run command";
        }
        let dir = { l: "left", r: "right", u: "up", d: "down" };
        if (d === "movefocus") return "Focus " + (dir[c] || c);
        if (d === "movewindow") return "Move window " + (dir[c] || c);
        if (d === "resizeactive") return "Resize window";
        if (d === "fullscreen") return "Fullscreen";
        if (d === "killactive") return "Close window";
        if (d === "togglefloating") return "Toggle floating";
        if (d === "workspace") return "Go to workspace " + c;
        if (d === "movetoworkspace") return "Move window to workspace " + c;
        return d + (c ? " " + c : "");
    }
    function kbMatches(b) {
        let q = root.kbFilter.trim().toLowerCase();
        if (q === "") return true;
        let hay = (root.modList(b.mods).join(" ") + " " + root.keyLabel(b.key) + " " + root.describe(b) + " " + b.command).toLowerCase();
        return hay.indexOf(q) >= 0;
    }
    function setKb(i, prop, val) { kbModel.setProperty(i, prop, val); root.kbDirty = true; root.kbRevision++; }

    // ---------------- startup helpers ----------------
    readonly property var coreStartup: ["hyprpolkitagent", "hypridle", "quickshell -p", "focustime/launch_daemon.sh",
        "scripts/init.sh", "settings_watcher.sh", "playerctld", "swayosd-server", "cliphist store",
        "volume_listener.sh", "start vicinae"]
    function isCore(cmd) { return !!cmd && root.coreStartup.some(c => cmd.indexOf(c) >= 0); }

    // ---------------- display ----------------
    property var monitors: []          // hyprctl monitors all -j
    property int monSel: 0
    property var monPending: null      // { mode, scale, transform, vrr } for the selected screen
    property var monRevert: null       // previous state while asking "keep?"
    property int monCountdown: 0
    readonly property var mon: monitors.length > monSel ? monitors[monSel] : null
    readonly property var internal: monitors.find(m => /^(eDP|LVDS|DSI)/.test(m.name)) || null
    readonly property var externals: monitors.filter(m => !/^(eDP|LVDS|DSI)/.test(m.name))

    Process {
        id: monPoll
        command: ["hyprctl", "monitors", "all", "-j"]
        stdout: StdioCollector {
            onStreamFinished: {
                let d; try { d = JSON.parse(this.text); } catch (e) { return; }
                root.monitors = d;
                if (root.monSel >= d.length) root.monSel = 0;
                if (!root.monRevert) root.resetPending();
            }
        }
    }
    function modeOf(m) { return m.width + "x" + m.height + "@" + m.refreshRate.toFixed(2); }
    function resetPending() {
        if (!root.mon) { root.monPending = null; return; }
        root.monPending = { mode: root.modeOf(root.mon), scale: root.mon.scale, transform: root.mon.transform, vrr: root.mon.vrr ? 1 : 0 };
    }
    onMonSelChanged: resetPending()
    function pend(k, v) { let p = Object.assign({}, root.monPending); p[k] = v; root.monPending = p; }
    readonly property bool monChanged: !!mon && !!monPending &&
        (monPending.mode !== modeOf(mon) || Math.abs(monPending.scale - mon.scale) > 0.001 ||
         monPending.transform !== mon.transform || monPending.vrr !== (mon.vrr ? 1 : 0))
    // available modes as { res: "1920x1200", rates: ["60.00", ...] }
    readonly property var monModes: {
        if (!mon) return [];
        let byRes = {}, order = [];
        for (let m of (mon.availableModes || [])) {
            let mm = m.match(/^(\d+x\d+)@([\d.]+)Hz$/);
            if (!mm) continue;
            if (!byRes[mm[1]]) { byRes[mm[1]] = []; order.push(mm[1]); }
            if (byRes[mm[1]].indexOf(mm[2]) < 0) byRes[mm[1]].push(mm[2]);
        }
        return order.map(r => ({ res: r, rates: byRes[r] }));
    }
    function luaMon(name, spec) {
        let parts = ["output = " + JSON.stringify(name)];
        for (let k in spec) parts.push(k + " = " + (typeof spec[k] === "string" ? JSON.stringify(spec[k]) : spec[k]));
        return "hl.monitor({ " + parts.join(", ") + " })";
    }
    function applyDisplay() {
        if (!root.mon || !root.monChanged) return;
        let m = root.mon, p = root.monPending;
        root.monRevert = { name: m.name, mode: root.modeOf(m), position: m.x + "x" + m.y, scale: m.scale, transform: m.transform, vrr: m.vrr ? 1 : 0 };
        root.sh("hyprctl eval '" + root.luaMon(m.name, { mode: p.mode, position: m.x + "x" + m.y, scale: p.scale, transform: p.transform, vrr: p.vrr }) + "'");
        root.monCountdown = 15;
        confirmTimer.restart();
        monRefresh.restart();
    }
    function keepDisplay() {
        confirmTimer.stop();
        root.monRevert = null;
        // remember every screen's current setup so it survives a reload / reboot
        let arr = root.monitors.filter(m => !m.disabled).map(m => ({
            name: m.name, resW: m.width, resH: m.height, rate: Math.round(m.refreshRate),
            x: m.x, y: m.y, scale: m.scale, transform: m.transform, vrr: m.vrr ? 1 : 0 }));
        Config.setSetting("monitors", arr);
    }
    function revertDisplay() {
        confirmTimer.stop();
        let r = root.monRevert;
        if (r) root.sh("hyprctl eval '" + root.luaMon(r.name, { mode: r.mode, position: r.position, scale: r.scale, transform: r.transform, vrr: r.vrr }) + "'");
        root.monRevert = null;
        monRefresh.restart();
    }
    Timer { id: monRefresh; interval: 700; onTriggered: monPoll.running = true }
    Timer {
        id: confirmTimer
        interval: 1000; repeat: true
        onTriggered: { root.monCountdown--; if (root.monCountdown <= 0) root.revertDisplay(); }
    }
    // projection (live only, like Win+P): needs the laptop screen + at least one external one
    readonly property string projection: {
        if (!internal || externals.length === 0) return "";
        if (internal.disabled) return "second";
        if (externals.every(m => m.disabled)) return "this";
        if (externals.some(m => m.mirrorOf && m.mirrorOf !== "none")) return "duplicate";
        return "extend";
    }
    function project(modeName) {
        if (!root.internal || root.externals.length === 0) return;
        let cmds = [], i = root.internal.name;
        if (modeName === "this") {
            cmds.push(root.luaMon(i, { mode: "preferred", position: "auto", scale: root.internal.scale }));
            for (let e of root.externals) cmds.push(root.luaMon(e.name, { disabled: true }));
        } else if (modeName === "second") {
            for (let e of root.externals) cmds.push(root.luaMon(e.name, { mode: "preferred", position: "auto", scale: 1 }));
            cmds.push(root.luaMon(i, { disabled: true }));
        } else if (modeName === "duplicate") {
            cmds.push(root.luaMon(i, { mode: "preferred", position: "auto", scale: root.internal.scale }));
            for (let e of root.externals) cmds.push(root.luaMon(e.name, { mode: "preferred", position: "auto", scale: 1, mirror: i }));
        } else {
            cmds.push(root.luaMon(i, { mode: "preferred", position: "0x0", scale: root.internal.scale }));
            for (let e of root.externals) cmds.push(root.luaMon(e.name, { mode: "preferred", position: "auto-right", scale: 1 }));
        }
        root.sh("hyprctl eval '" + cmds.join(" ") + "'");
        monRefresh.restart();
    }

    // =====================================================================
    // UI
    // =====================================================================
    Item {
        anchors.fill: parent
        opacity: root.introMain
        scale: 0.95 + 0.05 * root.introMain
        transform: Translate { y: root.s(20) * (1 - root.introMain) }

        // liquid glass: radius matches qs-master corner_radius (config/hyprliquid.json)
        Rectangle {
            anchors.fill: parent
            radius: 48
            color: Qt.rgba(root.base.r, root.base.g, root.base.b, 0.06)
        }
        MouseArea { anchors.fill: parent; onClicked: root.forceActiveFocus() }

        RowLayout {
            anchors.fill: parent
            anchors.margins: root.s(34)
            spacing: root.s(28)

            // ---------------- sidebar ----------------
            ColumnLayout {
                Layout.preferredWidth: root.s(220)
                Layout.maximumWidth: root.s(220)
                Layout.fillHeight: true
                spacing: root.s(22)
                opacity: root.introSide
                transform: Translate { x: root.s(-20) * (1 - root.introSide) }

                Text {
                    Layout.leftMargin: root.s(6)
                    text: "Settings"
                    color: root.text
                    font.family: root.ui; font.weight: Font.Black; font.pixelSize: root.s(32)
                }

                Item {
                    id: nav
                    Layout.fillWidth: true
                    Layout.preferredHeight: root.pages.length * root.s(54)
                    Rectangle {   // sliding highlight
                        width: parent.width; height: root.s(48)
                        radius: height / 2
                        y: root.page * root.s(54)
                        color: root.tint(0.9)
                        Behavior on y { NumberAnimation { duration: 420; easing.type: Easing.OutBack; easing.overshoot: 1.1 } }
                    }
                    Column {
                        anchors.fill: parent
                        Repeater {
                            model: root.pages
                            Item {
                                width: nav.width; height: root.s(54)
                                readonly property bool active: root.page === index
                                Row {
                                    anchors.left: parent.left; anchors.leftMargin: root.s(20)
                                    anchors.verticalCenter: parent.verticalCenter; anchors.verticalCenterOffset: -root.s(3)
                                    spacing: root.s(14)
                                    Text {
                                        anchors.verticalCenter: parent.verticalCenter
                                        text: modelData.icon
                                        color: active ? root.base : (navMa.containsMouse ? root.text : root.subtext0)
                                        font.family: root.icons; font.pixelSize: root.s(19)
                                        Behavior on color { ColorAnimation { duration: 200 } }
                                    }
                                    Text {
                                        anchors.verticalCenter: parent.verticalCenter
                                        text: modelData.label
                                        color: active ? root.base : (navMa.containsMouse ? root.text : root.subtext0)
                                        font.family: root.ui; font.weight: active ? Font.Bold : Font.DemiBold; font.pixelSize: root.s(16)
                                        Behavior on color { ColorAnimation { duration: 200 } }
                                    }
                                }
                                Rectangle {   // unsaved changes dot
                                    visible: (index === 0 && root.generalDirty) || (index === 1 && root.kbDirty) || (index === 3 && root.startupDirty)
                                    anchors.right: parent.right; anchors.rightMargin: root.s(18)
                                    anchors.verticalCenter: parent.verticalCenter; anchors.verticalCenterOffset: -root.s(3)
                                    width: root.s(8); height: width; radius: width / 2
                                    color: active ? root.base : root.text
                                }
                                MouseArea {
                                    id: navMa
                                    anchors.fill: parent; anchors.bottomMargin: root.s(6)
                                    hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                    onClicked: { root.page = index; root.forceActiveFocus(); }
                                }
                            }
                        }
                    }
                }

                Item { Layout.fillHeight: true }

            }

            // ---------------- content ----------------
            ColumnLayout {
                Layout.fillWidth: true
                Layout.fillHeight: true
                spacing: root.s(20)
                opacity: root.introContent
                transform: Translate { y: root.s(18) * (1 - root.introContent) }

                // page header
                RowLayout {
                    Layout.fillWidth: true
                    Layout.preferredHeight: root.s(56)
                    spacing: root.s(10)
                    ColumnLayout {
                        spacing: root.s(2)
                        Text { text: root.pages[root.page].title; color: root.text; font.family: root.ui; font.weight: Font.Bold; font.pixelSize: root.s(26) }
                    }
                    Item { Layout.fillWidth: true }
                    PillButton {
                        visible: root.page === 1 || root.page === 3
                        label: "Add"; icon: "󰐕"
                        onClicked: {
                            if (root.page === 1) {
                                kbModel.append({ type: "bind", mods: "$mainMod", key: "", dispatcher: "exec", command: "" });
                                root.kbFilter = ""; kbFilterField.text = "";
                                root.kbEditing = kbModel.count - 1; root.kbDirty = true; root.kbRevision++;
                                kbScrollEnd.restart();
                            } else {
                                startupModel.append({ command: "" });
                                root.startupDirty = true;
                                startupScrollEnd.restart();
                            }
                        }
                    }
                    PillButton {
                        visible: root.page !== 2
                        primary: (root.page === 0 && root.generalDirty) || (root.page === 1 && root.kbDirty) || (root.page === 3 && root.startupDirty)
                        label: "Save"; icon: "󰆓"
                        onClicked: {
                            if (root.page === 0) root.saveGeneral();
                            else if (root.page === 1) root.saveKeybinds();
                            else root.saveStartup();
                        }
                    }
                    PillButton {
                        visible: root.page === 2
                        primary: root.monChanged && !root.monRevert
                        enabled: root.monChanged && !root.monRevert
                        label: "Apply"; icon: "󰄬"
                        onClicked: root.applyDisplay()
                    }
                }

                StackLayout {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    currentIndex: root.page

                    // =========================== GENERAL ===========================
                    Page {
                        Card {
                            title: "Appearance"; icon: "󰏘"
                            SettingRow {
                                label: "Interface scale"
                                Stepper {
                                    value: Config.uiScale; from: 0.5; to: 2.0; step: 0.1
                                    display: Config.uiScale.toFixed(1) + "×"
                                    onMoved: (v) => { Config.uiScale = Math.round(v * 10) / 10; root.generalDirty = true; }
                                }
                            }
                            SettingRow {
                                label: "Workspaces"
                                Stepper {
                                    value: Config.workspaceCount; from: 2; to: 10; step: 1
                                    display: Config.workspaceCount
                                    onMoved: (v) => { Config.workspaceCount = v; root.generalDirty = true; }
                                }
                            }
                        }

                        Card {
                            title: "Windows"; icon: "󰖯"
                            SettingRow {
                                label: "Gaps between windows"
                                Stepper { value: Config.winGapsIn; from: 0; to: 40; step: 1; display: Config.winGapsIn + " px"
                                          onMoved: (v) => { Config.winGapsIn = v; root.generalDirty = true; } }
                            }
                            SettingRow {
                                label: "Gaps around the screen edge"
                                Stepper { value: Config.winGapsOut; from: 0; to: 60; step: 1; display: Config.winGapsOut + " px"
                                          onMoved: (v) => { Config.winGapsOut = v; root.generalDirty = true; } }
                            }
                            SettingRow {
                                label: "Border width"
                                Stepper { value: Config.winBorder; from: 0; to: 10; step: 1; display: Config.winBorder + " px"
                                          onMoved: (v) => { Config.winBorder = v; root.generalDirty = true; } }
                            }
                            SettingRow {
                                label: "Corner rounding"
                                Stepper { value: Config.winRounding; from: 0; to: 30; step: 1; display: Config.winRounding + " px"
                                          onMoved: (v) => { Config.winRounding = v; root.generalDirty = true; } }
                            }
                            SettingRow {
                                label: "Blur"
                                ToggleSwitch { on: Config.winBlur; onToggled: { Config.winBlur = !Config.winBlur; root.generalDirty = true; } }
                            }
                            SettingRow {
                                label: "Animations"
                                ToggleSwitch { on: Config.winAnimations; onToggled: { Config.winAnimations = !Config.winAnimations; root.generalDirty = true; } }
                            }
                        }

                        Card {
                            title: "Keyboard & mouse"; icon: "󰌌"
                            SettingRow {
                                label: "Keyboard layouts"
                                Flow {
                                    Layout.preferredWidth: root.s(380)
                                    layoutDirection: Qt.RightToLeft
                                    spacing: root.s(8)
                                    Repeater {
                                        model: Config.language === "" ? [] : Config.language.split(",")
                                        Rectangle {
                                            height: root.s(36); width: langChipRow.implicitWidth + root.s(28)
                                            radius: height / 2
                                            color: root.tint(0.08)
                                            border.width: 1; border.color: root.tint(0.1)
                                            Row {
                                                id: langChipRow
                                                anchors.centerIn: parent; spacing: root.s(8)
                                                Text { anchors.verticalCenter: parent.verticalCenter; text: modelData; color: root.text; font.family: root.ui; font.weight: Font.Bold; font.pixelSize: root.s(14) }
                                                Text {
                                                    anchors.verticalCenter: parent.verticalCenter
                                                    visible: Config.language.split(",").length > 1
                                                    text: "󰅖"; color: rmLangMa.containsMouse ? root.red : root.subtext0
                                                    font.family: root.icons; font.pixelSize: root.s(14)
                                                    MouseArea {
                                                        id: rmLangMa; anchors.fill: parent; anchors.margins: -root.s(6)
                                                        hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                                        onClicked: {
                                                            Config.language = Config.language.split(",").filter(x => x !== modelData).join(",");
                                                            root.generalDirty = true;
                                                        }
                                                    }
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                            // add a layout: type to search
                            Field {
                                id: langSearch
                                Layout.fillWidth: true
                                icon: "󰍉"
                                placeholder: "Add a layout: type a language or code"
                            }
                            Repeater {
                                model: {
                                    let q = langSearch.text.trim().toLowerCase();
                                    if (q === "") return [];
                                    let have = Config.language.split(",");
                                    return Layouts.layouts.filter(l => have.indexOf(l.code) < 0 &&
                                        (l.code.toLowerCase().indexOf(q) === 0 || l.name.toLowerCase().indexOf(q) >= 0)).slice(0, 6);
                                }
                                Rectangle {
                                    Layout.fillWidth: true; Layout.preferredHeight: root.s(44)
                                    radius: root.s(16)
                                    color: addLangMa.containsMouse ? root.tint(0.08) : "transparent"
                                    RowLayout {
                                        anchors.fill: parent; anchors.leftMargin: root.s(18); anchors.rightMargin: root.s(18)
                                        Text { Layout.preferredWidth: root.s(100); text: modelData.code; color: root.text; font.family: root.ui; font.weight: Font.Bold; font.pixelSize: root.s(14) }
                                        Text { Layout.fillWidth: true; elide: Text.ElideRight; text: modelData.name; color: root.subtext0; font.family: root.ui; font.pixelSize: root.s(14) }
                                        Text { text: "󰐕"; color: root.subtext0; font.family: root.icons; font.pixelSize: root.s(15) }
                                    }
                                    MouseArea {
                                        id: addLangMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                        onClicked: {
                                            Config.language = Config.language === "" ? modelData.code : Config.language + "," + modelData.code;
                                            langSearch.text = ""; root.generalDirty = true;
                                        }
                                    }
                                }
                            }
                            SettingRow {
                                label: "Switch layouts with"
                                visible: Config.language.split(",").length > 1
                                Flow {
                                    Layout.preferredWidth: root.s(430)
                                    layoutDirection: Qt.RightToLeft
                                    spacing: root.s(8)
                                    Repeater {
                                        model: Layouts.switchShortcuts
                                        Chip {
                                            label: modelData.label
                                            selected: Config.kbOptions === modelData.val
                                            onClicked: { Config.kbOptions = modelData.val; root.generalDirty = true; }
                                        }
                                    }
                                }
                            }
                            SettingRow {
                                label: "Natural scrolling"
                                ToggleSwitch { on: Config.naturalScroll; onToggled: { Config.naturalScroll = !Config.naturalScroll; root.generalDirty = true; } }
                            }
                            SettingRow {
                                label: "Mouse speed"
                                Stepper {
                                    value: Config.mouseSensitivity; from: -1; to: 1; step: 0.1
                                    display: (Config.mouseSensitivity > 0 ? "+" : "") + Config.mouseSensitivity.toFixed(1)
                                    onMoved: (v) => { Config.mouseSensitivity = Math.round(v * 10) / 10; root.generalDirty = true; }
                                }
                            }
                        }

                        Card {
                            title: "Idle"; icon: "󰒲"
                            SettingRow {
                                label: "Lock the screen after"
                                Stepper { value: Config.idleLockMin; from: 0; to: 240; minutes: true
                                          onMoved: (v) => { Config.idleLockMin = v; root.generalDirty = true; } }
                            }
                            SettingRow {
                                label: "Turn the screen off after"
                                Stepper { value: Config.idleScreenOffMin; from: 0; to: 240; minutes: true
                                          onMoved: (v) => { Config.idleScreenOffMin = v; root.generalDirty = true; } }
                            }
                            SettingRow {
                                label: "Sleep after"; desc: "On battery only"
                                Stepper { value: Config.idleSuspendMin; from: 0; to: 480; minutes: true
                                          onMoved: (v) => { Config.idleSuspendMin = v; root.generalDirty = true; } }
                            }
                        }

                        Card {
                            title: "Weather"; icon: "󰖐"
                            Text {
                                Layout.fillWidth: true
                                wrapMode: Text.WordWrap
                                text: "Free key from openweathermap.org. The city ID is the number at the end of your city's page address there."
                                color: root.subtext0; font.family: root.ui; font.pixelSize: root.s(13)
                            }
                            SettingRow {
                                label: "API key"
                                Field {
                                    id: apiKeyField
                                    Layout.preferredWidth: root.s(380)
                                    secret: true
                                    placeholder: "Paste your key"
                                    onEdited: { Config.weatherApiKey = text; root.generalDirty = true; }
                                }
                            }
                            SettingRow {
                                label: "City ID"
                                Field {
                                    id: cityField
                                    Layout.preferredWidth: root.s(380)
                                    placeholder: "e.g. 2643743"
                                    onEdited: { Config.weatherCityId = text; root.generalDirty = true; }
                                }
                            }
                            SettingRow {
                                label: "Temperature"
                                Segmented {
                                    options: [{ v: "metric", l: "Celsius" }, { v: "imperial", l: "Fahrenheit" }, { v: "standard", l: "Kelvin" }]
                                    current: Config.weatherUnit
                                    onPicked: (v) => { Config.weatherUnit = v; root.generalDirty = true; }
                                }
                            }
                        }
                    }

                    // =========================== KEYBINDS ===========================
                    Page {
                        id: kbPage
                        Timer { id: kbScrollEnd; interval: 80; onTriggered: kbPage.toEnd() }

                        Field {
                            id: kbFilterField
                            Layout.fillWidth: true
                            icon: "󰍉"
                            placeholder: "Search shortcuts: a key, an app, an action…"
                            onEdited: root.kbFilter = text
                        }

                        Card {
                            title: "Built in"; icon: "󰌾"
                            visible: root.kbFilter === ""
                            Repeater {
                                model: [
                                    { mods: ["SUPER"], key: "Z", what: "Minimize window" },
                                    { mods: ["SUPER", "SHIFT"], key: "Z", what: "Restore minimized window" },
                                    { mods: ["SUPER"], key: "P", what: "Picture-in-picture" },
                                    { mods: ["SUPER"], key: "Left drag", what: "Move window" },
                                    { mods: ["SUPER"], key: "Right drag", what: "Resize window" },
                                    { mods: [], key: "3-finger swipe", what: "Switch workspace" },
                                    { mods: [], key: "Lid", what: "Close: screen off · open: screen on" }
                                ]
                                KeyRow { mods: modelData.mods; key: modelData.key; what: modelData.what; locked: true }
                            }
                        }

                        Card {
                            title: "Your shortcuts"; icon: "󰌌"
                            Repeater {
                                model: kbModel
                                ColumnLayout {
                                    id: kbItem
                                    required property int index
                                    required property var model
                                    Layout.fillWidth: true
                                    spacing: 0
                                    readonly property bool editing: root.kbEditing === index
                                    readonly property bool conflict: { root.kbRevision; return !!root.kbConflicts[root.signature(kbItem.model)]; }
                                    visible: { root.kbRevision; return editing || root.kbMatches(kbItem.model); }

                                    KeyRow {
                                        mods: { root.kbRevision; return root.modList(kbItem.model.mods); }
                                        key: { root.kbRevision; return root.keyLabel(kbItem.model.key || "…"); }
                                        what: { root.kbRevision; return root.describe(kbItem.model); }
                                        detail: { root.kbRevision; return kbItem.model.dispatcher === "exec" ? kbItem.model.command : kbItem.model.dispatcher + " " + kbItem.model.command; }
                                        conflict: kbItem.conflict
                                        active: kbItem.editing
                                        onClicked: root.kbEditing = kbItem.editing ? -1 : kbItem.index
                                    }

                                    // inline editor
                                    Rectangle {
                                        Layout.fillWidth: true
                                        Layout.preferredHeight: kbItem.editing ? editCol.implicitHeight + root.s(36) : 0
                                        Layout.topMargin: kbItem.editing ? root.s(6) : 0
                                        Layout.bottomMargin: kbItem.editing ? root.s(10) : 0
                                        visible: Layout.preferredHeight > 1
                                        clip: true
                                        radius: root.s(18)
                                        color: root.tint(0.04)
                                        border.width: 1; border.color: root.tint(0.08)
                                        Behavior on Layout.preferredHeight { NumberAnimation { duration: 260; easing.type: Easing.OutCubic } }

                                        ColumnLayout {
                                            id: editCol
                                            anchors.left: parent.left; anchors.right: parent.right; anchors.top: parent.top
                                            anchors.margins: root.s(18)
                                            spacing: root.s(14)

                                            RowLayout {
                                                Layout.fillWidth: true; spacing: root.s(8)
                                                Text { Layout.preferredWidth: root.s(90); text: "Keys"; color: root.subtext0; font.family: root.ui; font.pixelSize: root.s(14) }
                                                Repeater {
                                                    model: ["SUPER", "SHIFT", "CTRL", "ALT"]
                                                    Chip {
                                                        label: modelData
                                                        selected: { root.kbRevision; return root.modList(kbItem.model.mods).indexOf(modelData) >= 0; }
                                                        onClicked: {
                                                            let l = root.modList(kbItem.model.mods);
                                                            let i = l.indexOf(modelData);
                                                            if (i >= 0) l.splice(i, 1); else l.push(modelData);
                                                            root.setKb(kbItem.index, "mods", root.modsFrom(l));
                                                        }
                                                    }
                                                }
                                                Text { text: "+"; color: root.subtext0; font.family: root.ui; font.pixelSize: root.s(16) }
                                                Field {
                                                    Layout.preferredWidth: root.s(120)
                                                    text: kbItem.model.key
                                                    placeholder: "Key"
                                                    onEdited: root.setKb(kbItem.index, "key", text)
                                                }
                                                Item { Layout.fillWidth: true }
                                                // press the combo instead of typing it
                                                Rectangle {
                                                    id: recBtn
                                                    Layout.preferredHeight: root.s(40); Layout.preferredWidth: recRow.implicitWidth + root.s(30)
                                                    radius: height / 2
                                                    readonly property bool rec: recCapture.activeFocus
                                                    color: rec ? Qt.alpha(root.red, 0.18) : (recMa.containsMouse ? root.tint(0.12) : root.tint(0.06))
                                                    border.width: 1; border.color: rec ? Qt.alpha(root.red, 0.6) : root.tint(0.1)
                                                    Row {
                                                        id: recRow; anchors.centerIn: parent; spacing: root.s(8)
                                                        Text {
                                                            anchors.verticalCenter: parent.verticalCenter
                                                            text: "󰑊"; color: recBtn.rec ? root.red : root.subtext0
                                                            font.family: root.icons; font.pixelSize: root.s(15)
                                                            SequentialAnimation on opacity {
                                                                running: recBtn.rec; loops: Animation.Infinite
                                                                NumberAnimation { to: 0.3; duration: 500 }
                                                                NumberAnimation { to: 1; duration: 500 }
                                                            }
                                                        }
                                                        Text { anchors.verticalCenter: parent.verticalCenter; text: recBtn.rec ? "Press keys…" : "Record"; color: root.text; font.family: root.ui; font.weight: Font.DemiBold; font.pixelSize: root.s(14) }
                                                    }
                                                    MouseArea {
                                                        id: recMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                                        onClicked: recBtn.rec ? root.forceActiveFocus() : recCapture.forceActiveFocus()
                                                    }
                                                    Item {
                                                        id: recCapture
                                                        // Hyprland's "passthru" submap (hyprland.lua) lets every combo reach us
                                                        onActiveFocusChanged: {
                                                            root.recording = activeFocus;
                                                            Quickshell.execDetached(["hyprctl", "dispatch", activeFocus ? "hl.dsp.submap(\"passthru\")" : "hl.dsp.submap(\"reset\")"]);
                                                        }
                                                        Keys.onPressed: (e) => {
                                                            e.accepted = true;
                                                            let modKeys = [Qt.Key_Super_L, Qt.Key_Super_R, Qt.Key_Meta, Qt.Key_Shift, Qt.Key_Control, Qt.Key_Alt, Qt.Key_AltGr];
                                                            if (modKeys.indexOf(e.key) >= 0) return;
                                                            if (e.key === Qt.Key_Escape) { root.forceActiveFocus(); return; }
                                                            let l = [];
                                                            if (e.modifiers & Qt.MetaModifier) l.push("SUPER");
                                                            if (e.modifiers & Qt.ShiftModifier) l.push("SHIFT");
                                                            if (e.modifiers & Qt.ControlModifier) l.push("CTRL");
                                                            if (e.modifiers & Qt.AltModifier) l.push("ALT");
                                                            let names = {};
                                                            names[Qt.Key_Return] = "RETURN"; names[Qt.Key_Enter] = "RETURN"; names[Qt.Key_Space] = "SPACE";
                                                            names[Qt.Key_Tab] = "TAB"; names[Qt.Key_Left] = "left"; names[Qt.Key_Right] = "right";
                                                            names[Qt.Key_Up] = "up"; names[Qt.Key_Down] = "down"; names[Qt.Key_Print] = "Print";
                                                            names[Qt.Key_Backspace] = "BACKSPACE"; names[Qt.Key_Delete] = "DELETE";
                                                            let k = names[e.key];
                                                            if (!k && e.key >= Qt.Key_F1 && e.key <= Qt.Key_F35) k = "F" + (e.key - Qt.Key_F1 + 1);
                                                            if (!k && e.key >= 0x20 && e.key < 0x7f) k = String.fromCharCode(e.key).toUpperCase();
                                                            if (!k) return;
                                                            root.setKb(kbItem.index, "mods", root.modsFrom(l));
                                                            root.setKb(kbItem.index, "key", k);
                                                            root.forceActiveFocus();
                                                        }
                                                    }
                                                }
                                            }

                                            RowLayout {
                                                Layout.fillWidth: true; spacing: root.s(10)
                                                Text { Layout.preferredWidth: root.s(90); text: "When"; color: root.subtext0; font.family: root.ui; font.pixelSize: root.s(14) }
                                                Segmented {
                                                    options: [{ v: "bind", l: "Pressed" }, { v: "binde", l: "Held" }, { v: "bindl", l: "Pressed, also locked" }, { v: "bindel", l: "Held, also locked" }]
                                                    current: { root.kbRevision; return kbItem.model.type; }
                                                    onPicked: (v) => root.setKb(kbItem.index, "type", v)
                                                }
                                            }

                                            RowLayout {
                                                Layout.fillWidth: true; spacing: root.s(10)
                                                Text { Layout.preferredWidth: root.s(90); Layout.alignment: Qt.AlignTop; Layout.topMargin: root.s(10); text: "Action"; color: root.subtext0; font.family: root.ui; font.pixelSize: root.s(14) }
                                                Flow {
                                                    Layout.fillWidth: true; spacing: root.s(8)
                                                    Repeater {
                                                        model: [{ v: "exec", l: "Run command" }, { v: "killactive", l: "Close window" }, { v: "togglefloating", l: "Float" },
                                                                { v: "fullscreen", l: "Fullscreen" }, { v: "movefocus", l: "Move focus" }, { v: "movewindow", l: "Move window" },
                                                                { v: "resizeactive", l: "Resize" }, { v: "workspace", l: "Workspace" }, { v: "movetoworkspace", l: "Send to workspace" }]
                                                        Chip {
                                                            label: modelData.l
                                                            selected: { root.kbRevision; return kbItem.model.dispatcher === modelData.v; }
                                                            onClicked: root.setKb(kbItem.index, "dispatcher", modelData.v)
                                                        }
                                                    }
                                                }
                                            }

                                            RowLayout {
                                                Layout.fillWidth: true; spacing: root.s(10)
                                                Text {
                                                    Layout.preferredWidth: root.s(90)
                                                    text: { root.kbRevision; return kbItem.model.dispatcher === "exec" ? "Command" : "Argument"; }
                                                    color: root.subtext0; font.family: root.ui; font.pixelSize: root.s(14)
                                                }
                                                Field {
                                                    Layout.fillWidth: true
                                                    mono: true
                                                    text: kbItem.model.command
                                                    placeholder: "e.g. kitty  ·  l / r / u / d  ·  3"
                                                    onEdited: root.setKb(kbItem.index, "command", text)
                                                }
                                            }

                                            RowLayout {
                                                Layout.fillWidth: true
                                                spacing: root.s(10)
                                                Text {
                                                    visible: kbItem.conflict
                                                    text: "󰀦  Another shortcut uses the same keys"
                                                    color: root.red; font.family: root.ui; font.pixelSize: root.s(13)
                                                }
                                                Item { Layout.fillWidth: true }
                                                PillButton {
                                                    label: "Delete"; icon: "󰆴"; danger: true
                                                    onClicked: { root.kbEditing = -1; kbModel.remove(kbItem.index); root.kbDirty = true; root.kbRevision++; }
                                                }
                                                PillButton {
                                                    label: "Done"; icon: "󰄬"
                                                    onClicked: root.kbEditing = -1
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }

                    // =========================== DISPLAY ===========================
                    Page {
                        // pick a screen when there's more than one
                        Flow {
                            Layout.fillWidth: true
                            visible: root.monitors.length > 1
                            spacing: root.s(10)
                            Repeater {
                                model: root.monitors
                                Chip {
                                    label: modelData.name + (modelData.disabled ? " (off)" : "")
                                    selected: root.monSel === index
                                    onClicked: root.monSel = index
                                }
                            }
                        }

                        // keep / go back after applying
                        Rectangle {
                            Layout.fillWidth: true
                            Layout.preferredHeight: root.s(72)
                            visible: !!root.monRevert
                            radius: root.s(24)
                            color: root.tint(0.08)
                            border.width: 1; border.color: root.tint(0.15)
                            RowLayout {
                                anchors.fill: parent; anchors.leftMargin: root.s(24); anchors.rightMargin: root.s(14)
                                spacing: root.s(10)
                                Text {
                                    Layout.fillWidth: true
                                    text: "Keep these display settings? Going back in " + root.monCountdown + " s"
                                    color: root.text; font.family: root.ui; font.weight: Font.DemiBold; font.pixelSize: root.s(15)
                                }
                                PillButton { label: "Go back"; onClicked: root.revertDisplay() }
                                PillButton { label: "Keep"; primary: true; onClicked: root.keepDisplay() }
                            }
                        }

                        Card {
                            title: root.mon ? root.mon.name : "Screen"; icon: "󰍹"
                            note: root.mon ? (root.mon.description || "") : "Reading displays…"

                            RowLayout {
                                Layout.fillWidth: true
                                spacing: root.s(28)
                                visible: !!root.mon && !!root.monPending

                                // preview: follows the chosen resolution and rotation
                                Item {
                                    id: prevBox
                                    Layout.preferredWidth: root.s(230); Layout.preferredHeight: root.s(230)
                                    Layout.alignment: Qt.AlignTop
                                    readonly property var wh: {
                                        if (!root.monPending) return [16, 10];
                                        let m = root.monPending.mode.match(/^(\d+)x(\d+)/);
                                        return m ? [parseInt(m[1]), parseInt(m[2])] : [16, 10];
                                    }
                                    Rectangle {
                                        anchors.centerIn: parent
                                        readonly property real k: root.s(190) / Math.max(prevBox.wh[0], prevBox.wh[1])
                                        width: prevBox.wh[0] * k; height: prevBox.wh[1] * k
                                        rotation: root.monPending ? [0, 90, 180, 270][root.monPending.transform % 4] : 0
                                        Behavior on rotation { NumberAnimation { duration: 600; easing.type: Easing.OutBack } }
                                        radius: root.s(14)
                                        color: root.tint(0.06)
                                        border.width: root.s(3); border.color: root.tint(0.35)
                                        Column {
                                            anchors.centerIn: parent
                                            spacing: root.s(4)
                                            Text { anchors.horizontalCenter: parent.horizontalCenter; text: "󰍹"; color: root.text; font.family: root.icons; font.pixelSize: root.s(28) }
                                            Text {
                                                anchors.horizontalCenter: parent.horizontalCenter
                                                text: root.monPending ? root.monPending.mode.replace(/@.*/, "").replace("x", " × ") : ""
                                                color: root.subtext0; font.family: root.ui; font.weight: Font.DemiBold; font.pixelSize: root.s(13)
                                            }
                                        }
                                        Rectangle {   // top edge marker so the rotation reads
                                            anchors.horizontalCenter: parent.horizontalCenter; anchors.top: parent.top; anchors.topMargin: root.s(8)
                                            width: root.s(28); height: root.s(4); radius: height / 2; color: root.tint(0.5)
                                        }
                                    }
                                }

                                ColumnLayout {
                                    Layout.fillWidth: true
                                    spacing: root.s(18)

                                    SettingRow {
                                        label: "Resolution"
                                        Flow {
                                            Layout.preferredWidth: root.s(320); layoutDirection: Qt.RightToLeft; spacing: root.s(8)
                                            Repeater {
                                                model: root.monModes
                                                Chip {
                                                    label: modelData.res.replace("x", " × ")
                                                    selected: !!root.monPending && root.monPending.mode.indexOf(modelData.res + "@") === 0
                                                    onClicked: root.pend("mode", modelData.res + "@" + modelData.rates[0])
                                                }
                                            }
                                        }
                                    }
                                    SettingRow {
                                        label: "Refresh rate"
                                        Flow {
                                            Layout.preferredWidth: root.s(320); layoutDirection: Qt.RightToLeft; spacing: root.s(8)
                                            Repeater {
                                                model: {
                                                    if (!root.monPending) return [];
                                                    let res = root.monPending.mode.split("@")[0];
                                                    let r = root.monModes.find(x => x.res === res);
                                                    return r ? r.rates : [];
                                                }
                                                Chip {
                                                    label: Math.round(parseFloat(modelData)) + " Hz"
                                                    selected: !!root.monPending && root.monPending.mode.split("@")[1] === modelData
                                                    onClicked: root.pend("mode", root.monPending.mode.split("@")[0] + "@" + modelData)
                                                }
                                            }
                                        }
                                    }
                                    SettingRow {
                                        label: "Scale"
                                        Segmented {
                                            options: [{ v: 1, l: "100%" }, { v: 1.25, l: "125%" }, { v: 1.5, l: "150%" }, { v: 2, l: "200%" }]
                                            current: root.monPending ? root.monPending.scale : 1
                                            onPicked: (v) => root.pend("scale", v)
                                        }
                                    }
                                    SettingRow {
                                        label: "Rotation"
                                        Segmented {
                                            options: [{ v: 0, l: "Normal" }, { v: 1, l: "90°" }, { v: 2, l: "180°" }, { v: 3, l: "270°" }]
                                            current: root.monPending ? root.monPending.transform : 0
                                            onPicked: (v) => root.pend("transform", v)
                                        }
                                    }
                                    SettingRow {
                                        label: "Adaptive sync"
                                        ToggleSwitch { on: !!root.monPending && root.monPending.vrr === 1; onToggled: root.pend("vrr", root.monPending.vrr === 1 ? 0 : 1) }
                                    }
                                }
                            }
                        }

                        Card {
                            title: "Project"; icon: "󰐯"
                            note: root.projection === "" ? "Plug in a second screen to use these" : ""
                            GridLayout {
                                Layout.fillWidth: true
                                columns: 4
                                columnSpacing: root.s(12)
                                Repeater {
                                    model: [{ v: "this", l: "This screen only", i: "󰌢" }, { v: "duplicate", l: "Duplicate", i: "󰍺" },
                                            { v: "extend", l: "Extend", i: "󰍹" }, { v: "second", l: "Second screen only", i: "󰡁" }]
                                    Rectangle {
                                        id: projTile
                                        Layout.fillWidth: true; Layout.preferredHeight: root.s(112)
                                        readonly property bool on: root.projection === modelData.v
                                        readonly property bool usable: root.projection !== ""
                                        radius: root.s(22)
                                        opacity: usable ? 1 : 0.4
                                        color: on ? root.tint(0.9) : (projMa.containsMouse && usable ? root.tint(0.1) : root.tint(0.05))
                                        border.width: 1; border.color: root.tint(0.1)
                                        scale: projMa.pressed && usable ? 0.96 : 1
                                        Behavior on color { ColorAnimation { duration: 200 } }
                                        Behavior on scale { NumberAnimation { duration: 250; easing.type: Easing.OutBack } }
                                        Column {
                                            anchors.centerIn: parent; spacing: root.s(10)
                                            Text { anchors.horizontalCenter: parent.horizontalCenter; text: modelData.i; color: projTile.on ? root.base : root.text; font.family: root.icons; font.pixelSize: root.s(30) }
                                            Text { anchors.horizontalCenter: parent.horizontalCenter; text: modelData.l; color: projTile.on ? root.base : root.text; font.family: root.ui; font.weight: Font.DemiBold; font.pixelSize: root.s(14) }
                                        }
                                        MouseArea { id: projMa; anchors.fill: parent; hoverEnabled: true; enabled: projTile.usable; cursorShape: Qt.PointingHandCursor; onClicked: root.project(modelData.v) }
                                    }
                                }
                            }
                        }
                    }

                    // =========================== STARTUP ===========================
                    Page {
                        id: startupPage
                        Timer { id: startupScrollEnd; interval: 80; onTriggered: startupPage.toEnd() }

                        Card {
                            title: "Runs at login"; icon: "󰐥"
                            Repeater {
                                model: startupModel
                                RowLayout {
                                    id: suRow
                                    required property int index
                                    required property var model
                                    readonly property bool locked: root.isCore(model.command)
                                    Layout.fillWidth: true
                                    spacing: root.s(10)

                                    Field {
                                        Layout.fillWidth: true
                                        mono: true
                                        readOnly: suRow.locked
                                        icon: suRow.locked ? "󰌾" : "󰐊"
                                        text: suRow.model.command
                                        placeholder: "Command to run, e.g. vesktop"
                                        onEdited: { startupModel.setProperty(suRow.index, "command", text); root.startupDirty = true; }
                                        Component.onCompleted: if (text === "") focusInput()
                                    }
                                    IconBtn {
                                        visible: !suRow.locked
                                        icon: "󰆴"; danger: true
                                        onClicked: { startupModel.remove(suRow.index); root.startupDirty = true; }
                                    }
                                    Item { visible: suRow.locked; Layout.preferredWidth: root.s(44) }
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    // =====================================================================
    // COMPONENTS
    // =====================================================================
    // scrolling page of cards
    component Page: Flickable {
        id: pg
        default property alias content: pageCol.data
        contentWidth: width
        contentHeight: pageCol.implicitHeight + root.s(30)
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        function toEnd() { contentY = Math.max(0, contentHeight - height); }
        ScrollBar.vertical: ScrollBar {
            width: root.s(6); policy: ScrollBar.AsNeeded
            contentItem: Rectangle { implicitWidth: root.s(6); radius: width / 2; color: root.tint(0.25) }
            background: Item {}
        }
        ColumnLayout {
            id: pageCol
            width: pg.width - root.s(14)
            spacing: root.s(20)
        }
    }

    // dashboard-style card
    component Card: Rectangle {
        id: card
        property string title: ""
        property string icon: ""
        property string note: ""
        default property alias content: cardCol.data
        Layout.fillWidth: true
        implicitHeight: cardHead.implicitHeight + cardCol.implicitHeight + root.s(70)
        radius: root.s(26)
        color: Qt.rgba(root.base.r, root.base.g, root.base.b, 0.55)
        border.width: 1
        border.color: root.tint(0.07)
        RowLayout {
            id: cardHead
            anchors.left: parent.left; anchors.right: parent.right; anchors.top: parent.top
            anchors.margins: root.s(26)
            spacing: root.s(10)
            Text { text: card.icon; color: root.subtext0; font.family: root.icons; font.pixelSize: root.s(18); visible: card.icon !== "" }
            Text { text: card.title; color: root.text; font.family: root.ui; font.weight: Font.Bold; font.pixelSize: root.s(18) }
            Text { Layout.fillWidth: true; horizontalAlignment: Text.AlignRight; elide: Text.ElideRight; text: card.note; color: Qt.alpha(root.subtext0, 0.75); font.family: root.ui; font.pixelSize: root.s(13) }
        }
        ColumnLayout {
            id: cardCol
            anchors.left: parent.left; anchors.right: parent.right; anchors.top: cardHead.bottom
            anchors.leftMargin: root.s(26); anchors.rightMargin: root.s(26); anchors.topMargin: root.s(18)
            spacing: root.s(16)
        }
    }

    // label (+ description) on the left, a control on the right
    component SettingRow: RowLayout {
        id: sr
        property string label: ""
        property string desc: ""
        default property alias control: srCtl.data
        Layout.fillWidth: true
        spacing: root.s(16)
        ColumnLayout {
            Layout.fillWidth: true
            spacing: root.s(3)
            Text { Layout.fillWidth: true; text: sr.label; color: root.text; font.family: root.ui; font.weight: Font.DemiBold; font.pixelSize: root.s(15); wrapMode: Text.WordWrap }
            Text { Layout.fillWidth: true; visible: sr.desc !== ""; text: sr.desc; color: root.subtext0; font.family: root.ui; font.pixelSize: root.s(13); wrapMode: Text.WordWrap }
        }
        RowLayout { id: srCtl; Layout.alignment: Qt.AlignRight | Qt.AlignVCenter }
    }

    // − value +   (minutes: 0 shows "Never", steps grow with the value)
    component Stepper: Rectangle {
        id: st
        property real value: 0
        property real from: 0
        property real to: 10
        property real step: 1
        property bool minutes: false
        property string display: minutes ? (value <= 0 ? "Never" : value + " min") : value
        signal moved(real v)
        function stepFor(up) {
            if (!minutes) return step;
            let v = up ? value : value - 1;
            return v < 10 ? 1 : v < 60 ? 5 : 15;
        }
        implicitWidth: root.s(180); implicitHeight: root.s(44)
        Layout.preferredWidth: implicitWidth; Layout.preferredHeight: implicitHeight
        radius: height / 2
        color: root.tint(0.06)
        border.width: 1; border.color: root.tint(0.1)
        RowLayout {
            anchors.fill: parent; anchors.margins: root.s(4)
            spacing: 0
            IconBtn { icon: "󰍴"; small: true; enabled: st.value > st.from; onClicked: st.moved(Math.max(st.from, +(st.value - st.stepFor(false)).toFixed(2))) }
            Text {
                Layout.fillWidth: true
                horizontalAlignment: Text.AlignHCenter
                text: st.display
                color: root.text; font.family: root.ui; font.weight: Font.Bold; font.pixelSize: root.s(15)
            }
            IconBtn { icon: "󰐕"; small: true; enabled: st.value < st.to; onClicked: st.moved(Math.min(st.to, +(st.value + st.stepFor(true)).toFixed(2))) }
        }
    }

    component ToggleSwitch: Rectangle {
        id: sw
        property bool on: false
        signal toggled()
        implicitWidth: root.s(56); implicitHeight: root.s(32)
        Layout.preferredWidth: implicitWidth; Layout.preferredHeight: implicitHeight
        radius: height / 2
        color: on ? root.tint(0.9) : root.tint(0.15)
        Behavior on color { ColorAnimation { duration: 180 } }
        Rectangle {
            width: parent.height - root.s(8); height: width; radius: width / 2
            y: root.s(4)
            x: sw.on ? parent.width - width - root.s(4) : root.s(4)
            color: sw.on ? root.base : root.text
            Behavior on x { NumberAnimation { duration: 250; easing.type: Easing.OutBack } }
        }
        MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: sw.toggled() }
    }

    component Segmented: Rectangle {
        id: seg
        property var options: []
        property var current
        signal picked(var v)
        readonly property int idx: { for (let i = 0; i < options.length; i++) if (options[i].v === current) return i; return -1; }
        implicitWidth: segRow.implicitWidth + root.s(8); implicitHeight: root.s(44)
        Layout.preferredWidth: implicitWidth; Layout.preferredHeight: implicitHeight
        radius: height / 2
        color: root.tint(0.06)
        border.width: 1; border.color: root.tint(0.1)
        Rectangle {   // sliding highlight
            visible: seg.idx >= 0
            // segRep.count makes this re-evaluate once the Repeater has built its items
            readonly property Item cur: segRep.count > 0 && seg.idx >= 0 ? segRep.itemAt(seg.idx) : null
            y: root.s(4); height: parent.height - root.s(8)
            x: cur ? cur.x + root.s(4) : 0
            width: cur ? cur.width : 0
            radius: height / 2
            color: root.tint(0.9)
            Behavior on x { NumberAnimation { duration: 380; easing.type: Easing.OutBack; easing.overshoot: 1.1 } }
            Behavior on width { NumberAnimation { duration: 300; easing.type: Easing.OutCubic } }
        }
        Row {
            id: segRow
            x: root.s(4); anchors.verticalCenter: parent.verticalCenter
            Repeater {
                id: segRep
                model: seg.options
                Item {
                    width: segText.implicitWidth + root.s(32); height: root.s(36)
                    Text {
                        id: segText
                        anchors.centerIn: parent
                        text: modelData.l
                        color: seg.idx === index ? root.base : (segMa.containsMouse ? root.text : root.subtext0)
                        font.family: root.ui; font.weight: Font.DemiBold; font.pixelSize: root.s(14)
                        Behavior on color { ColorAnimation { duration: 200 } }
                    }
                    MouseArea { id: segMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: seg.picked(modelData.v) }
                }
            }
        }
    }

    component Chip: Rectangle {
        id: chip
        property string label: ""
        property bool selected: false
        signal clicked()
        implicitWidth: chipText.implicitWidth + root.s(30); implicitHeight: root.s(38)
        width: implicitWidth; height: implicitHeight
        radius: height / 2
        color: selected ? root.tint(0.9) : (chipMa.containsMouse ? root.tint(0.12) : root.tint(0.06))
        border.width: 1; border.color: root.tint(0.1)
        scale: chipMa.pressed ? 0.95 : 1
        Behavior on color { ColorAnimation { duration: 180 } }
        Behavior on scale { NumberAnimation { duration: 200; easing.type: Easing.OutBack } }
        Text {
            id: chipText
            anchors.centerIn: parent
            text: chip.label
            color: chip.selected ? root.base : root.text
            font.family: root.ui; font.weight: Font.DemiBold; font.pixelSize: root.s(14)
        }
        MouseArea { id: chipMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: chip.clicked() }
    }

    component PillButton: Rectangle {
        id: pb
        property string label: ""
        property string icon: ""
        property bool primary: false
        property bool danger: false
        signal clicked()
        implicitWidth: pbRow.implicitWidth + root.s(36); implicitHeight: root.s(44)
        Layout.preferredWidth: implicitWidth; Layout.preferredHeight: implicitHeight
        radius: height / 2
        opacity: enabled ? 1 : 0.45
        color: danger && pbMa.containsMouse ? Qt.alpha(root.red, 0.18)
             : primary ? root.tint(pbMa.containsMouse ? 0.95 : 0.85)
             : root.tint(pbMa.containsMouse ? 0.12 : 0.06)
        border.width: primary ? 0 : 1
        border.color: danger && pbMa.containsMouse ? Qt.alpha(root.red, 0.5) : root.tint(0.1)
        scale: pbMa.pressed ? 0.95 : (pbMa.containsMouse ? 1.03 : 1)
        Behavior on color { ColorAnimation { duration: 150 } }
        Behavior on scale { NumberAnimation { duration: 220; easing.type: Easing.OutBack } }
        Row {
            id: pbRow
            anchors.centerIn: parent; spacing: root.s(8)
            Text {
                anchors.verticalCenter: parent.verticalCenter; visible: pb.icon !== ""; text: pb.icon
                font.family: root.icons; font.pixelSize: root.s(16)
                color: pb.danger && pbMa.containsMouse ? root.red : pb.primary ? root.base : root.subtext0
            }
            Text {
                anchors.verticalCenter: parent.verticalCenter; text: pb.label
                font.family: root.ui; font.weight: Font.DemiBold; font.pixelSize: root.s(15)
                color: pb.danger && pbMa.containsMouse ? root.red : pb.primary ? root.base : root.text
            }
        }
        MouseArea { id: pbMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: pb.clicked() }
    }

    component IconBtn: Rectangle {
        id: ib
        property string icon: ""
        property bool small: false
        property bool danger: false
        signal clicked()
        implicitWidth: small ? root.s(36) : root.s(46); implicitHeight: implicitWidth
        Layout.preferredWidth: implicitWidth; Layout.preferredHeight: implicitHeight
        radius: width / 2
        opacity: enabled ? 1 : 0.35
        color: ibMa.containsMouse ? (danger ? Qt.alpha(root.red, 0.18) : root.tint(0.14)) : (small ? "transparent" : root.tint(0.06))
        Behavior on color { ColorAnimation { duration: 150 } }
        Text {
            anchors.centerIn: parent
            text: ib.icon
            color: ibMa.containsMouse && ib.danger ? root.red : root.text
            font.family: root.icons; font.pixelSize: root.s(16)
        }
        MouseArea { id: ibMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: ib.clicked() }
    }

    // text field: pill, optional icon, secret (eye toggle), mono
    component Field: Rectangle {
        id: fld
        property alias text: fldInput.text
        property string placeholder: ""
        property string icon: ""
        property bool secret: false
        property bool mono: false
        property bool readOnly: false
        property bool reveal: false
        readonly property bool editing: fldInput.activeFocus
        signal edited()
        function focusInput() { fldInput.forceActiveFocus(); }
        implicitHeight: root.s(48)
        Layout.preferredHeight: implicitHeight
        radius: height / 2
        color: root.tint(fldInput.activeFocus ? 0.1 : (readOnly ? 0.03 : 0.06))
        border.width: 1; border.color: root.tint(fldInput.activeFocus ? 0.25 : 0.08)
        Behavior on color { ColorAnimation { duration: 150 } }
        RowLayout {
            anchors.fill: parent; anchors.leftMargin: root.s(18); anchors.rightMargin: root.s(16)
            spacing: root.s(10)
            Text { visible: fld.icon !== ""; text: fld.icon; color: root.subtext0; font.family: root.icons; font.pixelSize: root.s(15) }
            TextInput {
                id: fldInput
                Layout.fillWidth: true; Layout.fillHeight: true
                verticalAlignment: TextInput.AlignVCenter
                clip: true; selectByMouse: true
                readOnly: fld.readOnly
                echoMode: fld.secret && !fld.reveal ? TextInput.Password : TextInput.Normal
                passwordCharacter: "•"
                color: fld.readOnly ? Qt.alpha(root.subtext0, 0.85) : root.text
                font.family: fld.mono ? "Maple Mono Normal NF" : root.ui
                font.pixelSize: root.s(fld.mono ? 13 : 15)
                onTextEdited: fld.edited()
                Keys.onEscapePressed: (e) => { root.forceActiveFocus(); e.accepted = true; }
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    visible: fldInput.text === "" && !fldInput.activeFocus
                    text: fld.placeholder
                    color: Qt.alpha(root.subtext0, 0.55)
                    font: fldInput.font
                }
            }
            Text {
                visible: fld.secret
                text: fld.reveal ? "󰈈" : "󰈉"
                color: eyeMa.containsMouse ? root.text : root.subtext0
                font.family: root.icons; font.pixelSize: root.s(16)
                MouseArea { id: eyeMa; anchors.fill: parent; anchors.margins: -root.s(6); hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: fld.reveal = !fld.reveal }
            }
        }
    }

    // one shortcut: key chips + what it does
    component KeyRow: Rectangle {
        id: kr
        property var mods: []
        property string key: ""
        property string what: ""
        property string detail: ""
        property bool locked: false
        property bool conflict: false
        property bool active: false
        signal clicked()
        Layout.fillWidth: true
        implicitHeight: root.s(detail !== "" ? 62 : 50)
        Layout.preferredHeight: implicitHeight
        radius: root.s(16)
        color: active ? root.tint(0.08) : (krMa.containsMouse && !locked ? root.tint(0.06) : "transparent")
        Behavior on color { ColorAnimation { duration: 150 } }
        RowLayout {
            anchors.fill: parent; anchors.leftMargin: root.s(14); anchors.rightMargin: root.s(14)
            spacing: root.s(16)
            Row {
                Layout.preferredWidth: root.s(250)
                spacing: root.s(6)
                Repeater {
                    model: kr.mods.concat([kr.key])
                    Rectangle {
                        height: root.s(30); width: Math.max(height, kcText.implicitWidth + root.s(18))
                        radius: root.s(9)
                        color: kr.conflict ? Qt.alpha(root.red, 0.16) : root.tint(0.1)
                        border.width: 1; border.color: kr.conflict ? Qt.alpha(root.red, 0.5) : root.tint(0.12)
                        Text { id: kcText; anchors.centerIn: parent; text: modelData; color: root.text; font.family: root.ui; font.weight: Font.Bold; font.pixelSize: root.s(13) }
                    }
                }
            }
            ColumnLayout {
                Layout.fillWidth: true
                spacing: root.s(2)
                Text { Layout.fillWidth: true; elide: Text.ElideRight; text: kr.what; color: kr.locked ? root.subtext0 : root.text; font.family: root.ui; font.weight: Font.DemiBold; font.pixelSize: root.s(15) }
                Text { Layout.fillWidth: true; visible: kr.detail !== ""; elide: Text.ElideMiddle; text: kr.detail; color: Qt.alpha(root.subtext0, 0.7); font.family: "Maple Mono Normal NF"; font.pixelSize: root.s(12) }
            }
            Text {
                text: kr.locked ? "󰌾" : (kr.active ? "󰅃" : "󰏫")
                color: root.subtext0
                opacity: kr.locked || kr.active || krMa.containsMouse ? 1 : 0
                font.family: root.icons; font.pixelSize: root.s(15)
                Behavior on opacity { NumberAnimation { duration: 150 } }
            }
        }
        MouseArea { id: krMa; anchors.fill: parent; enabled: !kr.locked; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: kr.clicked() }
    }
}
