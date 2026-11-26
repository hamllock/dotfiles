import QtQuick
import QtQuick.Layouts
import QtQuick.Window
import Quickshell
import Quickshell.Io
import "../"

// Autoclicker HUD (SUPER+A). Edits ~/.config/autoclicker/config.json,
// which ~/.local/bin/autoclicker reads every time it starts. F6 toggles clicking.
FocusScope {
    id: root
    focus: true

    property var notifModel
    property var liveNotifs
    property real layoutWidth
    property real layoutHeight

    Scaler { id: scaler; currentWidth: Screen.width; currentHeight: Screen.height }
    function s(v) { return scaler.s(v); }

    MatugenColors { id: _theme }
    readonly property color base: _theme.base
    readonly property color text: _theme.text
    readonly property color subtext0: _theme.subtext0
    readonly property color accent: _theme.mauve
    readonly property color red: _theme.red
    readonly property color green: _theme.green
    readonly property string ui: "SF Pro Display"
    readonly property string icons: "Iosevka Nerd Font"
    function tint(a) { return Qt.rgba(root.text.r, root.text.g, root.text.b, a); }
    function g(cp) { return String.fromCodePoint(cp); }

    readonly property string home: Quickshell.env("HOME")
    readonly property string bin: home + "/.local/bin/autoclicker"
    readonly property string confPath: home + "/.config/autoclicker/config.json"
    readonly property string pidPath: (Quickshell.env("XDG_RUNTIME_DIR") || "/tmp") + "/autoclicker.pid"

    // ---------------- settings ----------------
    property int hours: 0
    property int mins: 0
    property int secs: 0
    property int ms: 100
    property string button: "left"
    property string clickType: "single"
    property string repeatMode: "forever"
    property int count: 10
    property string position: "current"
    property int px: 0
    property int py: 0

    property bool loaded: false
    property bool running: false
    property int pickLeft: 0

    readonly property real intervalSec: hours * 3600 + mins * 60 + secs + ms / 1000
    readonly property string rateText: intervalSec <= 0 ? "interval can't be 0"
        : intervalSec < 1 ? "≈ " + (1 / intervalSec).toFixed(1).replace(/\.0$/, "") + " clicks / sec"
        : "1 click every " + (+intervalSec.toFixed(3)) + " s"

    function configJson() {
        return JSON.stringify({
            hours: hours, mins: mins, secs: secs, ms: ms,
            button: button, clickType: clickType,
            repeatMode: repeatMode, count: Math.max(1, count),
            position: position, x: px, y: py
        }, null, 2);
    }

    onHoursChanged: queueSave()
    onMinsChanged: queueSave()
    onSecsChanged: queueSave()
    onMsChanged: queueSave()
    onButtonChanged: queueSave()
    onClickTypeChanged: queueSave()
    onRepeatModeChanged: queueSave()
    onCountChanged: queueSave()
    onPositionChanged: queueSave()
    onPxChanged: queueSave()
    onPyChanged: queueSave()
    function queueSave() { if (loaded) saveTimer.restart(); }
    Timer { id: saveTimer; interval: 250; onTriggered: root.save() }

    function save() {
        saveTimer.stop();
        saveProc.command = ["sh", "-c", 'mkdir -p "$(dirname "$1")" && printf "%s\\n" "$2" > "$1"',
                            "sh", root.confPath, root.configJson()];
        saveProc.running = true;
    }
    Process { id: saveProc }

    Process {
        running: true
        command: ["cat", root.confPath]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    let c = JSON.parse(this.text);
                    if (c.hours !== undefined) root.hours = c.hours;
                    if (c.mins !== undefined) root.mins = c.mins;
                    if (c.secs !== undefined) root.secs = c.secs;
                    if (c.ms !== undefined) root.ms = c.ms;
                    if (c.button) root.button = c.button;
                    if (c.clickType) root.clickType = c.clickType;
                    if (c.repeatMode) root.repeatMode = c.repeatMode;
                    if (c.count !== undefined) root.count = c.count;
                    if (c.position) root.position = c.position;
                    if (c.x !== undefined) root.px = c.x;
                    if (c.y !== undefined) root.py = c.y;
                } catch (e) {}
                root.loaded = true;
            }
        }
        onExited: (code) => { if (code !== 0) root.loaded = true; }
    }

    // ---------------- status ----------------
    Process {
        id: statusProc
        command: ["sh", "-c", 'p=$(cat "$1" 2>/dev/null) && kill -0 "$p" 2>/dev/null && echo on || echo off', "sh", root.pidPath]
        stdout: StdioCollector { onStreamFinished: root.running = this.text.trim() === "on" }
    }
    Timer { interval: 500; running: true; repeat: true; triggeredOnStart: true; onTriggered: statusProc.running = true }

    function toggleClicking() {
        if (root.running) {
            Quickshell.execDetached([root.bin, "stop"]);
            root.running = false;
            return;
        }
        if (root.intervalSec <= 0) return;
        root.save();
        // close the HUD first so the clicks don't land on it
        Quickshell.execDetached(["bash", root.home + "/.config/hypr/scripts/qs_manager.sh", "close"]);
        Quickshell.execDetached(["sh", "-c", "sleep 0.35; exec \"$1\" start", "sh", root.bin]);
    }

    // ---------------- pick location ----------------
    function startPick() { root.pickLeft = 3; pickTimer.restart(); }
    Timer {
        id: pickTimer; interval: 1000; repeat: true
        onTriggered: {
            root.pickLeft -= 1;
            if (root.pickLeft <= 0) { stop(); cursorProc.running = true; }
        }
    }
    Process {
        id: cursorProc
        command: ["hyprctl", "cursorpos"]
        stdout: StdioCollector {
            onStreamFinished: {
                let m = this.text.trim().split(",");
                if (m.length === 2) {
                    root.px = parseInt(m[0]);
                    root.py = parseInt(m[1]);
                    root.position = "fixed";
                }
            }
        }
    }

    // ---------------- reusable bits ----------------
    component SectionLabel: Text {
        property var app
        color: app.subtext0
        font.family: app.ui; font.pixelSize: app.s(11); font.weight: Font.DemiBold
        font.letterSpacing: app.s(1)
    }

    component Seg: Rectangle {
        id: seg
        property var app
        property var options: []      // [{ v: "left", label: "Left" }]
        property string value
        signal picked(string v)
        implicitHeight: app.s(38)
        radius: app.s(12)
        color: app.tint(0.06)
        RowLayout {
            anchors.fill: parent
            anchors.margins: seg.app.s(3)
            spacing: seg.app.s(3)
            Repeater {
                model: seg.options
                Rectangle {
                    readonly property bool sel: seg.value === modelData.v
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    radius: seg.app.s(9)
                    color: sel ? seg.app.tint(0.16) : segMa.containsMouse ? seg.app.tint(0.07) : "transparent"
                    Behavior on color { ColorAnimation { duration: 120 } }
                    Text {
                        anchors.centerIn: parent
                        text: modelData.label
                        color: parent.sel ? seg.app.text : seg.app.subtext0
                        font.family: seg.app.ui; font.pixelSize: seg.app.s(13)
                        font.weight: parent.sel ? Font.DemiBold : Font.Medium
                    }
                    MouseArea {
                        id: segMa
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: seg.picked(modelData.v)
                    }
                }
            }
        }
    }

    component NumField: Rectangle {
        id: nf
        property var app
        property int value: 0
        property int maxValue: 99999
        property string unit: ""
        property bool active: true
        signal edited(int v)
        implicitHeight: app.s(44)
        radius: app.s(12)
        opacity: active ? 1 : 0.4
        color: input.activeFocus ? app.tint(0.1) : app.tint(0.06)
        border.width: input.activeFocus ? 1 : 0
        border.color: Qt.alpha(app.accent, 0.7)
        onValueChanged: if (parseInt(input.text) !== value) input.text = String(value)
        TextInput {
            id: input
            anchors.left: parent.left
            anchors.right: unitText.left
            anchors.verticalCenter: parent.verticalCenter
            anchors.leftMargin: nf.app.s(12)
            anchors.rightMargin: nf.app.s(4)
            text: String(nf.value)
            enabled: nf.active
            color: nf.app.text
            selectByMouse: true
            selectionColor: Qt.alpha(nf.app.accent, 0.5)
            font.family: nf.app.ui; font.pixelSize: nf.app.s(16); font.weight: Font.DemiBold
            validator: IntValidator { bottom: 0; top: nf.maxValue }
            onTextEdited: nf.edited(parseInt(text) || 0)
            onActiveFocusChanged: if (activeFocus) selectAll()
            Keys.onUpPressed: nf.edited(Math.min(nf.maxValue, nf.value + 1))
            Keys.onDownPressed: nf.edited(Math.max(0, nf.value - 1))
        }
        Text {
            id: unitText
            anchors.right: parent.right
            anchors.rightMargin: nf.app.s(12)
            anchors.verticalCenter: parent.verticalCenter
            text: nf.unit
            color: nf.app.subtext0
            font.family: nf.app.ui; font.pixelSize: nf.app.s(12)
        }
        MouseArea {
            anchors.fill: parent
            enabled: !input.activeFocus && nf.active
            cursorShape: Qt.IBeamCursor
            onClicked: input.forceActiveFocus()
            onWheel: (w) => nf.edited(Math.max(0, Math.min(nf.maxValue, nf.value + (w.angleDelta.y > 0 ? 1 : -1))))
        }
    }

    // ---------------- intro ----------------
    property real intro: 0
    NumberAnimation on intro { from: 0; to: 1; duration: 450; easing.type: Easing.OutQuart; running: true }

    Item {
        anchors.fill: parent
        opacity: root.intro
        scale: 0.95 + 0.05 * root.intro
        transform: Translate { y: root.s(12) * (1 - root.intro) }

        // liquid glass sits behind qs-master; this is just a faint wash
        Rectangle {
            anchors.fill: parent
            radius: 48
            color: Qt.rgba(root.base.r, root.base.g, root.base.b, 0.06)
        }

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: root.s(24)
            spacing: root.s(16)

            // ---------------- header ----------------
            RowLayout {
                Layout.fillWidth: true
                spacing: root.s(12)
                Rectangle {
                    Layout.preferredWidth: root.s(42); Layout.preferredHeight: root.s(42)
                    radius: root.s(13)
                    color: root.running ? Qt.alpha(root.green, 0.2) : root.tint(0.08)
                    Behavior on color { ColorAnimation { duration: 200 } }
                    Text {
                        anchors.centerIn: parent
                        text: root.g(0xF037D)   // mouse
                        color: root.running ? root.green : root.text
                        font.family: root.icons; font.pixelSize: root.s(20)
                    }
                }
                Column {
                    Layout.fillWidth: true
                    spacing: root.s(2)
                    Text {
                        text: "Autoclicker"
                        color: root.text
                        font.family: root.ui; font.weight: Font.Bold; font.pixelSize: root.s(18)
                    }
                    Text {
                        text: "F6 to start / stop"
                        color: root.subtext0
                        font.family: root.ui; font.pixelSize: root.s(12)
                    }
                }
                Rectangle {
                    Layout.preferredHeight: root.s(26)
                    Layout.preferredWidth: statusText.implicitWidth + root.s(24)
                    radius: height / 2
                    color: root.running ? Qt.alpha(root.green, 0.18) : root.tint(0.07)
                    Row {
                        anchors.centerIn: parent
                        spacing: root.s(6)
                        Rectangle {
                            width: root.s(7); height: width; radius: width / 2
                            anchors.verticalCenter: parent.verticalCenter
                            color: root.running ? root.green : root.subtext0
                            SequentialAnimation on opacity {
                                running: root.running; loops: Animation.Infinite
                                NumberAnimation { to: 0.3; duration: 500 }
                                NumberAnimation { to: 1; duration: 500 }
                            }
                        }
                        Text {
                            id: statusText
                            text: root.running ? "Running" : "Idle"
                            color: root.running ? root.green : root.subtext0
                            font.family: root.ui; font.pixelSize: root.s(12); font.weight: Font.DemiBold
                        }
                    }
                }
            }

            // ---------------- interval ----------------
            ColumnLayout {
                Layout.fillWidth: true
                spacing: root.s(8)
                RowLayout {
                    Layout.fillWidth: true
                    SectionLabel { app: root; text: "CLICK INTERVAL" }
                    Item { Layout.fillWidth: true }
                    Text {
                        text: root.rateText
                        color: root.intervalSec <= 0 ? root.red : root.subtext0
                        font.family: root.ui; font.pixelSize: root.s(11)
                    }
                }
                RowLayout {
                    Layout.fillWidth: true
                    spacing: root.s(8)
                    NumField { app: root; Layout.fillWidth: true; unit: "h";   maxValue: 99;  value: root.hours; onEdited: (v) => root.hours = v }
                    NumField { app: root; Layout.fillWidth: true; unit: "m";   maxValue: 59;  value: root.mins;  onEdited: (v) => root.mins = v }
                    NumField { app: root; Layout.fillWidth: true; unit: "s";   maxValue: 59;  value: root.secs;  onEdited: (v) => root.secs = v }
                    NumField { app: root; Layout.fillWidth: true; unit: "ms";  maxValue: 999; value: root.ms;    onEdited: (v) => root.ms = v }
                }
            }

            // ---------------- click options ----------------
            ColumnLayout {
                Layout.fillWidth: true
                spacing: root.s(8)
                SectionLabel { app: root; text: "CLICK OPTIONS" }
                Seg {
                    app: root; Layout.fillWidth: true
                    options: [{ v: "left", label: "Left" }, { v: "middle", label: "Middle" }, { v: "right", label: "Right" }]
                    value: root.button
                    onPicked: (v) => root.button = v
                }
                Seg {
                    app: root; Layout.fillWidth: true
                    options: [{ v: "single", label: "Single" }, { v: "double", label: "Double" }]
                    value: root.clickType
                    onPicked: (v) => root.clickType = v
                }
            }

            // ---------------- repeat ----------------
            ColumnLayout {
                Layout.fillWidth: true
                spacing: root.s(8)
                SectionLabel { app: root; text: "CLICK REPEAT" }
                RowLayout {
                    Layout.fillWidth: true
                    spacing: root.s(8)
                    Seg {
                        app: root; Layout.fillWidth: true
                        options: [{ v: "forever", label: "Until stopped" }, { v: "count", label: "Repeat" }]
                        value: root.repeatMode
                        onPicked: (v) => root.repeatMode = v
                    }
                    NumField {
                        app: root
                        Layout.preferredWidth: root.s(120)
                        implicitHeight: root.s(38)
                        unit: "times"
                        active: root.repeatMode === "count"
                        value: root.count
                        onEdited: (v) => root.count = v
                    }
                }
            }

            // ---------------- position ----------------
            ColumnLayout {
                Layout.fillWidth: true
                spacing: root.s(8)
                SectionLabel { app: root; text: "CURSOR POSITION" }
                Seg {
                    app: root; Layout.fillWidth: true
                    options: [{ v: "current", label: "Current location" }, { v: "fixed", label: "Pick location" }]
                    value: root.position
                    onPicked: (v) => root.position = v
                }
                RowLayout {
                    Layout.fillWidth: true
                    spacing: root.s(8)
                    opacity: root.position === "fixed" ? 1 : 0.4
                    NumField { app: root; Layout.fillWidth: true; implicitHeight: root.s(38); unit: "X"; active: root.position === "fixed"; value: root.px; onEdited: (v) => root.px = v }
                    NumField { app: root; Layout.fillWidth: true; implicitHeight: root.s(38); unit: "Y"; active: root.position === "fixed"; value: root.py; onEdited: (v) => root.py = v }
                    Rectangle {
                        Layout.preferredWidth: root.s(118); Layout.preferredHeight: root.s(38)
                        radius: root.s(12)
                        color: root.pickLeft > 0 ? Qt.alpha(root.accent, 0.25) : pickMa.containsMouse ? root.tint(0.12) : root.tint(0.07)
                        Text {
                            anchors.centerIn: parent
                            text: root.pickLeft > 0 ? "Hover… " + root.pickLeft : root.g(0xF01A4) + "  Pick"
                            color: root.text
                            font.family: root.pickLeft > 0 ? root.ui : root.icons
                            font.pixelSize: root.s(13); font.weight: Font.DemiBold
                        }
                        MouseArea {
                            id: pickMa
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.startPick()
                        }
                    }
                }
                Text {
                    visible: root.pickLeft > 0
                    text: "Move the mouse to the spot to click. It's saved when the timer hits 0."
                    color: root.subtext0
                    font.family: root.ui; font.pixelSize: root.s(11)
                    wrapMode: Text.WordWrap
                    Layout.fillWidth: true
                }
            }

            Item { Layout.fillHeight: true }

            // ---------------- start / stop ----------------
            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: root.s(52)
                radius: root.s(16)
                readonly property color c: root.running ? root.red : root.green
                color: Qt.alpha(c, goMa.containsMouse ? 0.32 : 0.2)
                border.width: 1
                border.color: Qt.alpha(c, 0.55)
                opacity: !root.running && root.intervalSec <= 0 ? 0.4 : 1
                Behavior on color { ColorAnimation { duration: 140 } }
                Text {
                    anchors.centerIn: parent
                    text: (root.running ? root.g(0xF04DB) + "  Stop" : root.g(0xF040A) + "  Start") + "   (F6)"
                    color: parent.c
                    font.family: root.icons; font.pixelSize: root.s(15); font.weight: Font.Bold
                }
                MouseArea {
                    id: goMa
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.toggleClicking()
                }
            }
        }
    }
}
