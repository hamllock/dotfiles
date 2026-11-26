//@ pragma UseQApplication
import QtQuick
import QtQuick.Window
import QtQuick.Effects
import QtMultimedia
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Widgets
import Quickshell.Services.Pam

// macOS-style lock screen.
//   idle:   wallpaper, date + big clock at the top, avatar + name at the bottom
//   active: click the avatar (or start typing) -> the avatar glides to the centre,
//           the wallpaper blurs and a password pill appears. Esc goes back.
// The old lock screen is still in Lock.qml.
//
// Safe preview (does NOT lock the session; closes itself after 8 s):
//   MACLOCK_TEST=1 quickshell -p ~/.config/hypr/scripts/quickshell/MacLock.qml
//   MACLOCK_TEST=1 MACLOCK_TEST_ACTIVE=1 ...   (start in the login state)
ShellRoot {
    id: root

    readonly property bool testMode: Quickshell.env("MACLOCK_TEST") === "1"
    readonly property bool testActive: Quickshell.env("MACLOCK_TEST_ACTIVE") === "1"

    readonly property string home: Quickshell.env("HOME")
    readonly property string wallpaper: "file://" + home + "/.cache/quickshell/wallpaper_picker/current_wallpaper.png"
    // set by scripts/wallpaper/on_apply.sh when the wallpaper is a video; "" otherwise
    property string wallpaperVideo: ""
    Process {
        running: true
        command: ["bash", "-c", "f=\"$HOME/.cache/quickshell/wallpaper_picker/current_wallpaper.mp4\"; [ -e \"$f\" ] && readlink -f \"$f\""]
        stdout: StdioCollector {
            onStreamFinished: { let p = this.text.trim(); if (p !== "") root.wallpaperVideo = "file://" + p; }
        }
    }

    // shared auth state (all monitors)
    property bool failed: false
    property bool authenticating: false
    property string userName: Quickshell.env("USER")
    property string avatarPath: ""

    // avatar: GitHub avatar from the dash cache, else ~/.face(.icon)
    Process {
        running: true
        command: ["bash", "-c",
            "for f in \"$HOME/.cache/quickshell/dash/avatar.png\" \"$HOME/.face.icon\" \"$HOME/.face\"; do " +
            "  [ -s \"$f\" ] && { readlink -f \"$f\"; break; }; done; " +
            "echo \"NAME:$USER\""]   // show the username, not the full name
        stdout: StdioCollector {
            onStreamFinished: {
                let lines = this.text.trim().split("\n");
                for (let l of lines) {
                    if (l.startsWith("NAME:")) root.userName = l.slice(5);
                    else if (l !== "") root.avatarPath = "file://" + l;
                }
            }
        }
    }

    // ---------------- PAM ----------------
    Timer { id: pamStart; interval: 50; onTriggered: pam.start() }

    PamContext {
        id: pam
        Component.onCompleted: pamStart.start()
        onCompleted: (result) => {
            root.authenticating = false;
            if (result === PamResult.Success) {
                lock.locked = false;
                Qt.quit();
            } else {
                root.failed = true;
                pamStart.start();
            }
        }
    }

    function submit(pw) {
        if (pw.length === 0 || root.authenticating || !pam.responseRequired) return false;
        root.authenticating = true;
        root.failed = false;
        pam.respond(pw);
        return true;
    }

    // ---------------- surfaces ----------------
    WlSessionLock {
        id: lock
        locked: !root.testMode
        WlSessionLockSurface {
            color: "black"
            LockView { anchors.fill: parent }
        }
    }

    // preview window (MACLOCK_TEST=1): overlay layer instead of a real lock
    Loader {
        active: root.testMode
        sourceComponent: PanelWindow {
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.namespace: "maclock-test"
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
            exclusionMode: ExclusionMode.Ignore
            anchors { top: true; bottom: true; left: true; right: true }
            color: "black"
            LockView { anchors.fill: parent }
        }
    }
    Timer { running: root.testMode; interval: 8000; onTriggered: Qt.quit() }

    // ======================================================================
    component LockView: Item {
        id: view

        readonly property real sc: Math.max(0.6, Math.min(width / 1920, height / 1080))
        function s(v) { return Math.round(v * sc); }

        // 0 = idle (avatar at the bottom), 1 = login (avatar centred)
        property bool active: root.testActive
        property real t: active ? 1 : 0
        Behavior on t { NumberAnimation { duration: 650; easing.type: Easing.OutQuint } }
        function lerp(a, b) { return a + (b - a) * view.t; }

        property real intro: 0
        NumberAnimation on intro { from: 0; to: 1; duration: 900; easing.type: Easing.OutCubic; running: true }

        property var now: new Date()
        Timer { interval: 1000; running: true; repeat: true; onTriggered: view.now = new Date() }

        function activate() {
            view.active = true;
            idle.restart();
            pw.forceActiveFocus();
        }
        function deactivate() {
            view.active = false;
            pw.text = "";
            root.failed = false;
        }

        // back to idle after 30 s of nothing
        Timer { id: idle; interval: 30000; onTriggered: if (!root.authenticating) view.deactivate() }

        // ---------------- wallpaper ----------------
        // still frame shows instantly; the video (if any) fades in over it once it plays.
        // The wallpaper is drawn directly while idle and only goes through MultiEffect while
        // the login is open: a hidden-source MultiEffect doesn't repaint on new video frames
        // (video dropped to ~0.5 fps), and an always-on effect re-renders at 60 fps.
        Item {
            id: wall
            anchors.fill: parent
            opacity: view.intro
            layer.enabled: view.t > 0.001
            layer.effect: MultiEffect {
                autoPaddingEnabled: false
                blurEnabled: true
                blurMax: 64
                blur: 0.75 * view.t
                brightness: -0.1 * view.t
                saturation: 0.1 * view.t
            }
            Image {
                anchors.fill: parent
                source: root.wallpaper
                fillMode: Image.PreserveAspectCrop
                asynchronous: true
                cache: false
            }
            Video {
                id: wallVideo
                anchors.fill: parent
                source: root.wallpaperVideo
                fillMode: VideoOutput.PreserveAspectCrop
                loops: MediaPlayer.Infinite
                muted: true
                autoPlay: root.wallpaperVideo !== ""
                opacity: playbackState === MediaPlayer.PlayingState ? 1 : 0
                Behavior on opacity { NumberAnimation { duration: 400 } }
            }
        }
        // base dim (was brightness -0.05 on the effect)
        Rectangle { anchors.fill: parent; color: "black"; opacity: 0.05 }
        // gentle vignette so the white text always reads
        Rectangle {
            anchors.fill: parent
            gradient: Gradient {
                GradientStop { position: 0.0; color: Qt.rgba(0, 0, 0, 0.30) }
                GradientStop { position: 0.35; color: Qt.rgba(0, 0, 0, 0.0) }
                GradientStop { position: 0.7; color: Qt.rgba(0, 0, 0, 0.0) }
                GradientStop { position: 1.0; color: Qt.rgba(0, 0, 0, 0.35) }
            }
        }

        MouseArea {
            anchors.fill: parent
            onClicked: { if (view.active) { idle.restart(); pw.forceActiveFocus(); } }
        }

        // ---------------- clock (top) ----------------
        Column {
            anchors.horizontalCenter: parent.horizontalCenter
            y: view.s(70) - view.s(30) * (1 - view.intro) - view.s(24) * view.t
            opacity: view.intro * (1 - view.t)   // fades out when the login opens
            visible: opacity > 0.01
            scale: view.lerp(1, 0.94)
            spacing: view.s(-6)

            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: view.now.toLocaleDateString(Qt.locale("en_US"), "dddd, MMMM d")
                color: Qt.rgba(1, 1, 1, 0.88)
                font.family: "SF Pro Display"; font.styleName: "Bold"
                font.pixelSize: view.s(26)
            }
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: Qt.formatTime(view.now, "h:mm")
                color: Qt.rgba(1, 1, 1, 0.92)
                font.family: "SF Pro Rounded"; font.styleName: "Black"
                font.pixelSize: view.s(132)
                font.letterSpacing: view.s(-2)
            }
        }

        // ---------------- avatar + name (bottom -> centre) ----------------
        Item {
            id: user
            readonly property real size: view.lerp(view.s(68), view.s(170))
            width: size; height: size
            x: (view.width - size) / 2
            y: view.lerp(view.height - view.s(170), view.height / 2 - view.s(150)) + view.s(40) * (1 - view.intro)
            opacity: view.intro

            ClippingRectangle {
                anchors.fill: parent
                radius: width / 2
                color: Qt.rgba(1, 1, 1, 0.15)
                Image {
                    anchors.fill: parent
                    source: root.avatarPath
                    fillMode: Image.PreserveAspectCrop
                    sourceSize.width: 256; sourceSize.height: 256
                    smooth: true; mipmap: true
                    visible: root.avatarPath !== ""
                }
                Text {
                    anchors.centerIn: parent
                    visible: root.avatarPath === ""
                    text: root.userName.charAt(0).toUpperCase()
                    color: "white"
                    font.family: "SF Pro Rounded"; font.styleName: "Semibold"
                    font.pixelSize: parent.height * 0.45
                }
            }
            Rectangle {   // ring: brightens on hover, red on failure
                anchors.fill: parent
                anchors.margins: -view.s(3)
                radius: width / 2
                color: "transparent"
                border.width: Math.max(1, view.s(2))
                border.color: root.failed ? Qt.rgba(1, 0.27, 0.23, 0.9) : "transparent"   // ring only on a wrong password
                Behavior on border.color { ColorAnimation { duration: 200 } }
            }
            scale: avatarMa.containsMouse && !view.active ? 1.06 : 1.0
            Behavior on scale { NumberAnimation { duration: 220; easing.type: Easing.OutBack } }

            MouseArea {
                id: avatarMa
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: view.activate()
            }
        }

        Text {
            id: nameLabel
            anchors.horizontalCenter: parent.horizontalCenter
            y: user.y + user.height + view.s(14)
            text: root.userName
            color: "white"
            opacity: view.intro
            font.family: "SF Pro Display"; font.styleName: "Bold"
            font.pixelSize: view.lerp(view.s(17), view.s(22))
        }

        // idle hint under the name
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            y: nameLabel.y + nameLabel.height + view.s(6)
            text: "Click or start typing to unlock"
            color: Qt.rgba(1, 1, 1, 0.6)
            font.family: "SF Pro Display"; font.styleName: "Regular"; font.pixelSize: view.s(13)
            opacity: view.intro * (1 - view.t * 3)
            visible: opacity > 0
        }

        // ---------------- password pill ----------------
        Item {
            id: pill
            width: view.s(260)
            height: view.s(38)
            anchors.horizontalCenter: parent.horizontalCenter
            y: nameLabel.y + nameLabel.height + view.s(18) + view.s(12) * (1 - view.t)
            opacity: Math.max(0, view.t * 2 - 1)
            visible: opacity > 0.01
            transform: Translate { id: shake; x: 0 }

            SequentialAnimation {
                id: shakeAnim
                NumberAnimation { target: shake; property: "x"; to: -view.s(12); duration: 50 }
                NumberAnimation { target: shake; property: "x"; to: view.s(12); duration: 70 }
                NumberAnimation { target: shake; property: "x"; to: -view.s(8); duration: 70 }
                NumberAnimation { target: shake; property: "x"; to: view.s(6); duration: 60 }
                NumberAnimation { target: shake; property: "x"; to: 0; duration: 50 }
            }
            Connections {
                target: root
                function onFailedChanged() { if (root.failed) { shakeAnim.restart(); pw.text = ""; } }
            }

            Rectangle {
                anchors.fill: parent
                radius: height / 2
                color: Qt.rgba(1, 1, 1, pw.activeFocus ? 0.22 : 0.16)
                border.width: 1
                border.color: Qt.rgba(1, 1, 1, 0.22)
                Behavior on color { ColorAnimation { duration: 150 } }
            }

            TextInput {
                id: pw
                anchors.fill: parent
                anchors.leftMargin: view.s(18)
                anchors.rightMargin: view.s(42)
                verticalAlignment: TextInput.AlignVCenter
                echoMode: TextInput.Password
                passwordCharacter: "●"
                color: "white"
                font.family: "SF Pro Display"; font.styleName: "Regular"; font.pixelSize: view.s(15)
                font.letterSpacing: view.s(2)
                selectionColor: Qt.rgba(1, 1, 1, 0.3)
                enabled: !root.authenticating
                focus: true
                clip: true

                Component.onCompleted: forceActiveFocus()

                // any key while idle switches to the login state (the key still types)
                Keys.onPressed: (e) => {
                    if (e.key === Qt.Key_Escape) { view.deactivate(); e.accepted = true; return; }
                    if (!view.active) view.activate();
                    idle.restart();
                }
                onTextChanged: if (text.length > 0) root.failed = false
                onAccepted: if (root.submit(text)) text = ""

                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    visible: pw.text.length === 0
                    text: root.failed ? "Incorrect password" : root.authenticating ? "Checking…" : "Enter Password"
                    color: root.failed ? Qt.rgba(1, 0.75, 0.73, 0.95) : Qt.rgba(1, 1, 1, 0.6)
                    font.family: "SF Pro Display"; font.styleName: "Regular"; font.pixelSize: view.s(14)
                    font.letterSpacing: 0
                }
            }

            // submit arrow / spinner
            Rectangle {
                anchors.right: parent.right
                anchors.rightMargin: view.s(5)
                anchors.verticalCenter: parent.verticalCenter
                width: view.s(28); height: width; radius: width / 2
                color: Qt.rgba(1, 1, 1, pw.text.length > 0 ? 0.3 : 0.12)
                Behavior on color { ColorAnimation { duration: 150 } }

                Text {
                    anchors.centerIn: parent
                    visible: !root.authenticating
                    text: "→"
                    color: "white"
                    opacity: pw.text.length > 0 ? 1 : 0.5
                    font.family: "SF Pro Display"; font.styleName: "Bold"
                    font.pixelSize: view.s(15)
                }
                Rectangle {   // spinner arc
                    anchors.centerIn: parent
                    visible: root.authenticating
                    width: view.s(14); height: width; radius: width / 2
                    color: "transparent"
                    border.width: view.s(2)
                    border.color: Qt.rgba(1, 1, 1, 0.35)
                    Rectangle {
                        width: view.s(4); height: width; radius: width / 2
                        color: "white"
                        x: parent.width / 2 - width / 2; y: -width / 4
                    }
                    RotationAnimation on rotation { running: root.authenticating; from: 0; to: 360; duration: 800; loops: Animation.Infinite }
                }
                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: if (root.submit(pw.text)) pw.text = ""
                }
            }
        }

        // Esc hint / cancel under the pill
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            y: pill.y + pill.height + view.s(16)
            text: "Cancel"
            color: cancelMa.containsMouse ? "white" : Qt.rgba(1, 1, 1, 0.6)
            font.family: "SF Pro Display"; font.styleName: "Regular"; font.pixelSize: view.s(13)
            opacity: pill.opacity
            visible: opacity > 0.01
            MouseArea {
                id: cancelMa
                anchors.fill: parent; anchors.margins: -view.s(8)
                hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                onClicked: view.deactivate()
            }
        }
    }
}
