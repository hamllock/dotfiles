import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import QtQuick.Window
import Quickshell
import Quickshell.Io
import "../"

// Bluetooth popup (SUPER+M / top bar Bluetooth pill): connected devices, your paired
// devices and nearby ones as a plain scrollable list. Scans while it's open.
// Backend: bluetooth/bt.sh (bluetoothctl, via bluetooth/bluetooth_panel_logic.sh).
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
    readonly property color surface0: _theme.surface0
    readonly property color green: _theme.green
    readonly property color red: _theme.red
    readonly property color accent: _theme.mauve
    readonly property string ui: "SF Pro Display"
    readonly property string icons: "Iosevka Nerd Font"
    function tint(a) { return Qt.rgba(root.text.r, root.text.g, root.text.b, a); }
    function g(cp) { return String.fromCodePoint(cp); }
    // device icon from the emoji bluetooth_panel_logic.sh guesses from the device type/name
    function deviceIcon(d) {
        let e = d.icon || "";
        if (e.indexOf("🎧") >= 0) return g(0xF02CB);      // headphones
        if (e.indexOf("🔊") >= 0) return g(0xF04C3);      // speaker
        if (e.indexOf("📱") >= 0) return g(0xF011C);      // phone
        if (e.indexOf("🖱") >= 0) return g(0xF037D);      // mouse
        if (e.indexOf("⌨") >= 0) return g(0xF030C);      // keyboard
        if (e.indexOf("🎮") >= 0) return g(0xF0297);      // gamepad
        return g(0xF00AF);                                 // bluetooth
    }

    readonly property var mainDev: connectedDevs.length === 1 ? connectedDevs[0] : null
    readonly property int mainBattery: mainDev ? (parseInt(mainDev.battery) || 0) : 0
    readonly property string backend: Quickshell.env("HOME") + "/.config/hypr/scripts/quickshell/bluetooth/bt.sh"

    // ---------------- state ----------------
    property bool loaded: false
    property bool present: true
    property bool power: false
    property var connectedDevs: []
    property var devices: []
    property string filter: ""
    property string busyMac: ""
    property string busyLabel: ""
    property string failedMac: ""
    property string failMsg: ""

    readonly property var rows: {
        let q = root.filter.trim().toLowerCase();
        let match = d => q === "" || d.name.toLowerCase().indexOf(q) >= 0;
        let paired = root.devices.filter(d => d.action === "Connect" && match(d));
        let nearby = root.devices.filter(d => d.action !== "Connect" && match(d));
        let out = [];
        // with one device connected the hero shows it; with more they're listed here
        if (root.connectedDevs.length > 1) {
            out.push({ header: "Connected" });
            out = out.concat(root.connectedDevs.filter(match).map(d => Object.assign({}, d, { action: "Disconnect" })));
        }
        if (paired.length) { out.push({ header: "My devices" }); out = out.concat(paired); }
        if (nearby.length) { out.push({ header: "Nearby" }); out = out.concat(nearby); }
        return out;
    }

    function act(cmd, dev, label) {
        if (actionProc.running) return;
        root.busyMac = dev ? dev.mac : "";
        root.busyLabel = label || "";
        root.failedMac = "";
        actionProc.cmd = cmd;
        actionProc.command = ["bash", root.backend, cmd].concat(dev ? [dev.mac] : []);
        actionProc.running = true;
    }
    function refresh() { if (!statusProc.running) statusProc.running = true; }

    Process {
        id: statusProc
        command: ["bash", root.backend, "status"]
        stdout: StdioCollector {
            onStreamFinished: {
                let d; try { d = JSON.parse(this.text); } catch (e) { return; }
                root.present = d.present;
                root.power = d.power === "on";
                root.connectedDevs = d.connected || [];
                root.devices = d.devices || [];
                root.loaded = true;
            }
        }
    }
    Timer { interval: 3000; running: true; repeat: true; triggeredOnStart: true; onTriggered: root.refresh() }

    // discovery: runs while the popup is open (bluetoothctl stops itself after 60 s;
    // the rescan button starts another round)
    Process {
        id: scanProc
        command: ["bluetoothctl", "--timeout", "60", "scan", "on"]
        running: root.power
    }

    Process {
        id: actionProc
        property string cmd: ""
        onExited: (code) => {
            if (code !== 0 && (cmd === "connect" || cmd === "pair")) {
                root.failedMac = root.busyMac;
                root.failMsg = cmd === "pair" ? "Pairing failed: put the device in pairing mode" : "Couldn't connect";
            }
            root.busyMac = "";
            root.refresh();
        }
    }

    // ---------------- intro (staged like the Volume popup) ----------------
    property real intro: 0
    property real introHeader: 0
    property real introContent: 0
    property real introList: 0
    ParallelAnimation {
        running: true
        NumberAnimation { target: root; property: "intro"; from: 0; to: 1; duration: 700; easing.type: Easing.OutExpo }
        SequentialAnimation {
            PauseAnimation { duration: 90 }
            NumberAnimation { target: root; property: "introHeader"; from: 0; to: 1; duration: 700; easing.type: Easing.OutBack; easing.overshoot: 1.2 }
        }
        SequentialAnimation {
            PauseAnimation { duration: 180 }
            NumberAnimation { target: root; property: "introContent"; from: 0; to: 1; duration: 650; easing.type: Easing.OutExpo }
        }
        SequentialAnimation {
            PauseAnimation { duration: 260 }
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

            // ---------------- hero: status + connected device in one ----------------
            RowLayout {
                Layout.fillWidth: true
                Layout.preferredHeight: root.s(150)
                spacing: root.s(25)
                opacity: root.introHeader
                transform: Translate { y: root.s(26) * (1 - root.introHeader) }

                Item {
                    Layout.preferredWidth: root.s(130); Layout.preferredHeight: root.s(130)

                    PulseRings {
                        anchors.fill: parent
                        color: root.accent
                        running: root.power && (root.connectedDevs.length > 0 || scanProc.running)
                        duration: scanProc.running ? 1800 : 3400
                        maxScale: 1.35
                    }

                    // battery of the connected device, wrapped around the orb
                    Canvas {
                        id: batRing
                        anchors.fill: parent
                        visible: root.power && root.mainBattery > 0
                        property real shown: 0
                        Component.onCompleted: shown = root.mainBattery
                        Behavior on shown { NumberAnimation { duration: 1200; easing.type: Easing.OutCubic } }
                        onShownChanged: requestPaint()
                        Connections {
                            target: root
                            function onMainBatteryChanged() { batRing.shown = root.mainBattery; }
                            function onAccentChanged() { batRing.requestPaint(); }
                        }
                        onPaint: {
                            let ctx = getContext("2d");
                            ctx.reset();
                            let r = width / 2, lw = root.s(3.5);
                            ctx.lineWidth = lw; ctx.lineCap = "round";
                            ctx.strokeStyle = root.tint(0.1).toString();
                            ctx.beginPath(); ctx.arc(r, r, r - lw / 2, 0, 2 * Math.PI); ctx.stroke();
                            let c = shown <= 20 ? root.red : root.accent;
                            ctx.strokeStyle = Qt.lighter(c, 1.15).toString();
                            ctx.beginPath();
                            ctx.arc(r, r, r - lw / 2, -Math.PI / 2, -Math.PI / 2 + 2 * Math.PI * shown / 100);
                            ctx.stroke();
                        }
                    }

                    HeroOrb {
                        anchors.fill: parent
                        anchors.margins: root.s(10)
                        accent: root.accent
                        base: root.base
                        active: root.power && root.connectedDevs.length > 0
                        // the orb is the on/off switch
                        onClicked: if (root.present) root.act("power", null, "")

                        // radar sweep while discovering
                        Canvas {
                            id: radar
                            anchors.fill: parent
                            property real level: root.power && scanProc.running ? 1 : 0
                            Behavior on level { NumberAnimation { duration: 500 } }
                            opacity: level
                            visible: level > 0
                            RotationAnimation on rotation {
                                running: radar.visible
                                from: 0; to: 360; duration: 2400; loops: Animation.Infinite
                            }
                            Connections { target: root; function onAccentChanged() { radar.requestPaint(); } }
                            onPaint: {
                                let ctx = getContext("2d");
                                ctx.reset();
                                let r = width / 2;
                                let g = ctx.createConicalGradient(r, r, 0);
                                let c = root.accent;
                                g.addColorStop(0.0, Qt.rgba(c.r, c.g, c.b, 0.55).toString());
                                g.addColorStop(0.25, Qt.rgba(c.r, c.g, c.b, 0.0).toString());
                                g.addColorStop(1.0, Qt.rgba(c.r, c.g, c.b, 0.0).toString());
                                ctx.fillStyle = g;
                                ctx.beginPath();
                                ctx.moveTo(r, r);
                                ctx.arc(r, r, r, 0, 2 * Math.PI);
                                ctx.fill();
                            }
                        }

                        Text {
                            anchors.centerIn: parent
                            // the connected device's own icon, else the Bluetooth mark
                            text: !root.power ? root.g(0xF00B2) : root.mainDev ? root.deviceIcon(root.mainDev) : root.g(0xF00AF)
                            color: root.power ? Qt.lighter(root.accent, 1.2) : root.overlay0
                            font.family: root.icons; font.pixelSize: root.s(44)
                            Behavior on color { ColorAnimation { duration: 300 } }
                            scale: root.power ? 1.0 : 0.85
                            Behavior on scale { NumberAnimation { duration: 500; easing.type: Easing.OutBack } }
                        }
                    }
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: root.s(3)
                    // device name when one is connected, otherwise just "Bluetooth"
                    Text {
                        Layout.fillWidth: true
                        elide: Text.ElideRight
                        text: root.power && root.mainDev ? root.mainDev.name : "Bluetooth"
                        color: root.text
                        font.family: root.ui; font.weight: Font.Black; font.pixelSize: root.s(22)
                        fontSizeMode: Text.HorizontalFit
                        minimumPixelSize: root.s(16)
                    }
                    Text {
                        Layout.fillWidth: true
                        elide: Text.ElideRight
                        text: {
                            if (!root.present) return "No Bluetooth adapter";
                            if (!root.power) return "Off";
                            let parts = [];
                            if (root.mainDev) {
                                if (root.mainBattery > 0) parts.push(root.mainBattery + "% battery");
                                let pr = root.mainDev.profile;
                                if (pr && pr !== "None" && pr !== "Connected") parts.push(pr.replace(/ \(.*\)$/, ""));
                                if (!parts.length) parts.push("Connected");
                            } else parts.push(root.connectedDevs.length ? root.connectedDevs.length + " connected" : "On");
                            if (scanProc.running) parts.push("scanning");
                            return parts.join(" · ");
                        }
                        color: root.subtext0
                        font.family: root.ui; font.pixelSize: root.s(12)
                    }
                }

                // disconnect: round icon on the right
                Rectangle {
                    visible: root.power && root.mainDev !== null
                    Layout.preferredWidth: root.s(38); Layout.preferredHeight: root.s(38)
                    Layout.alignment: Qt.AlignVCenter
                    radius: width / 2
                    color: discMa.containsMouse ? Qt.alpha(root.red, 0.16) : root.tint(0.06)
                    border.width: 1
                    border.color: discMa.containsMouse ? Qt.alpha(root.red, 0.5) : root.tint(0.08)
                    scale: discMa.pressed ? 0.9 : discMa.containsMouse ? 1.08 : 1.0
                    Behavior on color { ColorAnimation { duration: 150 } }
                    Behavior on scale { NumberAnimation { duration: 300; easing.type: Easing.OutBack } }
                    Text {
                        anchors.centerIn: parent
                        text: root.g(0xF0338)
                        color: discMa.containsMouse ? root.red : root.subtext0
                        font.family: root.icons; font.pixelSize: root.s(17)
                        Behavior on color { ColorAnimation { duration: 150 } }
                    }
                    MouseArea {
                        id: discMa
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.act("disconnect", root.mainDev, "Disconnecting")
                    }
                }
            }

            // ---------------- filter ----------------
            RowLayout {
                Layout.fillWidth: true
                visible: root.power
                opacity: root.introContent
                spacing: root.s(8)
                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: root.s(46)
                    radius: height / 2
                    color: root.tint(filterInput.activeFocus ? 0.09 : 0.05)
                    border.width: 1
                    border.color: root.tint(filterInput.activeFocus ? 0.18 : 0.05)
                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: root.s(18)
                        anchors.rightMargin: root.s(14)
                        spacing: root.s(10)
                        Text { text: "\uf002"; color: root.overlay0; font.family: root.icons; font.pixelSize: root.s(15) }
                        TextField {
                            id: filterInput
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            background: Item {}
                            color: root.text
                            font.family: root.ui; font.pixelSize: root.s(14)
                            placeholderText: "Filter devices"
                            placeholderTextColor: root.overlay0
                            verticalAlignment: TextInput.AlignVCenter
                            onTextChanged: root.filter = text
                        }
                    }
                }
                IconButton {
                    implicitWidth: root.s(46); implicitHeight: root.s(46)
                    color: hovered ? root.tint(0.12) : root.tint(0.05)
                    border.width: 1
                    border.color: root.tint(0.05)
                    iconSize: root.s(18)
                    icon: root.g(0xF0450)
                    spinning: scanProc.running
                    onClicked: if (!scanProc.running) scanProc.running = true
                }
            }

            // ---------------- list ----------------
            Item {
                Layout.fillWidth: true
                Layout.fillHeight: true

                Column {
                    anchors.centerIn: parent
                    spacing: root.s(12)
                    visible: root.loaded && (!root.power || root.rows.length === 0)
                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: !root.present ? "No Bluetooth adapter found"
                            : !root.power ? "Bluetooth is off"
                            : root.filter !== "" ? "No devices match \"" + root.filter + "\""
                            : scanProc.running ? "Looking for devices…" : "No devices found"
                        color: root.subtext0
                        font.family: root.ui; font.pixelSize: root.s(14)
                    }
                    SmallButton {
                        anchors.horizontalCenter: parent.horizontalCenter
                        visible: root.present && !root.power
                        label: "Turn on"
                        onClicked: root.act("power", null, "")
                    }
                }

                ListView {
                    id: list
                    anchors.fill: parent
                    clip: true
                    visible: root.power
                    spacing: root.s(2)
                    boundsBehavior: Flickable.StopAtBounds
                    model: root.rows
                    ScrollBar.vertical: ScrollBar {
                        width: root.s(5)
                        policy: ScrollBar.AsNeeded
                        contentItem: Rectangle { implicitWidth: root.s(5); radius: width / 2; color: root.tint(0.3) }
                        background: Item {}
                    }

                    delegate: Item {
                        id: rowItem
                        readonly property bool isHeader: modelData.header !== undefined
                        readonly property bool isBusy: !isHeader && root.busyMac === modelData.mac
                        readonly property bool isFailed: !isHeader && root.failedMac === modelData.mac
                        readonly property bool paired: !isHeader && modelData.action === "Connect"
                        readonly property bool isConnected: !isHeader && modelData.action === "Disconnect"
                        width: list.width
                        height: isHeader ? root.s(34) : root.s(50) + (isFailed ? root.s(16) : 0)
                        // rows ease in one after another when the popup opens
                        readonly property real enter: Math.max(0, Math.min(1, root.introList * 2.2 - Math.min(index, 14) * 0.08))
                        opacity: enter
                        transform: Translate { x: root.s(22) * (1 - rowItem.enter) }
                        Behavior on height { NumberAnimation { duration: 160 } }

                        Text {
                            visible: rowItem.isHeader
                            anchors.left: parent.left
                            anchors.leftMargin: root.s(14)
                            anchors.bottom: parent.bottom
                            anchors.bottomMargin: root.s(6)
                            text: rowItem.isHeader ? modelData.header : ""
                            color: root.overlay0
                            font.family: root.ui; font.weight: Font.DemiBold; font.pixelSize: root.s(12)
                        }

                        Rectangle {
                            visible: !rowItem.isHeader
                            anchors.fill: parent
                            radius: root.s(16)
                            color: rowMa.containsMouse ? root.tint(0.07) : "transparent"
                            Behavior on color { ColorAnimation { duration: 120 } }

                            MouseArea {
                                id: rowMa
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: if (root.busyMac === "") {
                                    if (rowItem.isConnected) root.act("disconnect", modelData, "Disconnecting…");
                                    else root.act(rowItem.paired ? "connect" : "pair", modelData, rowItem.paired ? "Connecting…" : "Pairing…");
                                }
                            }

                            RowLayout {
                                anchors.left: parent.left; anchors.right: parent.right; anchors.top: parent.top
                                height: root.s(50)
                                anchors.leftMargin: root.s(14)
                                anchors.rightMargin: root.s(14)
                                spacing: root.s(12)
                                Text {
                                    text: rowItem.isHeader ? "" : root.deviceIcon(modelData)
                                    color: rowMa.containsMouse ? Qt.lighter(root.accent, 1.2) : root.text
                                    font.family: root.icons; font.pixelSize: root.s(18)
                                    scale: rowMa.containsMouse ? 1.18 : 1.0
                                    Behavior on scale { NumberAnimation { duration: 350; easing.type: Easing.OutBack } }
                                    Behavior on color { ColorAnimation { duration: 200 } }
                                }
                                Text {
                                    Layout.fillWidth: true
                                    elide: Text.ElideRight
                                    text: rowItem.isHeader ? "" : modelData.name
                                    color: root.text
                                    font.family: root.ui; font.pixelSize: root.s(14)
                                }
                                Text {
                                    visible: rowItem.isBusy || (!rowItem.isHeader && !(rowItem.paired && rowMa.containsMouse))
                                    text: rowItem.isBusy ? root.busyLabel
                                        : rowItem.isConnected ? (rowMa.containsMouse ? "Disconnect" : (parseInt(modelData.battery) > 0 ? modelData.battery + "%" : "Connected"))
                                        : rowItem.paired ? "" : "Pair"
                                    color: root.overlay0
                                    font.family: root.ui; font.pixelSize: root.s(12)
                                }
                                Spinner { visible: rowItem.isBusy }
                                Text {   // remove (unpair) a paired device
                                    visible: rowItem.paired && rowMa.containsMouse && !rowItem.isBusy
                                    text: root.g(0xF01B4)
                                    color: removeMa.containsMouse ? root.red : root.overlay0
                                    font.family: root.icons; font.pixelSize: root.s(15)
                                    MouseArea {
                                        id: removeMa
                                        anchors.fill: parent; anchors.margins: -root.s(6)
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: root.act("remove", modelData, "Removing…")
                                    }
                                }
                            }
                            Text {
                                visible: rowItem.isFailed
                                x: root.s(48); y: root.s(40)
                                text: root.failMsg
                                color: root.red
                                font.family: root.ui; font.pixelSize: root.s(11)
                            }
                        }
                    }
                }
            }
        }
    }

    // ---------------- small components ----------------
    component SmallButton: Rectangle {
        id: sb
        property string label: ""
        property bool primary: false
        signal clicked()
        implicitWidth: sbText.implicitWidth + root.s(28)
        implicitHeight: root.s(34)
        Layout.preferredWidth: implicitWidth; Layout.preferredHeight: implicitHeight
        radius: height / 2
        opacity: enabled ? 1 : 0.5
        color: primary ? root.tint(sbMa.containsMouse ? 0.95 : 0.85) : root.tint(sbMa.containsMouse ? 0.14 : 0.08)
        Behavior on color { ColorAnimation { duration: 120 } }
        Text {
            id: sbText
            anchors.centerIn: parent
            text: sb.label
            color: sb.primary ? root.base : root.text
            font.family: root.ui; font.weight: Font.DemiBold; font.pixelSize: root.s(13)
        }
        MouseArea { id: sbMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: sb.clicked() }
    }

    component IconButton: Rectangle {
        id: ib
        property string icon: ""
        property bool spinning: false
        property bool hovered: ibMa.containsMouse
        property real iconSize: root.s(16)
        signal clicked()
        implicitWidth: root.s(34); implicitHeight: root.s(34)
        Layout.preferredWidth: implicitWidth; Layout.preferredHeight: implicitHeight
        radius: width / 2
        color: ibMa.containsMouse ? root.tint(0.12) : "transparent"
        Text {
            anchors.centerIn: parent
            text: ib.icon
            color: root.subtext0
            font.family: root.icons; font.pixelSize: ib.iconSize
            RotationAnimation on rotation { running: ib.spinning; from: 0; to: 360; duration: 900; loops: Animation.Infinite }
        }
        MouseArea { id: ibMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: ib.clicked() }
    }

    component Spinner: Item {
        implicitWidth: root.s(16); implicitHeight: root.s(16)
        Rectangle { anchors.fill: parent; radius: width / 2; color: "transparent"; border.width: root.s(2); border.color: root.tint(0.2) }
        Rectangle { width: root.s(5); height: width; radius: width / 2; color: root.text; x: parent.width / 2 - width / 2; y: -root.s(1) }
        RotationAnimation on rotation { running: parent.visible; from: 0; to: 360; duration: 800; loops: Animation.Infinite }
    }
}
