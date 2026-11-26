import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import QtQuick.Window
import Quickshell
import Quickshell.Io
import "../"

// Wi-Fi popup (SUPER+N / top bar Wi-Fi pill): a plain scrollable list of every network
// in range, saved ones first, with a filter box for crowded places.
// Backend: wifi/wifi.py (nmcli).
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
    readonly property color accent: _theme.blue
    readonly property string ui: "SF Pro Display"
    readonly property string icons: "Iosevka Nerd Font"
    function g(cp) { return String.fromCodePoint(cp); }
    function tint(a) { return Qt.rgba(root.text.r, root.text.g, root.text.b, a); }
    function signalIcon(sig) { return sig >= 80 ? "󰤨" : sig >= 60 ? "󰤥" : sig >= 40 ? "󰤢" : sig >= 20 ? "󰤟" : "󰤯"; }

    readonly property string backend: Quickshell.env("HOME") + "/.config/hypr/scripts/quickshell/wifi/wifi.py"

    // ---------------- state ----------------
    property bool loaded: false
    property bool present: true
    property bool power: false
    property var connected: null
    property var networks: []
    property string filter: ""
    property string expanded: ""        // SSID whose password field is open
    property string busySsid: ""        // SSID being connected / forgotten
    property string failedSsid: ""
    property string failMsg: ""
    property bool scanning: false
    property real lastScanEnd: 0
    property bool openScanDone: false

    readonly property var rows: {
        let q = root.filter.trim().toLowerCase();
        let nets = root.networks.filter(n => q === "" || n.ssid.toLowerCase().indexOf(q) >= 0);
        let saved = nets.filter(n => n.saved), other = nets.filter(n => !n.saved);
        let out = [];
        if (saved.length) { out.push({ header: "Saved networks" }); out = out.concat(saved); }
        if (other.length) { out.push({ header: saved.length ? "Other networks" : "Networks" }); out = out.concat(other); }
        return out;
    }

    function run(args, after) {
        actionProc.after = after || "";
        actionProc.command = ["python3", "-I", root.backend].concat(args);
        actionProc.running = true;
    }
    function refresh() { if (!statusProc.running) statusProc.running = true; }
    function connectTo(net, password) {
        if (actionProc.running) return;
        root.busySsid = net.ssid;
        root.failedSsid = "";
        root.run(["connect", net.ssid, password || ""], "connect");
    }
    function onRowClicked(net) {
        if (root.busySsid !== "") return;
        if (net.saved || net.security === "") { root.expanded = ""; root.connectTo(net, ""); }
        else root.expanded = root.expanded === net.ssid ? "" : net.ssid;
    }

    Process {
        id: statusProc
        command: ["python3", "-I", root.backend, "status"]
        stdout: StdioCollector {
            onStreamFinished: {
                let d; try { d = JSON.parse(this.text); } catch (e) { return; }
                root.present = d.present;
                root.power = d.power;
                root.connected = d.connected;
                // NetworkManager briefly reports no networks while (and just after) it
                // rescans; keep showing the last list instead of flashing "none found"
                let nets = d.networks || [];
                let settling = root.scanning || Date.now() - root.lastScanEnd < 8000;
                if (nets.length > 0 || !settling || !d.power) root.networks = nets;
                root.loaded = root.loaded || nets.length > 0 || !settling || !d.power;
                // the scan on open is skipped while power is still unknown; run it now
                if (!root.openScanDone && d.power) { root.openScanDone = true; root.rescan(); }
            }
        }
    }
    Timer { interval: 4000; running: true; repeat: true; triggeredOnStart: true; onTriggered: root.refresh() }

    Process {
        id: scanProc
        command: ["python3", "-I", root.backend, "rescan"]
        onRunningChanged: {
            root.scanning = running;
            if (!running) { root.lastScanEnd = Date.now(); root.refresh(); settleRefresh.restart(); }
        }
    }
    Timer { id: settleRefresh; interval: 2500; repeat: true; property int n: 0
            onTriggered: { root.refresh(); if (++n >= 3) { n = 0; stop(); } } }
    function rescan() { if (!scanProc.running && root.power) scanProc.running = true; }

    Process {
        id: actionProc
        property string after: ""
        stdout: StdioCollector {
            onStreamFinished: {
                let d; try { d = JSON.parse(this.text); } catch (e) { d = { ok: false, error: "Something went wrong" }; }
                if (actionProc.after === "connect") {
                    if (!d.ok) { root.failedSsid = root.busySsid; root.failMsg = d.error || "Couldn't connect"; }
                    else root.expanded = "";
                }
                root.busySsid = "";
                root.refresh();
            }
        }
    }

    Component.onCompleted: if (root.power) { root.openScanDone = true; rescan(); }

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

            // ---------------- hero: status + connected network in one ----------------
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
                        running: root.power && (root.connected !== null || root.scanning)
                        duration: root.scanning ? 1500 : 3400
                        maxScale: 1.35
                    }

                    HeroOrb {
                        anchors.fill: parent
                        accent: root.accent
                        base: root.base
                        active: root.power && root.connected !== null
                        // the orb is the on/off switch
                        onClicked: if (root.present) root.run(["power", root.power ? "off" : "on"], "power")

                        // Wi-Fi arcs: lit by signal strength, a wave rolls outward while scanning
                        Canvas {
                            id: arcs
                            anchors.fill: parent
                            visible: root.power
                            readonly property int lit: !root.connected ? 0
                                : root.connected.signal >= 67 ? 3 : root.connected.signal >= 34 ? 2 : 1
                            property real litAnim: lit
                            Behavior on litAnim { NumberAnimation { duration: 700; easing.type: Easing.OutCubic } }
                            property real sweep: 0
                            NumberAnimation on sweep {
                                running: root.scanning && root.power
                                from: 0; to: 1; duration: 1200; loops: Animation.Infinite
                            }
                            property real wave: root.scanning ? 1 : 0
                            Behavior on wave { NumberAnimation { duration: 400 } }
                            onLitAnimChanged: requestPaint()
                            onSweepChanged: requestPaint()
                            onWaveChanged: requestPaint()
                            Connections {
                                target: root
                                function onAccentChanged() { arcs.requestPaint(); }
                                function onConnectedChanged() { arcs.requestPaint(); }
                            }
                            onPaint: {
                                let ctx = getContext("2d");
                                ctx.reset();
                                // glyph spans cy-0.42w (outer arc) to cy+0.045w (dot): cy = 0.70h
                                // puts its box in the middle, nudged down a hair for the heavy top
                                let w = width, cx = w / 2, cy = height * 0.70;
                                let col = Qt.lighter(root.accent, 1.25).toString();
                                ctx.strokeStyle = col; ctx.fillStyle = col;
                                ctx.lineCap = "round";
                                ctx.lineWidth = w * 0.065;
                                for (let i = 0; i <= 3; i++) {
                                    let still = i === 0 ? (root.connected ? 1 : 0.3)
                                                        : Math.max(0.18, Math.min(1, litAnim - i + 1));
                                    let d = sweep * 4.6 - i;
                                    let rolling = 0.22 + 0.78 * Math.max(0, 1 - Math.abs(d - 0.6) * 1.5);
                                    ctx.globalAlpha = still * (1 - wave) + rolling * wave;
                                    ctx.beginPath();
                                    if (i === 0) { ctx.arc(cx, cy, w * 0.045, 0, 2 * Math.PI); ctx.fill(); }
                                    else { ctx.arc(cx, cy, w * (0.09 + 0.1 * i), -Math.PI * 0.78, -Math.PI * 0.22); ctx.stroke(); }
                                }
                            }
                        }
                        Text {
                            anchors.centerIn: parent
                            visible: !root.power
                            text: "󰤭"
                            color: root.overlay0
                            font.family: root.icons; font.pixelSize: root.s(48)
                        }
                    }
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: root.s(3)
                    // network name when connected, otherwise just "Wi-Fi"
                    Text {
                        Layout.fillWidth: true
                        elide: Text.ElideRight
                        text: root.power && root.connected ? root.connected.ssid : "Wi-Fi"
                        color: root.text
                        font.family: root.ui; font.weight: Font.Black; font.pixelSize: root.s(22)
                        fontSizeMode: Text.HorizontalFit
                        minimumPixelSize: root.s(16)
                    }
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: root.s(7)
                        Item {   // live dot while connected
                            visible: root.power && root.connected !== null
                            Layout.preferredWidth: root.s(8); Layout.preferredHeight: root.s(8)
                            PulseRings {
                                anchors.fill: parent
                                color: root.green
                                rings: 2; maxScale: 2.6; duration: 2200; strength: 0.7
                            }
                            Rectangle { anchors.fill: parent; radius: width / 2; color: root.green }
                        }
                        Text {
                            Layout.fillWidth: true
                            elide: Text.ElideRight
                            text: !root.present ? "No Wi-Fi adapter" : !root.power ? "Off"
                                : root.connected ? root.connected.signal + "% · " + root.connected.band
                                                   + (root.connected.ip ? " · " + root.connected.ip : "")
                                : root.scanning ? "Scanning…"
                                : root.networks.length + " networks nearby"
                            color: ipMa.containsMouse ? root.text : root.subtext0
                            font.family: root.ui; font.pixelSize: root.s(12)
                            MouseArea {   // click to copy the IP
                                id: ipMa
                                anchors.fill: parent
                                enabled: root.connected !== null && !!root.connected.ip
                                hoverEnabled: true
                                cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                                onClicked: Quickshell.execDetached(["wl-copy", root.connected.ip])
                            }
                        }
                    }
                }

                // disconnect: round icon on the right
                Rectangle {
                    visible: root.power && root.connected !== null
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
                        onClicked: root.run(["disconnect"], "disconnect")
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
                            placeholderText: "Filter networks"
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
                    icon: "󰑐"
                    spinning: root.scanning
                    onClicked: root.rescan()
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
                        text: !root.present ? "No Wi-Fi adapter found"
                            : !root.power ? "Wi-Fi is off"
                            : root.filter !== "" ? "No networks match \"" + root.filter + "\""
                            : root.scanning || Date.now() - root.lastScanEnd < 8000 ? "Scanning…" : "No networks found"
                        color: root.subtext0
                        font.family: root.ui; font.pixelSize: root.s(14)
                    }
                    SmallButton {
                        anchors.horizontalCenter: parent.horizontalCenter
                        visible: root.present && !root.power
                        label: "Turn on"
                        onClicked: root.run(["power", "on"], "power")
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
                        readonly property bool isOpen: !isHeader && root.expanded === modelData.ssid
                        readonly property bool isBusy: !isHeader && root.busySsid === modelData.ssid
                        readonly property bool isFailed: !isHeader && root.failedSsid === modelData.ssid
                        width: list.width
                        height: isHeader ? root.s(34) : root.s(50) + (isOpen ? root.s(52) : 0) + (isFailed && !isOpen ? root.s(18) : 0)
                        // rows ease in one after another when the popup opens
                        readonly property real enter: Math.max(0, Math.min(1, root.introList * 2.2 - Math.min(index, 14) * 0.08))
                        opacity: enter
                        transform: Translate { x: root.s(22) * (1 - rowItem.enter) }
                        Behavior on height { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }

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
                            clip: true
                            color: rowItem.isOpen ? Qt.rgba(root.base.r, root.base.g, root.base.b, 0.55)
                                 : rowMa.containsMouse ? root.tint(0.07) : "transparent"
                            Behavior on color { ColorAnimation { duration: 120 } }

                            MouseArea {
                                id: rowMa
                                anchors.left: parent.left; anchors.right: parent.right; anchors.top: parent.top
                                height: root.s(50)
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.onRowClicked(modelData)
                            }

                            RowLayout {
                                anchors.left: parent.left; anchors.right: parent.right; anchors.top: parent.top
                                height: root.s(50)
                                anchors.leftMargin: root.s(14)
                                anchors.rightMargin: root.s(14)
                                spacing: root.s(12)
                                Text {
                                    text: rowItem.isHeader ? "" : root.signalIcon(modelData.signal)
                                    color: rowMa.containsMouse || rowItem.isOpen ? Qt.lighter(root.accent, 1.2) : root.text
                                    font.family: root.icons; font.pixelSize: root.s(18)
                                    scale: rowMa.containsMouse ? 1.18 : 1.0
                                    Behavior on scale { NumberAnimation { duration: 350; easing.type: Easing.OutBack } }
                                    Behavior on color { ColorAnimation { duration: 200 } }
                                }
                                Text {
                                    Layout.fillWidth: true
                                    elide: Text.ElideRight
                                    text: rowItem.isHeader ? "" : modelData.ssid
                                    color: root.text
                                    font.family: root.ui; font.pixelSize: root.s(14)
                                }
                                Text {   // lock for secured networks
                                    visible: !rowItem.isHeader && modelData.security !== ""
                                    text: "\uf023"
                                    color: root.overlay0
                                    font.family: root.icons; font.pixelSize: root.s(12)
                                }
                                Text {
                                    visible: !rowItem.isHeader && !rowItem.isBusy && !(modelData.saved && rowMa.containsMouse)
                                    text: rowItem.isHeader ? "" : modelData.band
                                    color: root.overlay0
                                    font.family: root.ui; font.pixelSize: root.s(11)
                                }
                                Spinner { visible: rowItem.isBusy }
                                Text {   // forget a saved network
                                    visible: !rowItem.isHeader && modelData.saved && rowMa.containsMouse && !rowItem.isBusy
                                    text: "󰆴"
                                    color: forgetMa.containsMouse ? root.red : root.overlay0
                                    font.family: root.icons; font.pixelSize: root.s(15)
                                    MouseArea {
                                        id: forgetMa
                                        anchors.fill: parent; anchors.margins: -root.s(6)
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: root.run(["forget", modelData.ssid], "forget")
                                    }
                                }
                            }

                            // error under the row
                            Text {
                                visible: rowItem.isFailed && !rowItem.isOpen
                                x: root.s(48); y: root.s(42)
                                text: root.failMsg
                                color: root.red
                                font.family: root.ui; font.pixelSize: root.s(11)
                            }

                            // password entry
                            RowLayout {
                                visible: rowItem.isOpen
                                anchors.left: parent.left; anchors.right: parent.right
                                y: root.s(50)
                                height: root.s(44)
                                anchors.leftMargin: root.s(14)
                                anchors.rightMargin: root.s(10)
                                spacing: root.s(8)
                                Rectangle {
                                    Layout.fillWidth: true
                                    Layout.fillHeight: true
                                    radius: height / 2
                                    color: root.tint(0.07)
                                    border.width: 1
                                    border.color: rowItem.isFailed ? Qt.alpha(root.red, 0.6) : root.tint(pw.activeFocus ? 0.25 : 0.08)
                                    RowLayout {
                                        anchors.fill: parent
                                        anchors.leftMargin: root.s(14)
                                        anchors.rightMargin: root.s(10)
                                        TextInput {
                                            id: pw
                                            Layout.fillWidth: true
                                            verticalAlignment: TextInput.AlignVCenter
                                            echoMode: showPw.on ? TextInput.Normal : TextInput.Password
                                            color: root.text
                                            font.family: root.ui; font.pixelSize: root.s(14)
                                            clip: true
                                            onVisibleChanged: if (visible) { text = ""; forceActiveFocus(); }
                                            Keys.onReturnPressed: if (text.length > 0) root.connectTo(modelData, text)
                                            Keys.onEscapePressed: (e) => { root.expanded = ""; e.accepted = true; }
                                            Text {
                                                anchors.verticalCenter: parent.verticalCenter
                                                visible: pw.text.length === 0
                                                text: rowItem.isFailed ? root.failMsg : "Password"
                                                color: rowItem.isFailed ? root.red : root.overlay0
                                                font: pw.font
                                            }
                                        }
                                        Text {
                                            id: showPw
                                            property bool on: false
                                            text: on ? "󰈈" : "󰈉"
                                            color: root.overlay0
                                            font.family: root.icons; font.pixelSize: root.s(15)
                                            MouseArea { anchors.fill: parent; anchors.margins: -root.s(6); cursorShape: Qt.PointingHandCursor; onClicked: showPw.on = !showPw.on }
                                        }
                                    }
                                }
                                SmallButton {
                                    label: rowItem.isBusy ? "Joining…" : "Join"
                                    primary: true
                                    enabled: pw.text.length > 0 && !rowItem.isBusy
                                    onClicked: root.connectTo(modelData, pw.text)
                                }
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
