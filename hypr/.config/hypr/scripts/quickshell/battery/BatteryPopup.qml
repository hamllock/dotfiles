import QtQuick
import QtQuick.Layouts
import QtQuick.Window
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import "../"

Item {
    id: window

    Caching { id: paths }

    // --- RECEIVE THE DBUS LIST FROM MAIN.QML ---
    property var notifModel
    property var liveNotifs


    // --- Responsive Scaling Logic ---
    Scaler {
        id: scaler
        // Uses the physical screen width so the popup scales synchronously with the TopBar
        currentWidth: Screen.width
    }
    
    // Helper function scoped to the root Item for easy access in deeply nested elements and Canvases
    function s(val) { 
        return scaler.s(val); 
    }

    // -------------------------------------------------------------------------
    // COLORS (Dynamic Matugen Palette)
    // -------------------------------------------------------------------------
    MatugenColors { id: _theme }
    readonly property color base: _theme.base
    readonly property color mantle: _theme.mantle
    readonly property color crust: _theme.crust
    readonly property color text: _theme.text
    readonly property color subtext0: _theme.subtext0
    readonly property color overlay0: _theme.overlay0
    readonly property color overlay1: _theme.overlay1
    readonly property color surface0: _theme.surface0
    readonly property color surface1: _theme.surface1
    readonly property color surface2: _theme.surface2
    
    readonly property color mauve: _theme.mauve
    readonly property color pink: _theme.pink
    readonly property color red: _theme.red
    readonly property color maroon: _theme.maroon
    readonly property color peach: _theme.peach
    readonly property color yellow: _theme.yellow
    readonly property color green: _theme.green
    readonly property color teal: _theme.teal
    readonly property color sapphire: _theme.sapphire
    readonly property color blue: _theme.blue

    // -------------------------------------------------------------------------
    // STATE & POLLING
    // -------------------------------------------------------------------------
    property int batCapacity: 0
    property string batStatus: "Unknown"
    property string powerProfile: "balanced"
    
    property int upHours: 0
    property int upMins: 0

    property real sysVolume: 0
    property bool sysMuted: false
    property real sysBrightness: 0
    
    property string currentUserName: ""
    

    // Anti-Jitter Sync States
    property bool isDraggingVol: false
    property bool isDraggingBri: false

    Timer { id: volSyncDelay; interval: 800; onTriggered: window.isDraggingVol = false; triggeredOnStart: true; }
    Timer { id: briSyncDelay; interval: 800; onTriggered: window.isDraggingBri = false; triggeredOnStart: true; }

    readonly property bool isCharging: batStatus === "Charging"

    // The whole popup takes the power mode's colour; only a low battery (not charging)
    // overrides it with red. Charging shows as the icon + "CHARGING" label.
    readonly property bool lowBattery: !isCharging && batCapacity <= 20
    readonly property color batColorStart: lowBattery ? window.red : profileStart
    readonly property color batColorEnd: Qt.lighter(batColorStart, 1.15)

    // Unified hue for Performance Profile
    // performance = warm amber (red stays reserved for low battery), saver = green,
    // balanced = the theme's neutral
    readonly property color profileStart: {
        if (powerProfile === "performance") return "#E3A770";
        if (powerProfile === "power-saver") return window.green;
        return window.text;
    }
    readonly property color profileEnd: Qt.lighter(profileStart, 1.15)

    // Ambient Blobs - Based strictly on aesthetic pairs derived from battery state
    readonly property color ambientPrimary: window.batColorStart
    readonly property color ambientSecondary: window.batColorStart

    property real animCapacity: 0
    Behavior on animCapacity { NumberAnimation { duration: 1200; easing.type: Easing.OutQuint } }
    
    onAnimCapacityChanged: batCanvas.requestPaint()
    onBatColorStartChanged: batCanvas.requestPaint()



    Process {
        id: sysPoller
        command: ["bash", "-c", 
            "cat /sys/class/power_supply/BAT*/capacity 2>/dev/null | head -n1 || echo '0'; " +
            "cat /sys/class/power_supply/BAT*/status 2>/dev/null | head -n1 || echo 'Unknown'; " +
            "powerprofilesctl get 2>/dev/null || echo 'balanced'; " +
            "awk '{print int($1/3600)\"h \"int(($1%3600)/60)\"m\"}' /proc/uptime 2>/dev/null || echo '0h 0m'; " +
            "wpctl get-volume @DEFAULT_AUDIO_SINK@ 2>/dev/null | awk '{print int($2*100), ($3==\"[MUTED]\"?\"off\":\"on\")}' || echo '0 on'; " +
            "brightnessctl -m 2>/dev/null | awk -F, '{print substr($4, 1, length($4)-1)}' || echo '0'"
        ]
        running: true
        stdout: StdioCollector {
            onStreamFinished: {
                let lines = this.text.trim().split("\n");
                if (lines.length >= 6) {
                    if (window.batCapacity !== parseInt(lines[0])) {
                        window.batCapacity = parseInt(lines[0]);
                        window.animCapacity = window.batCapacity;
                    }
                    window.batStatus = lines[1];
                    window.powerProfile = lines[2];
                    
                    let upParts = lines[3].split("h ");
                    if (upParts.length === 2) {
                        window.upHours = parseInt(upParts[0]) || 0;
                        window.upMins = parseInt(upParts[1].replace("m", "")) || 0;
                    }

                    if (!window.isDraggingVol) {
                        let volParts = (lines[4] || "0 on").trim().split(" ");
                        window.sysVolume = parseInt(volParts[0]) || 0;
                        window.sysMuted = (volParts[1] === "off");
                    }
                    
                    if (!window.isDraggingBri) {
                        window.sysBrightness = parseInt(lines[5]) || 0;
                    }
                }
            }
        }
    }
    Timer {
        interval: 1500; running: true; repeat: true; triggeredOnStart: true;
        onTriggered: sysPoller.running = true
    }

    property real globalOrbitAngle: 0
    NumberAnimation on globalOrbitAngle {
        from: 0; to: Math.PI * 2; duration: 90000; loops: Animation.Infinite; running: true
    }

    // --- ENHANCED STARTUP ANIMATION STATES ---
    property real introMain: 0
    property real introTop: 0
    property real introNotifs: 0
    property real introCore: 0
    property real introSliders: 0
    property real introActions: 0
    property real introProfiles: 0

    ParallelAnimation {
        running: true

        // Base window fades, scales, and lifts
        NumberAnimation { target: window; property: "introMain"; from: 0; to: 1.0; duration: 800; easing.type: Easing.OutQuart }

        // Top bar drops in
        SequentialAnimation {
            PauseAnimation { duration: 100 }
            NumberAnimation { target: window; property: "introTop"; from: 0; to: 1.0; duration: 800; easing.type: Easing.OutBack; easing.overshoot: 1.0 }
        }

        // Notification List cascades in smoothly
        SequentialAnimation {
            PauseAnimation { duration: 150 }
            NumberAnimation { target: window; property: "introNotifs"; from: 0; to: 1.0; duration: 850; easing.type: Easing.OutQuart }
        }

        // Central core pops out and breathes
        SequentialAnimation {
            PauseAnimation { duration: 250 }
            NumberAnimation { target: window; property: "introCore"; from: 0; to: 1.0; duration: 900; easing.type: Easing.OutBack; easing.overshoot: 1.2 }
        }

        // Hardware sliders slide up
        SequentialAnimation {
            PauseAnimation { duration: 350 }
            NumberAnimation { target: window; property: "introSliders"; from: 0; to: 1.0; duration: 800; easing.type: Easing.OutQuart }
        }

        // Actions waterfall
        SequentialAnimation {
            PauseAnimation { duration: 450 }
            NumberAnimation { target: window; property: "introActions"; from: 0; to: 1.0; duration: 800; easing.type: Easing.OutExpo }
        }

        // Power profiles finish the wave
        SequentialAnimation {
            PauseAnimation { duration: 550 }
            NumberAnimation { target: window; property: "introProfiles"; from: 0; to: 1.0; duration: 850; easing.type: Easing.OutBack; easing.overshoot: 0.8 }
        }
    }

    ParallelAnimation {
        id: exitAnim
        NumberAnimation { target: window; property: "introMain"; to: 0; duration: 400; easing.type: Easing.InQuart }
        NumberAnimation { target: window; property: "introTop"; to: 0; duration: 300; easing.type: Easing.InQuart }
        NumberAnimation { target: window; property: "introNotifs"; to: 0; duration: 300; easing.type: Easing.InQuart }
        NumberAnimation { target: window; property: "introCore"; to: 0; duration: 350; easing.type: Easing.InQuart }
        NumberAnimation { target: window; property: "introSliders"; to: 0; duration: 250; easing.type: Easing.InQuart }
        NumberAnimation { target: window; property: "introActions"; to: 0; duration: 200; easing.type: Easing.InQuart }
        NumberAnimation { target: window; property: "introProfiles"; to: 0; duration: 150; easing.type: Easing.InQuart }
    }


    // -------------------------------------------------------------------------
    // UI LAYOUT
    // -------------------------------------------------------------------------
    Item {
        anchors.fill: parent
        scale: 0.92 + (0.08 * introMain)
        opacity: introMain
        transform: Translate { y: window.s(15) * (1 - introMain) }

        // Unified Outer Background
        Rectangle {
            anchors.fill: parent
            // liquid glass (config/hyprliquid.json): corner must match corner_radius; near-clear fill: the glass tint does the colouring
            radius: 48
            color: Qt.rgba(window.base.r, window.base.g, window.base.b, 0.06)
            border.color: window.surface0 
            border.width: 0
            clip: true

            

            RowLayout {
                anchors.fill: parent
                spacing: window.s(15) // Seamless separation instead of a line

                // ==========================================
                // RIGHT SIDE: HARDWARE & BATTERY CORE
                // ==========================================
                Item {
                    Layout.preferredWidth: window.s(480)
                    Layout.fillHeight: true

                    // Radar Rings (Centered on the Hardware Panel so it aligns perfectly with the gauge)
                    Item {
                        anchors.fill: parent
                        
                        Repeater {
                            model: 3
                            Rectangle {
                                anchors.centerIn: parent
                                anchors.verticalCenterOffset: window.s(-70)
                                width: window.s(320) + (index * window.s(170))
                                height: width
                                radius: width / 2
                                color: "transparent"
                                border.color: window.ambientSecondary
                                border.width: 1
                                Behavior on border.color { ColorAnimation { duration: 1000 } }
                                opacity: 0.06 - (index * 0.02)
                            }
                        }
                    }

                    // CENTRAL CORE & BATTERY RING 
                    Item {
                        anchors.fill: parent
                        z: 1
                        
                        opacity: introCore
                        transform: Translate { y: window.s(25) * (1 - introCore) }
                        scale: 0.9 + (0.1 * introCore)

                        // CLEAN OUTSIDE GLOW HALO
                        Rectangle {
                            anchors.centerIn: centralCore
                            width: centralCore.width + window.s(45)
                            height: width
                            radius: width / 2
                            color: centralCore.isDangerState ? window.red : window.ambientPrimary
                            opacity: centralCore.isDangerState ? 0.25 : 0.15
                            z: 0 
                            Behavior on color { ColorAnimation { duration: 400 } }
                            SequentialAnimation on scale {
                                loops: Animation.Infinite; running: true
                                NumberAnimation { to: heroMa.containsMouse ? 1.15 : 1.08; duration: heroMa.containsMouse ? 800 : 2000; easing.type: Easing.InOutSine }
                                NumberAnimation { to: 1.0; duration: heroMa.containsMouse ? 800 : 2000; easing.type: Easing.InOutSine }
                            }
                        }

                        Rectangle {
                            id: centralCore
                            width: window.s(260)
                            height: width
                            anchors.centerIn: parent
                            anchors.verticalCenterOffset: window.s(-70)
                            radius: width / 2
                            z: 1
                            
                            property bool isDangerState: !window.isCharging && window.batCapacity < 15
                            
                            SequentialAnimation on scale {
                                loops: Animation.Infinite
                                running: true
                                NumberAnimation { 
                                    to: heroMa.containsMouse ? 1.05 : (centralCore.isDangerState ? 1.04 : 1.01)
                                    duration: heroMa.containsMouse ? 1200 : (centralCore.isDangerState ? 600 : 2500)
                                    easing.type: Easing.InOutSine 
                                }
                                NumberAnimation { 
                                    to: 1.0
                                    duration: heroMa.containsMouse ? 1200 : (centralCore.isDangerState ? 600 : 2500)
                                    easing.type: Easing.InOutSine 
                                }
                            }

                            gradient: Gradient {
                                orientation: Gradient.Vertical
                                GradientStop { position: 0.0; color: window.surface0 }
                                GradientStop { position: 1.0; color: window.base }
                            }

                            Rectangle {
                                anchors.fill: parent
                                radius: width / 2
                                color: window.maroon
                                opacity: centralCore.isDangerState ? 0.15 : 0.0
                                Behavior on opacity { NumberAnimation { duration: 1000 } }
                                SequentialAnimation on opacity {
                                    loops: Animation.Infinite; running: centralCore.isDangerState
                                    NumberAnimation { to: 0.25; duration: 600; easing.type: Easing.InOutSine }
                                    NumberAnimation { to: 0.15; duration: 600; easing.type: Easing.InOutSine }
                                }
                            }

                            Item {
                                anchors.fill: parent
                                
                                property real textPulse: 0.0
                                SequentialAnimation on textPulse {
                                    loops: Animation.Infinite; running: true
                                    NumberAnimation { from: 0.0; to: 1.0; duration: 1200; easing.type: Easing.InOutSine }
                                    NumberAnimation { from: 1.0; to: 0.0; duration: 1200; easing.type: Easing.InOutSine }
                                }
                                
                                property real pumpPhase: 0.0
                                NumberAnimation on pumpPhase {
                                    running: heroMa.containsMouse && window.isCharging
                                    loops: Animation.Infinite
                                    from: 0.0; to: 1.0; duration: 1200
                                    easing.type: Easing.InOutSine 
                                    onStopped: batCanvas.requestPaint()
                                }
                                
                                property real dischargePhase: 1.0
                                NumberAnimation on dischargePhase {
                                    running: heroMa.containsMouse && !window.isCharging
                                    loops: Animation.Infinite
                                    from: 1.0; to: 0.0; duration: 1600
                                    easing.type: Easing.InOutSine
                                    onStopped: batCanvas.requestPaint()
                                }
                                
                                onPumpPhaseChanged: { if(heroMa.containsMouse && window.isCharging) batCanvas.requestPaint() }
                                onDischargePhaseChanged: { if(heroMa.containsMouse && !window.isCharging) batCanvas.requestPaint() }
                                
                                Canvas {
                                    id: batCanvas
                                    anchors.fill: parent
                                    rotation: 180 
                                    
                                    onPaint: {
                                        var ctx = getContext("2d");
                                        ctx.clearRect(0, 0, width, height);
                                        
                                        var centerX = width / 2;
                                        var centerY = height / 2;
                                        var radius = (width / 2) - window.s(18); 
                                        var endAngle = (window.animCapacity / 100) * 2 * Math.PI;
                                        
                                        ctx.lineCap = "round";
                                        
                                        ctx.lineWidth = window.s(8);
                                        ctx.beginPath();
                                        ctx.arc(centerX, centerY, radius, 0, 2 * Math.PI);
                                        ctx.strokeStyle = window.surface1;
                                        ctx.stroke();
                                        
                                        var fillGrad = ctx.createLinearGradient(0, height, width, 0);
                                        fillGrad.addColorStop(0, window.batColorStart.toString());
                                        fillGrad.addColorStop(1, window.batColorEnd.toString());

                                        ctx.globalAlpha = 1.0;
                                        ctx.lineWidth = window.s(14);
                                        ctx.beginPath();
                                        ctx.arc(centerX, centerY, radius, 0, endAngle);
                                        ctx.strokeStyle = fillGrad;
                                        ctx.stroke();
                                        
                                        if (heroMa.containsMouse && endAngle > 0.1) {
                                            if (window.isCharging) {
                                                var surgeAngle = parent.pumpPhase * (endAngle + 0.6) - 0.3;
                                                if (surgeAngle > 0 && surgeAngle < endAngle) {
                                                    var sStart = Math.max(0, surgeAngle - 0.4);
                                                    var sEnd = Math.min(endAngle, surgeAngle + 0.4);
                                                    ctx.beginPath();
                                                    ctx.arc(centerX, centerY, radius, sStart, sEnd);
                                                    ctx.lineWidth = window.s(22);
                                                    ctx.strokeStyle = window.batColorStart.toString();
                                                    ctx.globalAlpha = 0.5 * Math.sin(parent.pumpPhase * Math.PI);
                                                    ctx.stroke();

                                                    sStart = Math.max(0, surgeAngle - 0.2);
                                                    sEnd = Math.min(endAngle, surgeAngle + 0.2);
                                                    ctx.beginPath();
                                                    ctx.arc(centerX, centerY, radius, sStart, sEnd);
                                                    ctx.lineWidth = window.s(28);
                                                    ctx.strokeStyle = window.batColorEnd.toString();
                                                    ctx.globalAlpha = 0.8 * Math.sin(parent.pumpPhase * Math.PI);
                                                    ctx.stroke();
                                                }
                                                
                                                if (parent.pumpPhase > 0.7) {
                                                    var flarePhase = (parent.pumpPhase - 0.7) / 0.3;
                                                    var hitX = centerX + Math.cos(endAngle) * radius;
                                                    var hitY = centerY + Math.sin(endAngle) * radius;
                                                    ctx.beginPath();
                                                    ctx.arc(hitX, hitY, window.s(7) + (flarePhase * window.s(15)), 0, 2*Math.PI);
                                                    ctx.fillStyle = window.batColorEnd.toString();
                                                    ctx.globalAlpha = (1.0 - flarePhase) * 0.6;
                                                    ctx.fill();
                                                }
                                            } else {
                                                var drainCenter = parent.dischargePhase * endAngle;
                                                for (var d = 0; d < 2; d++) {
                                                    var dSpread = 0.2 + (d * 0.15);
                                                    var dStart = Math.max(0, drainCenter - dSpread);
                                                    var dEnd = Math.min(endAngle, drainCenter + dSpread);
                                                    
                                                    if (dStart < dEnd) {
                                                        ctx.beginPath();
                                                        ctx.arc(centerX, centerY, radius, dStart, dEnd);
                                                        ctx.lineWidth = window.s(14) + (1 - d) * window.s(2);
                                                        ctx.strokeStyle = window.batColorEnd.toString();
                                                        ctx.globalAlpha = 0.2 * Math.sin(parent.dischargePhase * Math.PI);
                                                        ctx.stroke();
                                                    }
                                                }
                                            }
                                        }
                                    }
                                }

                                ColumnLayout {
                                    anchors.centerIn: parent
                                    spacing: window.s(-2)
                                    
                                    RowLayout {
                                        Layout.alignment: Qt.AlignHCenter
                                        spacing: window.s(8)
                                        
                                        Text {
                                            font.family: "Maple Mono Normal NF"
                                            font.pixelSize: window.s(28)
                                            color: window.batColorStart
                                            text: window.isCharging ? "󰂄" : (window.batCapacity > 20 ? "󰁹" : "󰂃")
                                            Behavior on color { ColorAnimation { duration: 400 } }
                                        }
                                        
                                        Text {
                                            font.family: "SF Pro Display"
                                            font.weight: Font.Black
                                            font.pixelSize: window.s(54)
                                            color: window.text
                                            text: Math.round(window.animCapacity) + "%" 
                                        }
                                    }

                                    Text {
                                        Layout.alignment: Qt.AlignHCenter
                                        font.family: "SF Pro Display"
                                        font.weight: Font.Bold
                                        font.pixelSize: window.s(13)
                                        
                                        color: window.isCharging 
                                                ? Qt.tint(window.green, Qt.rgba(1, 1, 1, parent.textPulse * 0.4)) 
                                                : (centralCore.isDangerState ? Qt.tint(window.red, Qt.rgba(1, 1, 1, parent.textPulse * 0.3)) : window.subtext0)
                                        
                                        text: window.batStatus.toUpperCase()
                                        Behavior on color { ColorAnimation { duration: 300 } }
                                    }
                                }
                            }

                            MouseArea {
                                id: heroMa
                                anchors.fill: centralCore 
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onEntered: batCanvas.requestPaint()
                                onExited: batCanvas.requestPaint()
                            }
                        }

                        // BOTTOM DOCKS
                        ColumnLayout {
                            anchors.bottom: parent.bottom
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.margins: window.s(25)
                            spacing: window.s(15)

                            // 1. HARDWARE CONTROLS DOCK (Sliders)
                            Rectangle {
                                Layout.fillWidth: true
                                Layout.preferredHeight: window.s(60)
                                radius: window.s(14)
                                color: window.surface0
                                border.color: window.surface1
                                border.width: 1

                                opacity: introSliders
                                transform: Translate { y: window.s(20) * (1.0 - introSliders) }

                                ColumnLayout {
                                    anchors.fill: parent
                                    anchors.margins: window.s(14)
                                    spacing: window.s(12)

                                    // Brightness Slider
                                    RowLayout {
                                        Layout.fillWidth: true
                                        spacing: window.s(15)

                                        Item {
                                            Layout.preferredWidth: window.s(32)
                                            Layout.preferredHeight: window.s(32)
                                            Text {
                                                anchors.centerIn: parent
                                                text: window.sysBrightness > 66 ? "󰃠" : (window.sysBrightness > 33 ? "󰃟" : "󰃞")
                                                font.family: "Maple Mono Normal NF"
                                                font.pixelSize: window.s(22)
                                                color: window.ambientPrimary
                                                Behavior on color { ColorAnimation { duration: 200 } }
                                            }
                                        }

                                        Item {
                                            Layout.fillWidth: true
                                            height: window.s(18)
                                            
                                            Timer {
                                                id: briCmdThrottle
                                                interval: 50
                                                property int targetPct: -1
                                                onTriggered: {
                                                    if (targetPct >= 0) {
                                                        Quickshell.execDetached(["brightnessctl", "set", targetPct + "%"]);
                                                        targetPct = -1;
                                                    }
                                                }
                                            }

                                            Rectangle {
                                                anchors.fill: parent
                                                radius: window.s(9)
                                                color: window.surface1
                                                border.color: window.surface2
                                                border.width: 1
                                                clip: true

                                                Rectangle {
                                                    height: parent.height
                                                    width: parent.width * (window.sysBrightness / 100)
                                                    radius: window.s(9)
                                                    opacity: briMa.containsMouse ? 1.0 : 0.85
                                                    Behavior on opacity { NumberAnimation { duration: 200 } }
                                                    Behavior on width { enabled: !window.isDraggingBri; NumberAnimation { duration: 200; easing.type: Easing.OutQuint } }

                                                    gradient: Gradient {
                                                        orientation: Gradient.Horizontal
                                                        GradientStop { position: 0.0; color: window.batColorStart; Behavior on color { ColorAnimation { duration: 300 } } }
                                                        GradientStop { position: 1.0; color: window.batColorEnd; Behavior on color { ColorAnimation { duration: 300 } } }
                                                    }
                                                }
                                            }
                                            MouseArea {
                                                id: briMa
                                                anchors.fill: parent
                                                hoverEnabled: true
                                                cursorShape: Qt.PointingHandCursor
                                                onPressed: (mouse) => { briSyncDelay.stop(); window.isDraggingBri = true; updateBri(mouse.x); }
                                                onPositionChanged: (mouse) => { if (pressed) updateBri(mouse.x); }
                                                onReleased: { briSyncDelay.restart(); }
                                                
                                                function updateBri(mx) {
                                                    let pct = Math.max(0, Math.min(100, Math.round((mx / width) * 100)));
                                                    window.sysBrightness = pct; 
                                                    briCmdThrottle.targetPct = pct;
                                                    if (!briCmdThrottle.running) briCmdThrottle.start();
                                                }
                                            }
                                        }
                                    }
                                }
                            }

                            // 3. POWER PROFILES DOCK
                            Rectangle {
                                Layout.fillWidth: true
                                Layout.preferredHeight: window.s(54)
                                radius: window.s(14)
                                color: window.surface0 
                                border.color: window.surface1
                                border.width: 1

                                opacity: introProfiles
                                transform: Translate { y: window.s(20) * (1.0 - introProfiles) }
                                
                                Rectangle {
                                    id: sliderPill
                                    width: (parent.width - window.s(2)) / 3 
                                    height: parent.height - window.s(2)
                                    y: window.s(1)
                                    radius: window.s(10)
                                    x: {
                                        if (window.powerProfile === "performance") return window.s(1);
                                        if (window.powerProfile === "balanced") return width + window.s(1);
                                        return (width * 2) + window.s(1);
                                    }
                                    
                                    Behavior on x { NumberAnimation { duration: 400; easing.type: Easing.OutBack; easing.overshoot: 1.2 } }
                                    
                                    gradient: Gradient {
                                        orientation: Gradient.Horizontal
                                        GradientStop { position: 0.0; color: window.profileStart; Behavior on color { ColorAnimation{duration:400} } }
                                        GradientStop { position: 1.0; color: window.profileEnd; Behavior on color { ColorAnimation{duration:400} } }
                                    }
                                }

                                RowLayout {
                                    anchors.fill: parent
                                    spacing: 0
                                    
                                    Repeater {
                                        model: ListModel {
                                            ListElement { name: "performance"; icon: "󰓅"; label: "Perform" } 
                                            ListElement { name: "balanced"; icon: "󰗑"; label: "Balance" }   
                                            ListElement { name: "power-saver"; icon: "󰌪"; label: "Saver" } 
                                        }
                                        
                                        delegate: Item {
                                            Layout.fillWidth: true
                                            Layout.fillHeight: true
                                            
                                            RowLayout {
                                                anchors.centerIn: parent
                                                spacing: window.s(8)
                                                Text {
                                                    font.family: "Maple Mono Normal NF"; font.pixelSize: window.s(18)
                                                    color: window.powerProfile === name ? window.crust : (profileMa.containsMouse ? window.text : window.subtext0)
                                                    text: icon
                                                    Behavior on color { ColorAnimation { duration: 200 } }
                                                }
                                                Text {
                                                    font.family: "SF Pro Display"; font.weight: Font.Black; font.pixelSize: window.s(13)
                                                    color: window.powerProfile === name ? window.crust : (profileMa.containsMouse ? window.text : window.subtext0)
                                                    text: label
                                                    Behavior on color { ColorAnimation { duration: 200 } }
                                                }
                                            }
                                            
                                            MouseArea {
                                                id: profileMa
                                                anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                                onClicked: { Quickshell.execDetached(["powerprofilesctl", "set", name]); sysPoller.running = true; }
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
