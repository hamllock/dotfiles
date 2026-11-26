import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import QtQuick.Window
import Quickshell
import Quickshell.Io
import "../"

// Claude Code sessions (top bar ✳ pill). Each running `claude` reports its state through
// hooks in ~/.claude/settings.json -> claude/claude_status.sh; this lists them.
// Click a session to jump to its terminal.
FocusScope {
    id: root

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
    readonly property color overlay0: _theme.overlay0
    readonly property string ui: "SF Pro Display"
    readonly property color claudeOrange: "#D97757"
    function tint(a) { return Qt.rgba(root.text.r, root.text.g, root.text.b, a); }

    readonly property var statusInfo: ({
        "waiting": { label: "Needs your permission", color: "#FFB340" },
        "done":    { label: "Done, your turn",       color: "#40C160" },
        "working": { label: "Working…",              color: "#E8956F" },
        "idle":    { label: "Idle",                  color: "#9a9aa2" }
    })
    // what needs you first: permission prompts, then finished, then working, then idle
    readonly property var order: ({ "waiting": 0, "done": 1, "working": 2, "idle": 3 })

    property var sessions: []
    property real now: Date.now() / 1000
    Timer { interval: 1000; running: true; repeat: true; onTriggered: root.now = Date.now() / 1000 }

    function ago(t) {
        let d = Math.max(0, Math.floor(root.now - t));
        if (d < 10) return "just now";
        if (d < 60) return d + "s ago";
        if (d < 3600) return Math.floor(d / 60) + "m ago";
        return Math.floor(d / 3600) + "h ago";
    }
    function shortPath(p) {
        let h = Quickshell.env("HOME");
        return p.indexOf(h) === 0 ? "~" + p.slice(h.length) : p;
    }

    readonly property string dirPath: Quickshell.env("XDG_RUNTIME_DIR") + "/claude-status"
    Process {
        id: reader
        command: ["bash", Quickshell.env("HOME") + "/.config/hypr/scripts/quickshell/claude/claude_list.sh"]
        stdout: StdioCollector {
            onStreamFinished: {
                let list; try { list = JSON.parse(this.text); } catch (e) { return; }
                list.sort((a, b) => (root.order[a.status] - root.order[b.status]) || (b.updated - a.updated));
                root.sessions = list;
            }
        }
    }
    Process {
        command: ["bash", "-c", "mkdir -p \"$1\"; inotifywait -qq -e create,modify,delete,moved_to \"$1\"", "_", root.dirPath]
        running: true
        onExited: { reader.running = true; running = true; }
    }
    Timer { interval: 3000; running: true; repeat: true; triggeredOnStart: true; onTriggered: reader.running = true }

    function jumpTo(sess) {
        if (sess.term_pid) Quickshell.execDetached(["hyprctl", "dispatch", "hl.dsp.focus({ window = \"pid:" + sess.term_pid + "\" })"]);
        Quickshell.execDetached(["bash", Quickshell.env("HOME") + "/.config/hypr/scripts/qs_manager.sh", "close"]);
    }

    // the state that needs you most decides the orb's colour and motion
    readonly property string topStatus: sessions.length ? sessions[0].status : "none"
    readonly property color orbColor: root.claudeOrange
    readonly property bool anyWorking: sessions.some(x => x.status === "working")

    // ---------------- intro (staged like the Volume popup) ----------------
    property real intro: 0
    property real introHeader: 0
    property real introList: 0
    ParallelAnimation {
        running: true
        NumberAnimation { target: root; property: "intro"; from: 0; to: 1; duration: 700; easing.type: Easing.OutExpo }
        SequentialAnimation {
            PauseAnimation { duration: 90 }
            NumberAnimation { target: root; property: "introHeader"; from: 0; to: 1; duration: 700; easing.type: Easing.OutBack; easing.overshoot: 1.2 }
        }
        SequentialAnimation {
            PauseAnimation { duration: 220 }
            NumberAnimation { target: root; property: "introList"; from: 0; to: 1; duration: 900; easing.type: Easing.OutCubic }
        }
    }

    Item {
        anchors.fill: parent
        opacity: root.intro
        scale: 0.95 + 0.05 * root.intro
        transform: Translate { y: root.s(20) * (1 - root.intro) }

        // liquid glass: radius matches qs-master corner_radius (config/hyprliquid.json)
        Rectangle {
            anchors.fill: parent
            radius: 48
            color: Qt.rgba(root.base.r, root.base.g, root.base.b, 0.06)
        }

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: root.s(34)
            spacing: root.s(20)

            // ---------------- orb (spins while Claude works) ----------------
            Item {
                Layout.alignment: Qt.AlignHCenter
                Layout.topMargin: root.s(6)
                Layout.bottomMargin: root.s(10)
                Layout.preferredWidth: root.s(84); Layout.preferredHeight: root.s(84)
                opacity: root.introHeader
                scale: 0.8 + 0.2 * root.introHeader

                PulseRings {
                    anchors.fill: parent
                    color: root.orbColor
                    running: root.topStatus === "waiting" || root.anyWorking
                    duration: root.topStatus === "waiting" ? 1300 : 3000
                    strength: root.topStatus === "waiting" ? 0.75 : 0.45
                    maxScale: 1.4
                }

                HeroOrb {
                    anchors.fill: parent
                    accent: root.orbColor
                    base: root.base
                    active: root.sessions.length > 0
                    hoverable: false

                    Text {
                        id: star
                        anchors.centerIn: parent
                        text: "✻"
                        color: Qt.lighter(root.claudeOrange, 1.08)
                        font.family: root.ui; font.weight: Font.Black; font.pixelSize: root.s(40)
                        // spins while Claude works, rests otherwise
                        property real speed: root.anyWorking ? 1 : 0
                        Behavior on speed { NumberAnimation { duration: 900; easing.type: Easing.InOutSine } }
                        NumberAnimation on rotation {
                            running: star.speed > 0
                            from: 0; to: 360; duration: 2600; loops: Animation.Infinite
                        }
                        // pops when a session asks for permission
                        SequentialAnimation on scale {
                            running: root.topStatus === "waiting"
                            loops: Animation.Infinite
                            NumberAnimation { to: 1.18; duration: 260; easing.type: Easing.OutBack }
                            NumberAnimation { to: 1.0; duration: 420; easing.type: Easing.OutCubic }
                            PauseAnimation { duration: 600 }
                        }
                    }
                }
            }

            // sessions
            ListView {
                id: list
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true
                spacing: root.s(6)
                model: root.sessions
                boundsBehavior: Flickable.StopAtBounds
                ScrollBar.vertical: ScrollBar {
                    width: root.s(5); policy: ScrollBar.AsNeeded
                    contentItem: Rectangle { implicitWidth: root.s(5); radius: width / 2; color: root.tint(0.3) }
                    background: Item {}
                }

                Text {
                    anchors.centerIn: parent
                    visible: root.sessions.length === 0
                    width: parent.width - root.s(40)
                    horizontalAlignment: Text.AlignHCenter
                    wrapMode: Text.WordWrap
                    text: "Start claude in a terminal and it shows up here."
                    color: root.overlay0
                    font.family: root.ui; font.pixelSize: root.s(13)
                }

                delegate: Rectangle {
                    id: card
                    readonly property var info: root.statusInfo[modelData.status] || root.statusInfo.idle
                    width: list.width
                    height: col.implicitHeight + root.s(26)
                    radius: root.s(18)
                    readonly property real enter: Math.max(0, Math.min(1, root.introList * 2.2 - Math.min(index, 14) * 0.1))
                    opacity: enter
                    transform: Translate { x: root.s(24) * (1 - card.enter) }
                    scale: cardMa.containsMouse ? 1.015 : 1.0
                    Behavior on scale { NumberAnimation { duration: 300; easing.type: Easing.OutBack } }
                    color: cardMa.containsMouse ? Qt.alpha(root.claudeOrange, 0.12) : Qt.rgba(root.base.r, root.base.g, root.base.b, 0.55)
                    border.width: 1
                    border.color: modelData.status === "waiting" ? Qt.alpha(card.info.color, 0.55)
                                : cardMa.containsMouse ? Qt.alpha(root.claudeOrange, 0.45) : root.tint(0.07)
                    Behavior on border.color { ColorAnimation { duration: 150 } }
                    Behavior on color { ColorAnimation { duration: 120 } }

                    PulseRings {
                        x: dot.x; y: dot.y
                        width: dot.width; height: dot.height
                        color: card.info.color
                        running: modelData.status === "waiting"
                        rings: 2; maxScale: 2.8; duration: 1400; strength: 0.8
                    }

                    // status dot (pulses while it needs you, breathes while working)
                    Rectangle {
                        id: dot
                        x: root.s(16); y: root.s(19)
                        width: root.s(10); height: width; radius: width / 2
                        color: card.info.color
                        SequentialAnimation on opacity {
                            running: modelData.status === "waiting" || modelData.status === "working"
                            loops: Animation.Infinite
                            NumberAnimation { to: 0.25; duration: modelData.status === "waiting" ? 500 : 900 }
                            NumberAnimation { to: 1.0; duration: modelData.status === "waiting" ? 500 : 900 }
                        }
                    }

                    Column {
                        id: col
                        x: root.s(38); y: root.s(13)
                        width: parent.width - root.s(54)
                        spacing: root.s(3)
                        RowLayout {
                            width: parent.width
                            Text {
                                Layout.fillWidth: true
                                elide: Text.ElideRight
                                text: modelData.project
                                color: root.text
                                font.family: root.ui; font.weight: Font.DemiBold; font.pixelSize: root.s(15)
                            }
                            Text {
                                text: root.ago(modelData.updated)
                                color: root.overlay0
                                font.family: root.ui; font.pixelSize: root.s(11)
                            }
                        }
                        Text {
                            text: card.info.label
                            color: card.info.color
                            font.family: root.ui; font.weight: Font.Medium; font.pixelSize: root.s(12)
                        }
                        Text {
                            visible: modelData.message !== ""
                            width: parent.width
                            wrapMode: Text.Wrap
                            maximumLineCount: 2
                            elide: Text.ElideRight
                            text: modelData.message
                            color: root.subtext0
                            font.family: root.ui; font.pixelSize: root.s(12)
                        }
                        Text {
                            width: parent.width
                            elide: Text.ElideMiddle
                            text: root.shortPath(modelData.cwd)
                            color: root.overlay0
                            font.family: root.ui; font.pixelSize: root.s(11)
                        }
                    }

                    MouseArea {
                        id: cardMa
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.jumpTo(modelData)
                    }
                }
            }
        }
    }
}
