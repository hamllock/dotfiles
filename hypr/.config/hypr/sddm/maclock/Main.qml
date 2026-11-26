import QtQuick
import QtQuick.Effects
import QtMultimedia

// SDDM login screen styled like MacLock (scripts/quickshell/MacLock.qml).
// Preview without logging out:
//   sddm-greeter-qt6 --test-mode --theme ~/.config/hypr/sddm/maclock
Rectangle {
    id: view
    color: "black"
    width: 1920; height: 1200

    readonly property real sc: Math.max(0.6, Math.min(width / 1920, height / 1080))
    function s(v) { return Math.round(v * sc); }

    readonly property string userName: config.userName !== "" ? config.userName : userModel.lastUser
    readonly property string displayName: config.displayName !== "" ? config.displayName : userName

    property bool failed: false
    property bool authenticating: false

    // 0 = idle (avatar at the bottom), 1 = login (avatar centred)
    property bool active: false
    property real t: active ? 1 : 0
    Behavior on t { NumberAnimation { duration: 650; easing.type: Easing.OutQuint } }
    function lerp(a, b) { return a + (b - a) * view.t; }

    property real intro: 0
    NumberAnimation on intro { from: 0; to: 1; duration: 900; easing.type: Easing.OutCubic; running: true }

    property var now: new Date()
    Timer { interval: 1000; running: true; repeat: true; onTriggered: view.now = new Date() }

    FontLoader { id: fDisplay; source: "fonts/SF-Pro-Display-Regular.otf" }
    FontLoader { id: fRoundBlack; source: "fonts/SF-Pro-Rounded-Black.otf" }
    FontLoader { id: fRoundSemi; source: "fonts/SF-Pro-Rounded-Semibold.otf" }
    FontLoader { source: "fonts/SF-Pro-Display-Bold.otf" }   // style "Bold" (same file MacLock gets)
    readonly property string display: fDisplay.name
    readonly property string rounded: fRoundBlack.name

    function activate() { view.active = true; idle.restart(); pw.forceActiveFocus(); }
    function deactivate() { view.active = false; pw.text = ""; view.failed = false; }
    function submit() {
        if (pw.text.length === 0 || view.authenticating) return;
        view.authenticating = true;
        view.failed = false;
        sddm.login(view.userName, pw.text, sessionModel.lastIndex);
    }

    Connections {
        target: sddm
        function onLoginFailed() {
            view.authenticating = false;
            view.failed = true;
            pw.text = "";
            shakeAnim.restart();
            pw.forceActiveFocus();
        }
        function onLoginSucceeded() { view.authenticating = false; }
    }

    Timer { id: idle; interval: 30000; onTriggered: if (!view.authenticating) view.deactivate() }

    // ---------------- wallpaper ----------------
    // still frame shows instantly; assets/wallpaper.mp4 (copied by sync.sh when the
    // wallpaper is a video) fades in over it once it plays. Missing file = image only.
    // Drawn directly while idle; only goes through MultiEffect while the login is open
    // (a hidden-source MultiEffect doesn't repaint on new video frames -> choppy video).
    Item {
        id: wall
        anchors.fill: parent
        opacity: view.intro
        layer.enabled: view.t > 0.001
        layer.effect: MultiEffect {
            autoPaddingEnabled: false   // otherwise the wallpaper renders ~2x zoomed
            blurEnabled: true
            blurMax: 64
            blur: 0.75 * view.t
            brightness: -0.1 * view.t
            saturation: 0.1 * view.t
        }
        Image {
            anchors.fill: parent
            source: "assets/wallpaper.png"
            fillMode: Image.PreserveAspectCrop
            asynchronous: true
            cache: false
        }
        Video {
            anchors.fill: parent
            source: Qt.resolvedUrl("assets/wallpaper.mp4")
            fillMode: VideoOutput.PreserveAspectCrop
            loops: MediaPlayer.Infinite
            muted: true
            autoPlay: true
            opacity: playbackState === MediaPlayer.PlayingState ? 1 : 0
            Behavior on opacity { NumberAnimation { duration: 400 } }
        }
    }
    // base dim (was brightness -0.05 on the effect)
    Rectangle { anchors.fill: parent; color: "black"; opacity: 0.05 }
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

    // ---------------- clock ----------------
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
            font.family: view.display; font.styleName: "Bold"
            font.pixelSize: view.s(26)
        }
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: Qt.formatTime(view.now, "h:mm")
            color: Qt.rgba(1, 1, 1, 0.92)
            font.family: view.rounded; font.styleName: "Black"
            font.pixelSize: view.s(132)
            font.letterSpacing: view.s(-2)
        }
    }

    // ---------------- avatar + name ----------------
    Item {
        id: user
        readonly property real size: view.lerp(view.s(68), view.s(170))
        width: size; height: size
        x: (view.width - size) / 2
        y: view.lerp(view.height - view.s(170), view.height / 2 - view.s(150)) + view.s(40) * (1 - view.intro)
        opacity: view.intro

        Rectangle {
            anchors.fill: parent
            radius: width / 2
            color: Qt.rgba(1, 1, 1, 0.15)
        }
        Image {
            id: avatarImg
            anchors.fill: parent
            source: "assets/avatar.png"
            fillMode: Image.PreserveAspectCrop
            sourceSize.width: 256; sourceSize.height: 256
            smooth: true; mipmap: true
            visible: false
        }
        Rectangle {
            id: avatarMask
            anchors.fill: parent
            radius: width / 2
            visible: false
            layer.enabled: true
        }
        MultiEffect {
            anchors.fill: parent
            source: avatarImg
            maskEnabled: true
            maskSource: avatarMask
            maskThresholdMin: 0.5
            maskSpreadAtMin: 1.0
            visible: avatarImg.status === Image.Ready
        }
        Text {
            anchors.centerIn: parent
            visible: avatarImg.status !== Image.Ready
            text: view.displayName.charAt(0).toUpperCase()
            color: "white"
            font.family: view.rounded; font.styleName: "Semibold"
            font.pixelSize: parent.height * 0.45
        }
        Rectangle {
            anchors.fill: parent
            anchors.margins: -view.s(3)
            radius: width / 2
            color: "transparent"
            border.width: Math.max(1, view.s(2))
            border.color: view.failed ? Qt.rgba(1, 0.27, 0.23, 0.9) : "transparent"   // ring only on a wrong password
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
        text: view.displayName
        color: "white"
        opacity: view.intro
        font.family: view.display; font.styleName: "Bold"
        font.pixelSize: view.lerp(view.s(17), view.s(22))
    }

    Text {
        anchors.horizontalCenter: parent.horizontalCenter
        y: nameLabel.y + nameLabel.height + view.s(6)
        text: "Click or start typing to log in"
        color: Qt.rgba(1, 1, 1, 0.6)
        font.family: view.display; font.styleName: "Regular"; font.pixelSize: view.s(13)
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
            font.family: view.display; font.styleName: "Regular"; font.pixelSize: view.s(15)
            font.letterSpacing: view.s(2)
            selectionColor: Qt.rgba(1, 1, 1, 0.3)
            enabled: !view.authenticating
            focus: true
            clip: true

            Component.onCompleted: forceActiveFocus()

            Keys.onPressed: (e) => {
                if (e.key === Qt.Key_Escape) { view.deactivate(); e.accepted = true; return; }
                if (!view.active) view.activate();
                idle.restart();
            }
            onTextChanged: if (text.length > 0) view.failed = false
            onAccepted: view.submit()

            Text {
                anchors.verticalCenter: parent.verticalCenter
                visible: pw.text.length === 0
                text: view.failed ? "Incorrect password" : view.authenticating ? "Logging in…" : "Enter Password"
                color: view.failed ? Qt.rgba(1, 0.75, 0.73, 0.95) : Qt.rgba(1, 1, 1, 0.6)
                font.family: view.display; font.styleName: "Regular"; font.pixelSize: view.s(14)
                font.letterSpacing: 0
            }
        }

        Rectangle {
            anchors.right: parent.right
            anchors.rightMargin: view.s(5)
            anchors.verticalCenter: parent.verticalCenter
            width: view.s(28); height: width; radius: width / 2
            color: Qt.rgba(1, 1, 1, pw.text.length > 0 ? 0.3 : 0.12)
            Behavior on color { ColorAnimation { duration: 150 } }

            Text {
                anchors.centerIn: parent
                visible: !view.authenticating
                text: "→"
                color: "white"
                opacity: pw.text.length > 0 ? 1 : 0.5
                font.family: view.display; font.styleName: "Bold"
                font.pixelSize: view.s(15)
            }
            Rectangle {
                anchors.centerIn: parent
                visible: view.authenticating
                width: view.s(14); height: width; radius: width / 2
                color: "transparent"
                border.width: view.s(2)
                border.color: Qt.rgba(1, 1, 1, 0.35)
                Rectangle {
                    width: view.s(4); height: width; radius: width / 2
                    color: "white"
                    x: parent.width / 2 - width / 2; y: -width / 4
                }
                RotationAnimation on rotation { running: view.authenticating; from: 0; to: 360; duration: 800; loops: Animation.Infinite }
            }
            MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: view.submit()
            }
        }
    }

    Text {
        anchors.horizontalCenter: parent.horizontalCenter
        y: pill.y + pill.height + view.s(16)
        text: "Cancel"
        color: cancelMa.containsMouse ? "white" : Qt.rgba(1, 1, 1, 0.6)
        font.family: view.display; font.styleName: "Regular"; font.pixelSize: view.s(13)
        opacity: pill.opacity
        visible: opacity > 0.01
        MouseArea {
            id: cancelMa
            anchors.fill: parent; anchors.margins: -view.s(8)
            hoverEnabled: true; cursorShape: Qt.PointingHandCursor
            onClicked: view.deactivate()
        }
    }

    // ---------------- power buttons (small, top right) ----------------
    Row {
        anchors.top: parent.top
        anchors.right: parent.right
        anchors.margins: view.s(18)
        spacing: view.s(6)
        opacity: view.intro

        Repeater {
            model: [
                { label: "Sleep",     glyph: "☾", ok: sddm.canSuspend,  act: function() { sddm.suspend(); } },
                { label: "Restart",   glyph: "↻", ok: sddm.canReboot,   act: function() { sddm.reboot(); } },
                { label: "Shut Down", glyph: "⏻", ok: sddm.canPowerOff, act: function() { sddm.powerOff(); } }
            ]
            delegate: Rectangle {
                required property var modelData
                visible: modelData.ok
                width: view.s(26); height: width; radius: width / 2
                color: Qt.rgba(1, 1, 1, btnMa.containsMouse ? 0.22 : 0.0)
                Behavior on color { ColorAnimation { duration: 150 } }
                Text {
                    anchors.centerIn: parent
                    text: modelData.glyph
                    color: Qt.rgba(1, 1, 1, btnMa.containsMouse ? 1 : 0.6)
                    font.pixelSize: view.s(13)
                }
                MouseArea {
                    id: btnMa
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: modelData.act()
                }
            }
        }
    }
}
