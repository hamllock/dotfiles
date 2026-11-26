import QtQuick
import QtQuick.Layouts
import QtQuick.Window
import Quickshell
import Quickshell.Io
import Quickshell.Widgets
import "../"

// Power menu (power button in the top bar). A labelled list:
//   Lock, Sleep          -> one click
//   Log out, Restart, Shut down -> click to arm (row turns red, 3 s countdown), click again
// Keyboard: Up/Down + Enter; Esc closes.
FocusScope {
    id: root
    focus: true

    property var notifModel
    property var liveNotifs
    property real layoutWidth
    property real layoutHeight

    Caching { id: paths }
    Scaler { id: scaler; currentWidth: Screen.width; currentHeight: Screen.height }
    function s(v) { return scaler.s(v); }

    MatugenColors { id: _theme }
    readonly property color base: _theme.base
    readonly property color text: _theme.text
    readonly property color subtext0: _theme.subtext0
    readonly property color overlay0: _theme.overlay0
    readonly property color red: _theme.red
    readonly property color green: _theme.green
    readonly property string ui: "SF Pro Display"
    readonly property string icons: "Iosevka Nerd Font"
    function tint(a) { return Qt.rgba(root.text.r, root.text.g, root.text.b, a); }
    function g(cp) { return String.fromCodePoint(cp); }

    readonly property var actions: [
        { label: "Lock",      icon: 0xF033E, confirm: false, cmd: "bash ~/.config/hypr/scripts/lock.sh" },
        { label: "Sleep",     icon: 0xF04B2, confirm: false, cmd: "bash ~/.config/hypr/scripts/lock.sh & sleep 1; systemctl suspend" },
        { label: "Log out",   icon: 0xF0343, confirm: true,  cmd: "bash ~/.config/hypr/scripts/exit.sh", verb: "log out" },
        { label: "Restart",   icon: 0xF0709, confirm: true,  cmd: "systemctl reboot", verb: "restart" },
        { label: "Shut down", icon: 0xF0425, confirm: true,  cmd: "systemctl poweroff", verb: "shut down" }
    ]

    // ---------------- state ----------------
    property int selected: -1          // keyboard highlight
    property int armed: -1             // row waiting for its confirming click
    property real armLeft: 1           // 1 -> 0 over the arm window
    property bool leaving: false

    function trigger(i) {
        if (root.leaving) return;
        let a = root.actions[i];
        if (a.confirm && root.armed !== i) {
            root.armed = i;
            armAnim.restart();
            return;
        }
        root.leaving = true;
        armAnim.stop();
        // close the panel first so the lock screen / session end isn't covered by it
        Quickshell.execDetached(["bash", Quickshell.env("HOME") + "/.config/hypr/scripts/qs_manager.sh", "close"]);
        runTimer.cmd = a.cmd;
        runTimer.start();
    }
    Timer { id: runTimer; property string cmd: ""; interval: 220; onTriggered: Quickshell.execDetached(["sh", "-c", cmd]) }
    NumberAnimation {
        id: armAnim
        target: root; property: "armLeft"; from: 1; to: 0; duration: 3000
        onFinished: root.armed = -1
    }

    Keys.onPressed: (e) => {
        if (e.key === Qt.Key_Down || e.key === Qt.Key_Tab) { root.selected = (root.selected + 1) % root.actions.length; e.accepted = true; }
        else if (e.key === Qt.Key_Up || e.key === Qt.Key_Backtab) { root.selected = (root.selected + root.actions.length - 1) % root.actions.length; e.accepted = true; }
        else if ((e.key === Qt.Key_Return || e.key === Qt.Key_Enter) && root.selected >= 0) { root.trigger(root.selected); e.accepted = true; }
    }

    // ---------------- info: user, uptime, battery ----------------
    property string userName: Quickshell.env("USER")
    property string avatar: ""
    property string uptime: ""
    property int battery: -1
    property string batStatus: ""

    Process {
        running: true
        command: ["bash", "-c",
            "n=$(getent passwd \"$USER\" | cut -d: -f5 | cut -d, -f1); echo \"${n:-$USER}\"; " +
            "for f in \"$HOME/.cache/quickshell/dash/avatar.png\" \"$HOME/.face.icon\" \"$HOME/.face\"; do [ -s \"$f\" ] && { echo \"$f\"; break; }; done"]
        stdout: StdioCollector {
            onStreamFinished: {
                let l = this.text.trim().split("\n");
                if (l[0]) root.userName = l[0];
                if (l[1]) root.avatar = "file://" + l[1];
            }
        }
    }
    Process {
        id: sysProc
        command: ["bash", "-c",
            "awk '{d=int($1/86400); h=int(($1%86400)/3600); m=int(($1%3600)/60); " +
            "if (d>0) printf \"%dd %dh\", d, h; else if (h>0) printf \"%dh %dm\", h, m; else printf \"%dm\", m}' /proc/uptime; echo; " +
            "cat /sys/class/power_supply/BAT*/capacity 2>/dev/null | head -n1; cat /sys/class/power_supply/BAT*/status 2>/dev/null | head -n1"]
        stdout: StdioCollector {
            onStreamFinished: {
                let l = this.text.trim().split("\n");
                root.uptime = l[0] || "";
                root.battery = l[1] ? parseInt(l[1]) : -1;
                root.batStatus = l[2] || "";
            }
        }
    }
    Timer { interval: 30000; running: true; repeat: true; triggeredOnStart: true; onTriggered: sysProc.running = true }

    // ---------------- intro ----------------
    property real intro: 0
    NumberAnimation on intro { from: 0; to: 1; duration: 550; easing.type: Easing.OutQuart; running: true }

    Item {
        anchors.fill: parent
        opacity: root.intro
        scale: 0.94 + 0.06 * root.intro
        transform: Translate { y: root.s(14) * (1 - root.intro) }

        // liquid glass: radius matches qs-master corner_radius (config/hyprliquid.json)
        Rectangle {
            anchors.fill: parent
            radius: 48
            color: Qt.rgba(root.base.r, root.base.g, root.base.b, 0.06)
        }

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: root.s(22)
            anchors.topMargin: root.s(24)
            spacing: root.s(14)

            // ---------------- header ----------------
            RowLayout {
                Layout.fillWidth: true
                Layout.leftMargin: root.s(4)
                spacing: root.s(14)
                Item {
                    Layout.preferredWidth: root.s(46); Layout.preferredHeight: root.s(46)
                    Rectangle {
                        anchors.fill: parent; anchors.margins: -root.s(2)
                        radius: width / 2; color: "transparent"
                        border.width: root.s(1.5); border.color: root.tint(0.2)
                    }
                    ClippingRectangle {
                        anchors.fill: parent
                        radius: width / 2
                        color: root.tint(0.1)
                        Image {
                            anchors.fill: parent
                            source: root.avatar
                            fillMode: Image.PreserveAspectCrop
                            sourceSize.width: 128; sourceSize.height: 128
                            smooth: true; mipmap: true
                            visible: root.avatar !== ""
                        }
                        Text {
                            anchors.centerIn: parent
                            visible: root.avatar === ""
                            text: root.userName.charAt(0).toUpperCase()
                            color: root.text
                            font.family: root.ui; font.weight: Font.Bold; font.pixelSize: root.s(20)
                        }
                    }
                }
                Column {
                    Layout.fillWidth: true
                    spacing: root.s(2)
                    Text {
                        width: parent.width; elide: Text.ElideRight
                        text: root.userName
                        color: root.text
                        font.family: root.ui; font.weight: Font.Bold; font.pixelSize: root.s(17)
                    }
                    Row {
                        spacing: root.s(12)
                        Text {
                            visible: root.uptime !== ""
                            text: root.g(0xF0954) + "  up " + root.uptime
                            color: root.subtext0
                            font.family: root.ui; font.pixelSize: root.s(12)
                        }
                        Text {
                            visible: root.battery >= 0
                            text: (root.batStatus === "Charging" ? root.g(0xF0084) : root.g(0xF0079)) + " " + root.battery + "%"
                            color: root.battery <= 15 && root.batStatus !== "Charging" ? root.red : root.subtext0
                            font.family: root.ui; font.pixelSize: root.s(12)
                        }
                    }
                }
            }

            // ---------------- actions ----------------
            Column {
                Layout.fillWidth: true
                Layout.fillHeight: true
                spacing: root.s(4)

                Repeater {
                    model: root.actions
                    Rectangle {
                        id: row
                        readonly property bool isArmed: root.armed === index
                        readonly property bool isSel: root.selected === index
                        readonly property bool danger: modelData.confirm
                        // stagger the rows in
                        readonly property real p: Math.max(0, Math.min(1, root.intro * 2.2 - index * 0.18))
                        width: parent.width
                        height: root.s(50)
                        radius: root.s(16)
                        clip: true
                        opacity: p
                        transform: Translate { x: root.s(16) * (1 - row.p) }
                        color: isArmed ? Qt.alpha(root.red, 0.16)
                             : (ma.containsMouse || isSel) ? root.tint(0.08) : "transparent"
                        border.width: isArmed ? 1 : 0
                        border.color: Qt.alpha(root.red, 0.5)
                        Behavior on color { ColorAnimation { duration: 140 } }

                        // countdown bar while armed
                        Rectangle {
                            visible: row.isArmed
                            anchors.left: parent.left
                            anchors.bottom: parent.bottom
                            height: root.s(3)
                            width: parent.width * root.armLeft
                            color: root.red
                            opacity: 0.8
                        }

                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: root.s(10)
                            anchors.rightMargin: root.s(16)
                            spacing: root.s(14)
                            Rectangle {
                                Layout.preferredWidth: root.s(34); Layout.preferredHeight: root.s(34)
                                radius: root.s(11)
                                color: row.isArmed ? root.red
                                     : (ma.containsMouse || row.isSel) ? (row.danger ? Qt.alpha(root.red, 0.18) : root.tint(0.16))
                                     : root.tint(0.07)
                                Behavior on color { ColorAnimation { duration: 140 } }
                                Text {
                                    anchors.centerIn: parent
                                    text: root.g(modelData.icon)
                                    color: row.isArmed ? root.base : (row.danger && (ma.containsMouse || row.isSel)) ? root.red : root.text
                                    font.family: root.icons; font.pixelSize: root.s(17)
                                }
                            }
                            Text {
                                Layout.fillWidth: true
                                elide: Text.ElideRight
                                text: row.isArmed ? "Click again to " + modelData.verb : modelData.label
                                color: row.isArmed ? root.red : root.text
                                font.family: root.ui
                                font.weight: row.isArmed ? Font.DemiBold : Font.Medium
                                font.pixelSize: root.s(14)
                            }
                            Text {
                                visible: row.isArmed
                                text: Math.ceil(root.armLeft * 3) + "s"
                                color: root.red
                                font.family: root.ui; font.pixelSize: root.s(12)
                            }
                        }

                        MouseArea {
                            id: ma
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onEntered: root.selected = index
                            onClicked: root.trigger(index)
                        }
                    }
                }
            }
        }
    }
}
