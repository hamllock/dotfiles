import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import Quickshell.Widgets
import Quickshell.Wayland
import Quickshell.Services.SystemTray
import Quickshell.Hyprland
import QtQuick.Shapes
import Qt5Compat.GraphicalEffects

Variants {
    id: topBarRoot
    property var notifModel: null
    model: Quickshell.screens

    delegate: Component {
        PanelWindow {
            id: barWindow
            // matches the topbar_blur layerrule in config/rules.lua
            WlrLayershell.namespace: "qs-topbar"
            property bool pendingReload: false
            
	    Caching { id: paths }
        
            IpcHandler {
                target: "topbar"
                function forceReload() {
                    Quickshell.reload(true) 
                }
                function queueReload() {
                    if (!barWindow.isSettingsOpen) {
                        Quickshell.reload(true)
                    } else {
                        barWindow.pendingReload = true
                    }
                }
            }

            required property var modelData
            screen: modelData

            anchors {
                top: true
                left: true
                right: true
            }

            Scaler {
                id: scaler
                currentWidth: barWindow.width
            }

            property real baseScale: scaler.baseScale

            function s(val) { 
                return scaler.s(val); 
            }

            function formatSpeed(bytes) {
                if (bytes === undefined || isNaN(bytes) || bytes <= 0) return "0 B/s";
                let units = ["B/s", "KB/s", "MB/s", "GB/s"];
                let i = 0;
                while (bytes >= 1024 && i < units.length - 1) {
                    bytes /= 1024;
                    i++;
                }
                if (i === 0) {
                    return Math.round(bytes) + " " + units[i];
                } else {
                    return bytes.toFixed(1) + " " + units[i];
                }
            }

            property int barHeight: s(40)

            height: barHeight
            // floating glass pill; its rounding is corner_radius in config/hyprliquid.json
            margins { top: s(8); bottom: 0; left: s(8); right: s(8) }
            exclusiveZone: barHeight 
            color: "transparent"

            MatugenColors {
                id: mocha
            }

            property bool isRecording: false
            
            
            property int workspaceCount: 8
            
            property string activeWidget: "" 
            property bool isSettingsOpen: activeWidget === "settings"

            onIsSettingsOpenChanged: {
                if (!barWindow.isSettingsOpen && barWindow.pendingReload) {
                    barWindow.pendingReload = false;
                    Quickshell.reload(true);
                }
            }

            Process {
                id: widgetPoller
                command: ["bash", "-c", "cat " + paths.runDir + "/current_widget 2>/dev/null || echo ''"]
                running: true
                stdout: StdioCollector {
                    onStreamFinished: {
                        let txt = this.text.trim();
                        if (barWindow.activeWidget !== txt) barWindow.activeWidget = txt;
                    }
                }
            }

            Process {
                id: widgetWatcher
                command: ["bash", "-c", "while [ ! -f " + paths.runDir + "/current_widget ]; do sleep 1; done; inotifywait -qq -e modify,close_write " + paths.runDir + "/current_widget"]
                running: true
                onExited: {
                    widgetPoller.running = false;
                    widgetPoller.running = true;
                    running = false;
                    running = true;
                }
            }
            
            Process {
                id: recPoller
                command: ["bash", "-c", "if [ -s " + paths.getCacheDir("recording") + "/rec_pid ] && kill -0 $(cat " + paths.getCacheDir("recording") + "/rec_pid) 2>/dev/null; then echo '1'; else echo '0'; fi"]
                stdout: StdioCollector {
                    onStreamFinished: {
                        barWindow.isRecording = (this.text.trim() === "1");
                    }
                }
            }

            Process {
 	    	id: recWatcher
 		running: true
 		command: ["bash", "-c", "setpriv --pdeathsig KILL inotifywait -qq -e create,delete,modify,close_write " + paths.getCacheDir("recording") + "/ 2>/dev/null || sleep 2"]
 	        onExited: {
 	        	recPoller.running = false;
 	         	recPoller.running = true;
 	         	running = false;
 	         	running = true;
 	        }
	    }	  
	                
            Process {
                id: settingsReader
                command: ["bash", "-c", "cat ~/.config/hypr/settings.json 2>/dev/null || echo '{}'"]
                running: true
                stdout: StdioCollector {
                    onStreamFinished: {
                        try {
                            if (this.text && this.text.trim().length > 0 && this.text.trim() !== "{}") {
                                let parsed = JSON.parse(this.text);
                                
                                
                                if (parsed.workspaceCount !== undefined && barWindow.workspaceCount !== parsed.workspaceCount) {
                                    barWindow.workspaceCount = parsed.workspaceCount;
                                    wsDaemon.running = false;
                                    wsDaemon.running = true;
                                }
                            }
                        } catch (e) {}
                    }
                }
            }

            Process {
                id: settingsWatcher
                command: ["bash", "-c", "while [ ! -f ~/.config/hypr/settings.json ]; do sleep 1; done; inotifywait -qq -e modify,close_write ~/.config/hypr/settings.json"]
                running: true
                stdout: StdioCollector {
                    onStreamFinished: {
                        settingsReader.running = false;
                        settingsReader.running = true;
                        
                        settingsWatcher.running = false;
                        settingsWatcher.running = true;
                    }
                }
            }
            
            property bool isDesktop: false
            property string ethStatus: "Ethernet"

            Process {
                id: chassisDetector
                running: true
                command: ["bash", "-c", "if ls /sys/class/power_supply/BAT* 1> /dev/null 2>&1; then echo 'laptop'; else echo 'desktop'; fi"]
                stdout: StdioCollector {
                    onStreamFinished: {
                        barWindow.isDesktop = (this.text.trim() === "desktop");
                    }
                }
            }

            property bool isStartupReady: false
            Timer { interval: 10; running: true; onTriggered: barWindow.isStartupReady = true }
            
            property bool startupCascadeFinished: false
            Timer { interval: 1000; running: true; onTriggered: barWindow.startupCascadeFinished = true }
            
            property bool fastPollerLoaded: false
            property bool isDataReady: fastPollerLoaded
            Timer { interval: 600; running: true; onTriggered: barWindow.isDataReady = true }
            
            property string timeStr: ""
            property string fullDateStr: ""
            property int typeInIndex: 0
            property string dateStr: fullDateStr.substring(0, typeInIndex)

            property string weatherIcon: ""
            property string weatherTemp: "--°"
            property string weatherHex: mocha.yellow
            
            property string wifiStatus: "Off"
            property string wifiIcon: "󰤮"
            property string wifiSsid: ""
            
            property string btStatus: "Off"
            property string btIcon: "󰂲"
            property string btDevice: ""
            
            property string volPercent: "0%"
            property string volIcon: "󰕾"
            property bool isMuted: false
            
            property string batPercent: "100%"
            property string batIcon: "󰁹"
            property string batStatus: "Unknown"
            
            property string kbLayout: "us"
            
            ListModel { 
                id: workspacesModel 
                property int activeIndex: 0
            }
            
            property var musicData: { "status": "Stopped", "title": "", "artUrl": "", "timeStr": "" }

            property string displayTitle: ""
            property string displayTime: ""
            property string displayArtUrl: ""

            onMusicDataChanged: {
                if (musicData && musicData.status !== "Stopped" && musicData.title !== "") {
                    displayTitle = musicData.title;
                    displayTime = musicData.timeStr;
                    displayArtUrl = musicData.artUrl;
                }
            }

            property bool isMediaActive: barWindow.musicData.status !== "Stopped" && barWindow.musicData.title !== ""
            property bool isWifiOn: barWindow.wifiStatus.toLowerCase() === "enabled" || barWindow.wifiStatus.toLowerCase() === "on"
            property bool isBtOn: barWindow.btStatus.toLowerCase() === "enabled" || barWindow.btStatus.toLowerCase() === "on"
            property string warpStatus: "Disconnected"
            property bool isWarpOn: barWindow.warpStatus === "Connected"
            property bool showEthernet: barWindow.ethStatus === "Connected" || (barWindow.isDesktop && !barWindow.isWifiOn)
            
            property bool isSoundActive: !barWindow.isMuted && parseInt(barWindow.volPercent) > 0
            property int batCap: parseInt(barWindow.batPercent) || 0
            property bool isCharging: barWindow.batStatus === "Charging" || barWindow.batStatus === "Full"
            
            property color batDynamicColor: {
                if (isCharging) return mocha.green;
                if (batCap <= 20) return mocha.red;
                return mocha.text; 
            }

            Process {
                id: wsDaemon
                command: ["bash", "-c", "~/.config/hypr/scripts/workspaces.sh"]
                running: true
            }

            Process {
		id: wsReader
		running: true
                command: ["cat", paths.getRunDir("workspaces") + "/workspaces.json"]
                stdout: StdioCollector {
                    onStreamFinished: {
                        let txt = this.text.trim();
                        if (txt !== "") {
                            try { 
                                let newData = JSON.parse(txt);
                                
                                while (workspacesModel.count < newData.length) {
                                    workspacesModel.append({ "wsId": "", "wsState": "" });
                                }
                                
                                while (workspacesModel.count > newData.length) {
                                    workspacesModel.remove(workspacesModel.count - 1);
                                }
                                
                                let newActive = -1;

                                for (let i = 0; i < newData.length; i++) {
                                    if (newData[i].state === "active") newActive = i;

                                    if (workspacesModel.get(i).wsState !== newData[i].state) {
                                        workspacesModel.setProperty(i, "wsState", newData[i].state);
                                    }
                                    if (workspacesModel.get(i).wsId !== newData[i].id.toString()) {
                                        workspacesModel.setProperty(i, "wsId", newData[i].id.toString());
                                    }
                                }

                                if (newActive !== -1 && workspacesModel.activeIndex !== newActive) {
                                    workspacesModel.activeIndex = newActive;
                                }

                            } catch(e) {}
                        }
                    }
                }
            }

            Process {
                id: wsWatcher
                running: true
                command: ["bash", "-c", "inotifywait -qq -e close_write,modify " + paths.getRunDir("workspaces") + "/workspaces.json"]
                onExited: {
                    wsReader.running = false;
                    wsReader.running = true;
                    running = false;
                    running = true;
                }
            }

            Process {
                id: musicForceRefresh
                running: false
                command: ["bash", "-c", "bash ~/.config/hypr/scripts/quickshell/music/music_info.sh | tee " + paths.getRunDir("music") + "/music_info.json"]
                stdout: StdioCollector {
                    onStreamFinished: {
                        let txt = this.text.trim();
                        if (txt !== "") {
                            try { barWindow.musicData = JSON.parse(txt); } catch(e) {}
                        }
                    }
                }
            }

            Timer {
                interval: 1000
                running: barWindow.musicData !== null && barWindow.musicData.status === "Playing"
                repeat: true
                onTriggered: {
                    if (!barWindow.musicData || barWindow.musicData.status !== "Playing") return;
                    if (!barWindow.musicData.timeStr || barWindow.musicData.timeStr === "") return;

                    let parts = barWindow.musicData.timeStr.split(" / ");
                    if (parts.length !== 2) return;

                    let posParts = parts[0].split(":").map(Number);
                    let lenParts = parts[1].split(":").map(Number);

                    let posSecs = (posParts.length === 3) 
                        ? (posParts[0] * 3600 + posParts[1] * 60 + posParts[2]) 
                        : (posParts[0] * 60 + posParts[1]);

                    let lenSecs = (lenParts.length === 3) 
                        ? (lenParts[0] * 3600 + lenParts[1] * 60 + lenParts[2]) 
                        : (lenParts[0] * 60 + lenParts[1]);

                    if (isNaN(posSecs) || isNaN(lenSecs)) return;

                    posSecs++;
                    if (posSecs > lenSecs) posSecs = lenSecs;

                    let newPosStr = "";
                    if (posParts.length === 3) {
                        let h = Math.floor(posSecs / 3600);
                        let m = Math.floor((posSecs % 3600) / 60);
                        let s = posSecs % 60;
                        newPosStr = h + ":" + (m < 10 ? "0" : "") + m + ":" + (s < 10 ? "0" : "") + s;
                    } else {
                        let m = Math.floor(posSecs / 60);
                        let s = posSecs % 60;
                        newPosStr = (m < 10 ? "0" : "") + m + ":" + (s < 10 ? "0" : "") + s;
                    }

                    let newData = Object.assign({}, barWindow.musicData);
                    newData.timeStr = newPosStr + " / " + parts[1];
                    newData.positionStr = newPosStr;
                    if (lenSecs > 0) newData.percent = (posSecs / lenSecs) * 100;
                    
                    barWindow.musicData = newData;
                }
            }

            Process {
                id: mprisWatcher
                running: false
                command: ["bash", "-c", "setpriv --pdeathsig KILL dbus-monitor --session \"type='signal',interface='org.freedesktop.DBus.Properties',member='PropertiesChanged',arg0='org.mpris.MediaPlayer2.Player'\" \"type='signal',interface='org.mpris.MediaPlayer2.Player',member='Seeked'\" 2>/dev/null | setpriv --pdeathsig KILL grep -m 1 'member=' > /dev/null || sleep 2"]
                onExited: {
                    musicForceRefresh.running = false;
                    musicForceRefresh.running = true;
                    running = false;
                    running = true;
                }
            }

            Timer {
                id: artRetryTimer
                interval: 500
                repeat: true
                running: false
                onTriggered: {
                    musicForceRefresh.running = false;
                    musicForceRefresh.running = true;
                }
            }

            Process {
                id: kbPoller; running: true
                command: ["bash", "-c", "~/.config/hypr/scripts/quickshell/watchers/kb_fetch.sh"]
                stdout: StdioCollector {
                    onStreamFinished: {
                        let txt = this.text.trim();
                        if (txt !== "" && barWindow.kbLayout !== txt) barWindow.kbLayout = txt;
                        kbWaiter.running = false;
                        kbWaiter.running = true;
                        barWindow.fastPollerLoaded = true; 
                    }
                }
            }
            Process { id: kbWaiter; command: ["bash", "-c", "~/.config/hypr/scripts/quickshell/watchers/kb_wait.sh"]; onExited: { kbPoller.running = false; kbPoller.running = true; } }

            Process {
                id: audioPoller; running: true
                command: ["bash", "-c", "~/.config/hypr/scripts/quickshell/watchers/audio_fetch.sh"]
                stdout: StdioCollector {
                    onStreamFinished: {
                        let txt = this.text.trim();
                        if (txt !== "") {
                            try {
                                let data = JSON.parse(txt);
                                let newVol = data.volume.toString() + "%";
                                if (barWindow.volPercent !== newVol) barWindow.volPercent = newVol;
                                if (barWindow.volIcon !== data.icon) barWindow.volIcon = data.icon;
                                let newMuted = (data.is_muted === "true");
                                if (barWindow.isMuted !== newMuted) barWindow.isMuted = newMuted;
                            } catch(e) {}
                        }
                        audioWaiter.running = false;
                        audioWaiter.running = true;
                    }
                }
            }
            Process { id: audioWaiter; command: ["bash", "-c", "~/.config/hypr/scripts/quickshell/watchers/audio_wait.sh"]; onExited: { audioPoller.running = false; audioPoller.running = true; } }

            Process {
                id: networkPoller; running: true
                command: ["bash", "-c", "~/.config/hypr/scripts/quickshell/watchers/network_fetch.sh"]
                stdout: StdioCollector {
                    onStreamFinished: {
                        let txt = this.text.trim();
                        if (txt !== "") {
                            try {
                                let data = JSON.parse(txt);
                                if (barWindow.wifiStatus !== data.status) barWindow.wifiStatus = data.status;
                                if (barWindow.wifiIcon !== data.icon) barWindow.wifiIcon = data.icon;
                                if (barWindow.wifiSsid !== data.ssid) barWindow.wifiSsid = data.ssid;
                                if (barWindow.ethStatus !== data.eth_status) barWindow.ethStatus = data.eth_status;
                            } catch(e) {}
                        }
                        networkWaiter.running = false;
                        networkWaiter.running = true;
                    }
                }
            }
            Process { id: networkWaiter; command: ["bash", "-c", "~/.config/hypr/scripts/quickshell/watchers/network_wait.sh"]; onExited: { networkPoller.running = false; networkPoller.running = true; } }

            Process {
                id: btPoller; running: true
                command: ["bash", "-c", "~/.config/hypr/scripts/quickshell/watchers/bt_fetch.sh"]
                stdout: StdioCollector {
                    onStreamFinished: {
                        let txt = this.text.trim();
                        if (txt !== "") {
                            try {
                                let data = JSON.parse(txt);
                                if (barWindow.btStatus !== data.status) barWindow.btStatus = data.status;
                                if (barWindow.btIcon !== data.icon) barWindow.btIcon = data.icon;
                                if (barWindow.btDevice !== data.connected) barWindow.btDevice = data.connected;
                            } catch(e) {}
                        }
                        btWaiter.running = false;
                        btWaiter.running = true;
                    }
                }
            }
            Process { id: btWaiter; command: ["bash", "-c", "~/.config/hypr/scripts/quickshell/watchers/bt_wait.sh"]; onExited: { btPoller.running = false; btPoller.running = true; } }

            Process {
                id: warpPoller; running: true
                command: ["bash", "-c", "warp-cli --accept-tos status 2>/dev/null | sed -n 's/^Status update: //p' | head -n1"]
                stdout: StdioCollector {
                    onStreamFinished: {
                        let txt = this.text.trim();
                        if (txt !== "" && barWindow.warpStatus !== txt) barWindow.warpStatus = txt;
                    }
                }
            }
            Timer { id: warpTimer; interval: 10000; running: true; repeat: true; onTriggered: { warpPoller.running = false; warpPoller.running = true; } }
            Process {
                id: warpToggler
                command: ["warp-cli", "--accept-tos", barWindow.isWarpOn ? "disconnect" : "connect"]
                onExited: { warpPoller.running = false; warpPoller.running = true; }
            }

            Process {
                id: batteryPoller; running: true
                command: ["bash", "-c", "~/.config/hypr/scripts/quickshell/watchers/battery_fetch.sh"]
                stdout: StdioCollector {
                    onStreamFinished: {
                        let txt = this.text.trim();
                        if (txt !== "") {
                            try {
                                let data = JSON.parse(txt);
                                let newBat = data.percent.toString() + "%";
                                if (barWindow.batPercent !== newBat) barWindow.batPercent = newBat;
                                if (barWindow.batIcon !== data.icon) barWindow.batIcon = data.icon;
                                if (barWindow.batStatus !== data.status) barWindow.batStatus = data.status;
                            } catch(e) {}
                        }
                        batteryWaiter.running = false;
                        batteryWaiter.running = true;
                    }
                }
            }
            Process { id: batteryWaiter; command: ["bash", "-c", "~/.config/hypr/scripts/quickshell/watchers/battery_wait.sh"]; onExited: { batteryPoller.running = false; batteryPoller.running = true; } }

            Process {
                id: weatherPoller
                command: ["bash", "-c", `
                    echo "$(~/.config/hypr/scripts/quickshell/calendar/weather.sh --current-icon)"
                    echo "$(~/.config/hypr/scripts/quickshell/calendar/weather.sh --current-temp)"
                    echo "$(~/.config/hypr/scripts/quickshell/calendar/weather.sh --current-hex)"
                `]
                stdout: StdioCollector {
                    onStreamFinished: {
                        let lines = this.text.trim().split("\n");
                        if (lines.length >= 3) {
                            barWindow.weatherIcon = lines[0];
                            barWindow.weatherTemp = lines[1];
                            barWindow.weatherHex = lines[2] || mocha.yellow;
                        }
                    }
                }
            }
            Timer { interval: 150000; running: true; repeat: true; triggeredOnStart: true; onTriggered: { weatherPoller.running = false; weatherPoller.running = true; } }


            Timer {
                interval: 1000; running: true; repeat: true; triggeredOnStart: true
                onTriggered: {
                    let d = new Date();
                    barWindow.timeStr = Qt.formatDateTime(d, "hh:mm AP");
                    barWindow.fullDateStr = Qt.formatDateTime(d, "dddd, MMMM dd");
                    if (barWindow.typeInIndex >= barWindow.fullDateStr.length) {
                        barWindow.typeInIndex = barWindow.fullDateStr.length;
                    }
                }
            }

            Timer {
                id: typewriterTimer
                interval: 40
                running: barWindow.isStartupReady && barWindow.typeInIndex < barWindow.fullDateStr.length
                repeat: true
                onTriggered: barWindow.typeInIndex += 1
            }

            Item {
                anchors.fill: parent
                
                Row {
                    id: leftContent
                    anchors.left: parent.left
                    anchors.leftMargin: barWindow.s(8)
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: barWindow.s(4)

                    // GitHub avatar (dash/github_avatar.sh): click toggles the dash (SUPER+G)
                    Item {
                        id: ghAvatar
                        property string path: ""
                        width: path !== "" ? barWindow.s(34) : 0
                        height: barWindow.barHeight
                        visible: path !== ""

                        Process {
                            id: ghAvatarFetch
                            command: ["bash", Quickshell.env("HOME") + "/.config/hypr/scripts/quickshell/dash/github_avatar.sh"]
                            running: true
                            stdout: StdioCollector {
                                onStreamFinished: { let p = this.text.trim(); if (p !== "") ghAvatar.path = p; }
                            }
                        }
                        Timer { interval: 6 * 3600 * 1000; running: true; repeat: true; onTriggered: ghAvatarFetch.running = true }

                        opacity: path !== "" ? 1 : 0
                        transform: Translate { y: ghAvatar.path !== "" ? 0 : barWindow.s(15); Behavior on y { NumberAnimation { duration: 500; easing.type: Easing.OutBack } } }
                        Behavior on opacity { NumberAnimation { duration: 400; easing.type: Easing.OutCubic } }

                        Item {
                            anchors.centerIn: parent
                            width: barWindow.s(24); height: width
                            scale: ghAvatarMouse.containsMouse ? 1.12 : 1.0
                            Behavior on scale { NumberAnimation { duration: 250; easing.type: Easing.OutExpo } }

                            Rectangle {
                                anchors.fill: parent
                                anchors.margins: -barWindow.s(2)
                                radius: width / 2
                                color: "transparent"
                                border.width: barWindow.s(1.5)
                                border.color: Qt.rgba(1, 1, 1, ghAvatarMouse.containsMouse ? 0.55 : 0.2)
                                Behavior on border.color { ColorAnimation { duration: 200 } }
                            }
                            ClippingRectangle {
                                anchors.fill: parent
                                radius: width / 2
                                color: "transparent"
                                Image {
                                    anchors.fill: parent
                                    source: ghAvatar.path !== "" ? "file://" + ghAvatar.path : ""
                                    fillMode: Image.PreserveAspectCrop
                                    sourceSize.width: barWindow.s(48); sourceSize.height: barWindow.s(48)
                                    smooth: true; mipmap: true
                                    cache: false
                                }
                            }
                        }
                        MouseArea {
                            id: ghAvatarMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: Quickshell.execDetached(["bash", "-c", "~/.config/hypr/scripts/qs_manager.sh toggle dash"])
                        }
                    }

                    Rectangle {
                        id: workspacesBox
                        color: "transparent"
                        border.width: 0
                        height: barWindow.barHeight
                        clip: true
                        
                        width: workspacesModel.count > 0 ? wsLayout.implicitWidth + barWindow.s(20) : 0


                        visible: width > 0 || opacity > 0
                        opacity: workspacesModel.count > 0 ? 1 : 0
                        Behavior on opacity { NumberAnimation { duration: 300 } }

                        Rectangle {
                            id: activeHighlight
                            y: (workspacesBox.height - barWindow.s(32)) / 2
                            height: barWindow.s(32)
                            radius: barWindow.s(6)
                            color: "transparent"
                            z: 0

                            property int prevIdx: 0
                            property int curIdx: workspacesModel.activeIndex

                            onCurIdxChanged: {
                                if (curIdx > prevIdx) {
                                    rightAnim.duration = 200; leftAnim.duration = 350;
                                } else if (curIdx < prevIdx) {
                                    leftAnim.duration = 200; rightAnim.duration = 350;
                                }
                                prevIdx = curIdx;
                            }

                            // FIXED: Calculate step size to perfectly match the rounded width + rounded spacing of the Row elements.
                            property real stepSize: barWindow.s(32) + barWindow.s(6)
                            property real targetLeft: wsLayout.x + (curIdx * stepSize)
                            property real targetRight: targetLeft + barWindow.s(32)

                            property real actualLeft: targetLeft
                            property real actualRight: targetRight

                            Behavior on actualLeft { NumberAnimation { id: leftAnim; duration: 250; easing.type: Easing.OutExpo } }
                            Behavior on actualRight { NumberAnimation { id: rightAnim; duration: 250; easing.type: Easing.OutExpo } }

                            x: actualLeft
                            width: actualRight - actualLeft
                            opacity: workspacesModel.count > 0 ? 1 : 0
                        }

                        // Active workspace: a white pill with its number cut out, so the
                        // bar's glass shows through the digits (OpacityMask, inverted).
                        // activeHighlight above only supplies the animated geometry.
                        Item {
                            id: hlSource
                            anchors.fill: parent
                            visible: false
                            Rectangle {
                                x: activeHighlight.x; y: activeHighlight.y
                                width: activeHighlight.width; height: activeHighlight.height
                                radius: activeHighlight.radius
                                color: "white"
                            }
                        }
                        Item {
                            id: hlMask
                            anchors.fill: parent
                            visible: false
                            Text {
                                property int idx: workspacesModel.activeIndex
                                text: (idx >= 0 && idx < workspacesModel.count) ? workspacesModel.get(idx).wsId : ""
                                x: activeHighlight.targetLeft + (barWindow.s(32) - width) / 2
                                y: activeHighlight.y + (activeHighlight.height - height) / 2
                                font.family: "SF Pro Display"
                                font.pixelSize: barWindow.s(14)
                                font.weight: Font.Black
                            }
                        }
                        OpacityMask {
                            anchors.fill: parent
                            source: hlSource
                            maskSource: hlMask
                            invert: true
                            opacity: workspacesModel.count > 0 ? 1 : 0
                        }

                        Row {
                            id: wsLayout
                            anchors.centerIn: parent
                            spacing: barWindow.s(6)
                            
                            Repeater {
                                model: workspacesModel
                                delegate: Rectangle {
                                    id: wsPill
                                    
                                    
                                    property bool isHovered: wsPillMouse.containsMouse
                                    
                                    property string stateLabel: model.wsState
                                    property string wsName: model.wsId
                                    
                                    property real targetWidth: barWindow.s(32)
                                    width: targetWidth
                                    Behavior on targetWidth { NumberAnimation { duration: 250; easing.type: Easing.OutBack } }
                                    
                                    height: barWindow.s(32); radius: barWindow.s(6)
                                    
                                    color: isHovered && index !== workspacesModel.activeIndex ? Qt.rgba(mocha.text.r, mocha.text.g, mocha.text.b, 0.1) : "transparent"

                                    scale: isHovered && stateLabel !== "active" ? 1.08 : 1.0
                                    Behavior on scale { NumberAnimation { duration: 250; easing.type: Easing.OutBack } }
                                    
                                    property bool initAnimTrigger: false
                                    opacity: initAnimTrigger ? 1 : 0
                                    transform: Translate {
                                        y: wsPill.initAnimTrigger ? 0 : barWindow.s(15)
                                        Behavior on y { NumberAnimation { duration: 500; easing.type: Easing.OutBack } }
                                    }

                                    Component.onCompleted: {
                                        if (!barWindow.startupCascadeFinished) {
                                            animTimer.interval = index * 60;
                                            animTimer.start();
                                        } else {
                                            initAnimTrigger = true;
                                        }
                                    }

                                    Timer {
                                        id: animTimer
                                        running: false
                                        repeat: false
                                        onTriggered: wsPill.initAnimTrigger = true
                                    }
                                    
                                    Behavior on opacity { NumberAnimation { duration: 500; easing.type: Easing.OutCubic } }
                                    Behavior on color { ColorAnimation { duration: 250 } }

                                    Text {
                                        anchors.centerIn: parent
                                        text: wsName
                                        font.family: "SF Pro Display"
                                        font.pixelSize: barWindow.s(14)
                                        font.weight: stateLabel === "active" ? Font.Black : (stateLabel === "occupied" ? Font.Bold : Font.Medium)
                                        
                                        color: index === workspacesModel.activeIndex ? mocha.text : (isHovered ? mocha.text : (stateLabel === "occupied" ? mocha.subtext0 : mocha.overlay0))
                                        
                                        Behavior on color { ColorAnimation { duration: 250 } }
                                        // the active number is drawn as a cut-out in the white pill instead
                                        opacity: index === workspacesModel.activeIndex ? 0 : 1
                                    }
                                    MouseArea {
                                        id: wsPillMouse
                                        hoverEnabled: true
                                        anchors.fill: parent
                                        onClicked: Quickshell.execDetached(["bash", "-c", "~/.config/hypr/scripts/qs_manager.sh " + wsName])
                                    }
                                }
                            }
                        }
                    }

                    Rectangle {
                        height: barWindow.barHeight
                        border.width: 0
                        color: "transparent"

                        property real targetWidth: trayRepeater.count > 0 ? trayLayout.width + barWindow.s(24) : 0
                        width: targetWidth
                        Behavior on width { NumberAnimation { duration: 400; easing.type: Easing.OutExpo } }

                        visible: targetWidth > 0
                        opacity: targetWidth > 0 ? 1 : 0
                        Behavior on opacity { NumberAnimation { duration: 300 } }

                        Row {
                            id: trayLayout
                            anchors.centerIn: parent
                            spacing: barWindow.s(10)

                            Repeater {
                                id: trayRepeater
                                model: SystemTray.items
                                delegate: Image {
                                    id: trayIcon
                                    source: modelData.icon || ""
                                    fillMode: Image.PreserveAspectFit

                                    sourceSize: Qt.size(barWindow.s(18), barWindow.s(18))
                                    width: barWindow.s(18)
                                    height: barWindow.s(18)
                                    anchors.verticalCenter: parent.verticalCenter

                                    property bool isHovered: trayMouse.containsMouse
                                    property bool initAnimTrigger: false
                                    opacity: initAnimTrigger ? (isHovered ? 1.0 : 0.8) : 0.0
                                    scale: initAnimTrigger ? (isHovered ? 1.15 : 1.0) : 0.0

                                    Component.onCompleted: {
                                        if (!barWindow.startupCascadeFinished) {
                                            trayAnimTimer.interval = index * 50;
                                            trayAnimTimer.start();
                                        } else {
                                            initAnimTrigger = true;
                                        }
                                    }
                                    Timer {
                                        id: trayAnimTimer
                                        running: false
                                        repeat: false
                                        onTriggered: trayIcon.initAnimTrigger = true
                                    }

                                    Behavior on opacity { NumberAnimation { duration: 250; easing.type: Easing.OutCubic } }
                                    Behavior on scale { NumberAnimation { duration: 250; easing.type: Easing.OutBack } }

                                    QsMenuAnchor {
                                        id: menuAnchor
                                        anchor.window: barWindow
                                        anchor.item: trayIcon
                                        menu: modelData.menu
                                    }

                                    MouseArea {
                                        id: trayMouse
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
                                        onClicked: mouse => {
                                            if (mouse.button === Qt.LeftButton) {
                                                if (modelData.isMenuOnly || modelData.onlyMenu) {
                                                    menuAnchor.open();
                                                } else if (typeof modelData.activate === "function") {
                                                    modelData.activate(); 
                                                }
                                            } else if (mouse.button === Qt.MiddleButton) {
                                                if (typeof modelData.secondaryActivate === "function") {
                                                    modelData.secondaryActivate();
                                                }
                                            } else if (mouse.button === Qt.RightButton) {
                                                if (modelData.menu) { 
                                                    menuAnchor.open();
                                                } else if (typeof modelData.contextMenu === "function") {
                                                    modelData.contextMenu(mouse.x, mouse.y);
                                                } else {
                                                    modelData.activate(); 
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }

                Rectangle {
                    id: mediaBox
                    color: "transparent"
                    border.width: 0
                    y: (parent.height - barWindow.barHeight) / 2
                    height: barWindow.barHeight
                    clip: true 
                    
                    width: programsPill.targetWidth
                    Behavior on width { NumberAnimation { duration: 400; easing.type: Easing.OutQuint } }

                    property real defaultX: leftContent.x + leftContent.width + (leftContent.width > 0 ? barWindow.s(4) : 0)
                    x: defaultX

                    visible: width > 0 || opacity > 0
                    opacity: 1.0
                    Behavior on opacity { NumberAnimation { duration: 400 } }
                    
                    Rectangle {
                        id: programsPill
                        property bool isHovered: programsMouse.containsMouse
                        color: isHovered ? Qt.rgba(mocha.text.r, mocha.text.g, mocha.text.b, 0.08) : "transparent"
                        radius: barWindow.s(6); height: barWindow.s(34);
                        clip: true

                        anchors.centerIn: parent

                        property var activeWs: Hyprland.focusedMonitor ? Hyprland.focusedMonitor.activeWorkspace : null
                        property var toplevelsList: activeWs ? activeWs.toplevels : null
                        // ObjectModel only exposes .values (no count) in current Quickshell
                        property int toplevelsCount: toplevelsList && toplevelsList.values ? toplevelsList.values.length : 0

                        // per-workspace app list: turned off (set back to the line below to re-enable)
                        // property real targetWidth: toplevelsCount > 0 ? (programsLayoutRow.implicitWidth + barWindow.s(24)) : 0
                        property real targetWidth: 0
                        width: targetWidth
                        Behavior on width { NumberAnimation { duration: 500; easing.type: Easing.OutQuint } }

                        scale: isHovered ? 1.05 : 1.0
                        Behavior on scale { NumberAnimation { duration: 250; easing.type: Easing.OutExpo } }
                        Behavior on color { ColorAnimation { duration: 200 } }

                        property bool initAnimTrigger: false
                        Timer { running: rightContent.showLayout && !programsPill.initAnimTrigger; interval: 0; onTriggered: programsPill.initAnimTrigger = true }
                        opacity: initAnimTrigger ? 1 : 0
                        transform: Translate { y: programsPill.initAnimTrigger ? 0 : barWindow.s(15); Behavior on y { NumberAnimation { duration: 500; easing.type: Easing.OutBack } } }
                        Behavior on opacity { NumberAnimation { duration: 400; easing.type: Easing.OutCubic } }

                        Row {
                            id: programsLayoutRow
                            anchors.verticalCenter: parent.verticalCenter
                            anchors.left: parent.left
                            anchors.leftMargin: barWindow.s(12)
                            spacing: barWindow.s(8)

                            Repeater {
                                model: programsPill.toplevelsList
                                delegate: Rectangle {
                                    width: barWindow.s(24)
                                    height: barWindow.s(24)
                                    radius: barWindow.s(6)
                                    color: modelData.activated ? Qt.rgba(mocha.text.r, mocha.text.g, mocha.text.b, 0.12) : "transparent"
                                    border.width: 0

                                    Image {
                                        id: appIcon
                                        anchors.centerIn: parent
                                        width: barWindow.s(16)
                                        height: barWindow.s(16)
                                        // HyprlandToplevel: app id lives on its Wayland toplevel (or Hyprland's window class)
                                        readonly property string appId: (modelData.wayland && modelData.wayland.appId) ? modelData.wayland.appId
                                                                      : (modelData.lastIpcObject && modelData.lastIpcObject.class) ? modelData.lastIpcObject.class : ""
                                        // window class -> desktop entry icon (e.g. "zen" -> "zen-browser"), with a real fallback
                                        readonly property var entry: appId !== "" ? DesktopEntries.heuristicLookup(appId) : null
                                        source: Quickshell.iconPath(entry && entry.icon ? entry.icon : appId.toLowerCase(), "application-x-executable")
                                        fillMode: Image.PreserveAspectFit

                                        onStatusChanged: {
                                            if (status === Image.Error) {
                                                source = "image://icon/application-x-executable"
                                            }
                                        }
                                    }

                                    MouseArea {
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        onClicked: modelData.wayland ? modelData.wayland.activate()
                                                                     : Quickshell.execDetached(["hyprctl", "dispatch", "hl.dsp.focus({ window = \"address:0x" + modelData.address + "\" })"])
                                    }
                                }
                            }
                        }

                        MouseArea {
                            id: programsMouse
                            anchors.fill: parent
                            hoverEnabled: true
                        }
                    }
                }

                Row {
                    id: rightContent
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: barWindow.s(4)
                    
                    property bool showLayout: false
                    opacity: showLayout ? 1 : 0
                    transform: Translate {
                        x: rightContent.showLayout ? 0 : barWindow.s(30)
                        Behavior on x { NumberAnimation { duration: 800; easing.type: Easing.OutBack; easing.overshoot: 1.1 } }
                    }
                    
                    Timer {
                        running: barWindow.isStartupReady && barWindow.isDataReady
                        interval: 250
                        onTriggered: rightContent.showLayout = true
                    }

                    Behavior on opacity { NumberAnimation { duration: 600; easing.type: Easing.OutCubic } }



                    Rectangle {
                        height: barWindow.barHeight
                        border.width: 0
                        color: "transparent"
                        clip: true
                        
                        width: sysLayout.implicitWidth + barWindow.s(20)

                        Row {
                            id: sysLayout
                            anchors.centerIn: parent
                            spacing: barWindow.s(8) 

                            property int pillHeight: barWindow.s(34)



                            // ---- Claude Code sessions (claude/: hooks write status, popup lists them) ----
                            Rectangle {
                                id: claudePill
                                property bool isHovered: claudeMouse.containsMouse
                                property var sessions: []
                                readonly property int nWaiting: sessions.filter(x => x.status === "waiting").length
                                readonly property int nDone: sessions.filter(x => x.status === "done").length
                                readonly property int nWorking: sessions.filter(x => x.status === "working").length
                                readonly property string dirPath: Quickshell.env("XDG_RUNTIME_DIR") + "/claude-status"

                                radius: barWindow.s(10); height: sysLayout.pillHeight
                                readonly property bool needsYou: nWaiting > 0
                                readonly property bool yourTurn: !needsYou && nDone > 0
                                readonly property color claudeOrange: "#D97757"
                                readonly property int maxIcons: 6
                                // stable order: oldest claude process first, so icons don't shuffle around
                                readonly property var ordered: sessions.slice().sort((a, b) => (a.pid || 0) - (b.pid || 0))
                                readonly property var frames: ["\u00B7", "\u2722", "\u2733", "\u2736", "\u273B", "\u273D"]
                                property int step: 0
                                Timer {
                                    interval: 120; repeat: true
                                    running: claudePill.nWorking > 0
                                    onTriggered: claudePill.step = (claudePill.step + 1) % 10
                                }
                                color: isHovered ? Qt.rgba(mocha.text.r, mocha.text.g, mocha.text.b, 0.08) : "transparent"
                                // 0..1 pulse shared by the "!" (needs permission) and the disc (done)
                                QtObject {
                                    id: claudeGlow
                                    property real v: 1
                                    property var anim: SequentialAnimation {
                                        running: claudePill.needsYou || claudePill.yourTurn
                                        loops: Animation.Infinite
                                        NumberAnimation { target: claudeGlow; property: "v"; to: 0; duration: 650; easing.type: Easing.InOutSine }
                                        NumberAnimation { target: claudeGlow; property: "v"; to: 1; duration: 650; easing.type: Easing.InOutSine }
                                        onRunningChanged: if (!running) claudeGlow.v = 1
                                    }
                                }
                                clip: true
                                property real targetWidth: sessions.length > 0 ? claudeRow.implicitWidth + barWindow.s(16) : 0
                                width: targetWidth
                                visible: targetWidth > 0
                                Behavior on width { NumberAnimation { duration: 400; easing.type: Easing.OutQuint } }
                                scale: isHovered ? 1.05 : 1.0
                                Behavior on scale { NumberAnimation { duration: 250; easing.type: Easing.OutExpo } }

                                Process {
                                    id: claudeReader
                                    command: ["bash", Quickshell.env("HOME") + "/.config/hypr/scripts/quickshell/claude/claude_list.sh"]
                                    stdout: StdioCollector {
                                        onStreamFinished: { try { claudePill.sessions = JSON.parse(this.text); } catch (e) {} }
                                    }
                                }
                                // instant updates when a hook writes a status file
                                Process {
                                    id: claudeWatcher
                                    command: ["bash", "-c", "mkdir -p \"$1\"; inotifywait -qq -e create,modify,delete,moved_to \"$1\"", "_", claudePill.dirPath]
                                    running: true
                                    onExited: { claudeReader.running = true; running = true; }
                                }
                                // fallback: also clears sessions whose claude process died
                                Timer { interval: 5000; running: true; repeat: true; triggeredOnStart: true; onTriggered: claudeReader.running = true }

                                Row {
                                    id: claudeRow
                                    anchors.verticalCenter: parent.verticalCenter
                                    anchors.left: parent.left
                                    anchors.leftMargin: barWindow.s(8)
                                    spacing: barWindow.s(2)
                                    // one star per session, oldest first (always Claude orange)
                                    //   idle: still ✻   working: cycles like Claude Code's spinner
                                    //   done: white ✳ on a pulsing orange disc   needs permission: blinking "!"
                                    Repeater {
                                        model: claudePill.ordered.slice(0, claudePill.maxIcons)
                                        Item {
                                            id: sessIcon
                                            readonly property string st: modelData.status
                                            readonly property bool done: st === "done"
                                            anchors.verticalCenter: parent.verticalCenter
                                            width: barWindow.s(26); height: width
                                            Rectangle {
                                                anchors.fill: parent
                                                radius: width / 2
                                                color: Qt.alpha(claudePill.claudeOrange, 0.12 + 0.28 * claudeGlow.v)
                                                border.width: barWindow.s(1.5)
                                                border.color: Qt.alpha(claudePill.claudeOrange, 0.5 + 0.5 * claudeGlow.v)
                                                opacity: sessIcon.done ? 1 : 0
                                                scale: sessIcon.done ? 1 : 0.6
                                                Behavior on opacity { NumberAnimation { duration: 200 } }
                                                Behavior on scale { NumberAnimation { duration: 300; easing.type: Easing.OutBack } }
                                            }
                                            Text {
                                                anchors.centerIn: parent
                                                text: {
                                                    if (sessIcon.st === "waiting") return "!";
                                                    if (sessIcon.done) return "\u2733";
                                                    if (sessIcon.st !== "working") return "\u273B";
                                                    // each session offset a bit so they don't all move in lockstep
                                                    let f = claudePill.frames, n = f.length, k = (claudePill.step + index * 3) % (2 * n - 2);
                                                    return f[k < n ? k : 2 * n - 2 - k];
                                                }
                                                color: sessIcon.done ? "white" : claudePill.claudeOrange
                                                opacity: sessIcon.st === "waiting" ? 0.3 + 0.7 * claudeGlow.v : 1
                                                Behavior on color { ColorAnimation { duration: 200 } }
                                                font.family: "SF Pro Display"; font.pixelSize: barWindow.s(18); font.weight: Font.Black
                                            }
                                        }
                                    }
                                    Item { width: barWindow.s(4); height: 1 }
                                    Text {   // total sessions (also covers any beyond maxIcons)
                                        anchors.verticalCenter: parent.verticalCenter
                                        text: claudePill.sessions.length
                                        color: "white"
                                        font.family: "SF Pro Display"; font.pixelSize: barWindow.s(14); font.weight: Font.Black
                                    }
                                }
                                MouseArea {
                                    id: claudeMouse
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: Quickshell.execDetached(["bash", "-c", "~/.config/hypr/scripts/qs_manager.sh toggle claude"])
                                }
                            }

                            Rectangle {
                                id: wifiPill
                                property bool isHovered: wifiMouse.containsMouse
                                radius: barWindow.s(10); height: sysLayout.pillHeight; 
                                color: "transparent"
                                clip: true

                                Component.onCompleted: SysData.subscribe()
                                Component.onDestruction: SysData.unsubscribe()

                                property real targetWidth: barWindow.s(120)
                                width: targetWidth
                                Behavior on width { NumberAnimation { duration: 500; easing.type: Easing.OutQuint } }
                                
                                scale: isHovered ? 1.05 : 1.0
                                Behavior on scale { NumberAnimation { duration: 250; easing.type: Easing.OutExpo } }
                                Behavior on color { ColorAnimation { duration: 200 } }

                                property bool initAnimTrigger: false
                                Timer { running: rightContent.showLayout && !wifiPill.initAnimTrigger; interval: 50; onTriggered: wifiPill.initAnimTrigger = true }
                                opacity: initAnimTrigger ? 1 : 0
                                transform: Translate { y: wifiPill.initAnimTrigger ? 0 : barWindow.s(15); Behavior on y { NumberAnimation { duration: 500; easing.type: Easing.OutBack } } }
                                Behavior on opacity { NumberAnimation { duration: 400; easing.type: Easing.OutCubic } }

                                Row { 
                                    id: wifiLayoutRow
                                    anchors.verticalCenter: parent.verticalCenter
                                    anchors.left: parent.left
                                    anchors.leftMargin: barWindow.s(12)
                                    spacing: barWindow.s(8)

                                    layer.enabled: true
                                    layer.effect: LinearGradient {
                                        start: Qt.point(0, 0)
                                        end: Qt.point(wifiLayoutRow.width, 0)
                                        gradient: Gradient {
                                            GradientStop { 
                                                position: 0.0
                                                color: (barWindow.showEthernet ? (barWindow.ethStatus === "Connected") : barWindow.isWifiOn) ? mocha.blue : mocha.subtext0
                                                Behavior on color { ColorAnimation { duration: 250 } }
                                            }
                                            GradientStop { 
                                                position: 1.0
                                                color: (barWindow.showEthernet ? (barWindow.ethStatus === "Connected") : barWindow.isWifiOn) ? Qt.lighter(mocha.blue, 1.3) : mocha.text
                                                Behavior on color { ColorAnimation { duration: 250 } }
                                            }
                                        }
                                    }

                                    Text { 
                                        anchors.verticalCenter: parent.verticalCenter; 
                                        text: barWindow.showEthernet ? "󰈀" : barWindow.wifiIcon;
                                        font.family: "Iosevka Nerd Font"; font.pixelSize: barWindow.s(16);
                                        color: "white"
                                    }

                                    Text {
                                        anchors.verticalCenter: parent.verticalCenter
                                        text: barWindow.formatSpeed(SysData.netRx)
                                        font.family: "SF Pro Display"; font.pixelSize: barWindow.s(14); font.weight: Font.Black; 
                                        color: "white"
                                    }
                                }
                                MouseArea { id: wifiMouse; hoverEnabled: true; anchors.fill: parent; onClicked: Quickshell.execDetached(["bash", "-c", "~/.config/hypr/scripts/qs_manager.sh toggle wifi"]) }
                            }

                            Rectangle {
                                id: btPill
                                property bool isHovered: btMouse.containsMouse
                                radius: barWindow.s(10); height: sysLayout.pillHeight
                                clip: true
                                color: "transparent"

                                property real targetWidth: btLayoutRow.implicitWidth + barWindow.s(24)
                                width: targetWidth
                                visible: targetWidth > 0
                                Behavior on width { NumberAnimation { duration: 500; easing.type: Easing.OutQuint } }

                                scale: isHovered ? 1.05 : 1.0
                                Behavior on scale { NumberAnimation { duration: 250; easing.type: Easing.OutExpo } }
                                Behavior on color { ColorAnimation { duration: 200 } }

                                property bool initAnimTrigger: false
                                Timer { running: rightContent.showLayout && !btPill.initAnimTrigger; interval: 100; onTriggered: btPill.initAnimTrigger = true }
                                opacity: initAnimTrigger ? 1 : 0
                                transform: Translate { y: btPill.initAnimTrigger ? 0 : barWindow.s(15); Behavior on y { NumberAnimation { duration: 500; easing.type: Easing.OutBack } } }
                                Behavior on opacity { NumberAnimation { duration: 400; easing.type: Easing.OutCubic } }

                                Row { 
                                    id: btLayoutRow
                                    anchors.verticalCenter: parent.verticalCenter
                                    anchors.left: parent.left
                                    anchors.leftMargin: barWindow.s(12)
                                    spacing: barWindow.s(8)

                                    layer.enabled: true
                                    layer.effect: LinearGradient {
                                        start: Qt.point(0, 0)
                                        end: Qt.point(btLayoutRow.width, 0)
                                        gradient: Gradient {
                                            GradientStop { 
                                                position: 0.0
                                                color: barWindow.isBtOn ? mocha.mauve : mocha.subtext0
                                                Behavior on color { ColorAnimation { duration: 250 } }
                                            }
                                            GradientStop { 
                                                position: 1.0
                                                color: barWindow.isBtOn ? Qt.lighter(mocha.mauve, 1.3) : mocha.text
                                                Behavior on color { ColorAnimation { duration: 250 } }
                                            }
                                        }
                                    }

                                    Text { 
                                        anchors.verticalCenter: parent.verticalCenter; 
                                        text: barWindow.btIcon; 
                                        font.family: "Iosevka Nerd Font"; font.pixelSize: barWindow.s(16); 
                                        color: "white"
                                    }

                                    Text {
                                        anchors.verticalCenter: parent.verticalCenter
                                        text: barWindow.btDevice
                                        font.family: "SF Pro Display"; font.pixelSize: barWindow.s(14); font.weight: Font.Black; 
                                        color: "white"
                                    }
                                }
                                MouseArea { id: btMouse; hoverEnabled: true; anchors.fill: parent; onClicked: Quickshell.execDetached(["bash", "-c", "~/.config/hypr/scripts/qs_manager.sh toggle bluetooth"]) }
                            }

                            Rectangle {
                                id: warpPill
                                property bool isHovered: warpMouse.containsMouse
                                radius: barWindow.s(10); height: sysLayout.pillHeight
                                clip: true
                                color: "transparent"

                                property real targetWidth: warpLayoutRow.implicitWidth + barWindow.s(24)
                                width: targetWidth
                                visible: targetWidth > 0
                                Behavior on width { NumberAnimation { duration: 500; easing.type: Easing.OutQuint } }

                                scale: isHovered ? 1.05 : 1.0
                                Behavior on scale { NumberAnimation { duration: 250; easing.type: Easing.OutExpo } }

                                property bool initAnimTrigger: false
                                Timer { running: rightContent.showLayout && !warpPill.initAnimTrigger; interval: 100; onTriggered: warpPill.initAnimTrigger = true }
                                opacity: initAnimTrigger ? 1 : 0
                                transform: Translate { y: warpPill.initAnimTrigger ? 0 : barWindow.s(15); Behavior on y { NumberAnimation { duration: 500; easing.type: Easing.OutBack } } }
                                Behavior on opacity { NumberAnimation { duration: 400; easing.type: Easing.OutCubic } }

                                Row {
                                    id: warpLayoutRow
                                    anchors.verticalCenter: parent.verticalCenter
                                    anchors.left: parent.left
                                    anchors.leftMargin: barWindow.s(12)
                                    spacing: barWindow.s(8)

                                    layer.enabled: true
                                    layer.effect: LinearGradient {
                                        start: Qt.point(0, 0)
                                        end: Qt.point(warpLayoutRow.width, 0)
                                        gradient: Gradient {
                                            GradientStop {
                                                position: 0.0
                                                color: barWindow.isWarpOn ? "#F38020" : mocha.subtext0
                                                Behavior on color { ColorAnimation { duration: 250 } }
                                            }
                                            GradientStop {
                                                position: 1.0
                                                color: barWindow.isWarpOn ? Qt.lighter("#F38020", 1.15) : mocha.text
                                                Behavior on color { ColorAnimation { duration: 250 } }
                                            }
                                        }
                                    }

                                    Text {
                                        anchors.verticalCenter: parent.verticalCenter
                                        text: barWindow.isWarpOn ? "󰅟" : "󰅤"
                                        font.family: "Iosevka Nerd Font"; font.pixelSize: barWindow.s(16)
                                        color: "white"
                                    }

                                    Text {
                                        anchors.verticalCenter: parent.verticalCenter
                                        text: "WARP"
                                        font.family: "SF Pro Display"; font.pixelSize: barWindow.s(14); font.weight: Font.Black
                                        color: "white"
                                    }
                                }
                                MouseArea { id: warpMouse; hoverEnabled: true; anchors.fill: parent; onClicked: if (!warpToggler.running) warpToggler.running = true }
                            }

                            Rectangle {
                                id: volPill
                                property bool isHovered: volMouse.containsMouse
                                color: "transparent"
                                radius: barWindow.s(10); height: sysLayout.pillHeight;
                                clip: true
                                
                                property real targetWidth: volLayoutRow.implicitWidth + barWindow.s(24)
                                width: targetWidth
                                Behavior on width { NumberAnimation { duration: 500; easing.type: Easing.OutQuint } }
                                
                                scale: isHovered ? 1.05 : 1.0
                                Behavior on scale { NumberAnimation { duration: 250; easing.type: Easing.OutExpo } }
                                Behavior on color { ColorAnimation { duration: 200 } }

                                property bool initAnimTrigger: false
                                Timer { running: rightContent.showLayout && !volPill.initAnimTrigger; interval: 150; onTriggered: volPill.initAnimTrigger = true }
                                opacity: initAnimTrigger ? 1 : 0
                                transform: Translate { y: volPill.initAnimTrigger ? 0 : barWindow.s(15); Behavior on y { NumberAnimation { duration: 500; easing.type: Easing.OutBack } } }
                                Behavior on opacity { NumberAnimation { duration: 400; easing.type: Easing.OutCubic } }

                                Row { 
                                    id: volLayoutRow
                                    anchors.verticalCenter: parent.verticalCenter
                                    anchors.left: parent.left
                                    anchors.leftMargin: barWindow.s(12)
                                    spacing: barWindow.s(8)

                                    layer.enabled: true
                                    layer.effect: LinearGradient {
                                        start: Qt.point(0, 0)
                                        end: Qt.point(volLayoutRow.width, 0)
                                        gradient: Gradient {
                                            GradientStop { 
                                                position: 0.0
                                                color: barWindow.isSoundActive ? mocha.peach : mocha.subtext0
                                                Behavior on color { ColorAnimation { duration: 250 } }
                                            }
                                            GradientStop { 
                                                position: 1.0
                                                color: barWindow.isSoundActive ? Qt.lighter(mocha.peach, 1.3) : mocha.text
                                                Behavior on color { ColorAnimation { duration: 250 } }
                                            }
                                        }
                                    }

                                    Text { 
                                        anchors.verticalCenter: parent.verticalCenter
                                        text: barWindow.volIcon; font.family: "Iosevka Nerd Font"; font.pixelSize: barWindow.s(20); 
                                        color: "white"
                                    }
                                    Text { 
                                        anchors.verticalCenter: parent.verticalCenter
                                        text: barWindow.volPercent; 
                                        font.family: "SF Pro Display"; font.pixelSize: barWindow.s(14); font.weight: Font.Black; 
                                        color: "white"
                                    }
                                }
                                MouseArea { id: volMouse; hoverEnabled: true; anchors.fill: parent; onClicked: Quickshell.execDetached(["bash", "-c", "~/.config/hypr/scripts/qs_manager.sh toggle volume"]) }
                            }

                            Rectangle {
                                id: batPill
                                property bool isHovered: batMouse.containsMouse
                                color: "transparent"
                                radius: barWindow.s(10); height: sysLayout.pillHeight;
                                clip: true
                                
                                property real targetWidth: barWindow.isDesktop ? barWindow.s(34) : batLayoutRow.implicitWidth + barWindow.s(24)
                                width: targetWidth
                                Behavior on width { NumberAnimation { duration: 500; easing.type: Easing.OutQuint } }
                                
                                scale: isHovered ? 1.05 : 1.0
                                Behavior on scale { NumberAnimation { duration: 250; easing.type: Easing.OutExpo } }
                                Behavior on color { ColorAnimation { duration: 200 } }

                                property bool initAnimTrigger: false
                                Timer { running: rightContent.showLayout && !batPill.initAnimTrigger; interval: 200; onTriggered: batPill.initAnimTrigger = true }
                                opacity: initAnimTrigger ? 1 : 0
                                transform: Translate { y: batPill.initAnimTrigger ? 0 : barWindow.s(15); Behavior on y { NumberAnimation { duration: 500; easing.type: Easing.OutBack } } }
                                Behavior on opacity { NumberAnimation { duration: 400; easing.type: Easing.OutCubic } }

                                Row { 
                                    id: batLayoutRow
                                    anchors.centerIn: parent
                                    spacing: barWindow.s(8)

                                    layer.enabled: true
                                    layer.effect: LinearGradient {
                                        start: Qt.point(0, 0)
                                        end: Qt.point(batLayoutRow.width, 0)
                                        gradient: Gradient {
                                            GradientStop { 
                                                position: 0.0
                                                color: barWindow.isDesktop ? mocha.red : barWindow.batDynamicColor
                                                Behavior on color { ColorAnimation { duration: 300 } }
                                            }
                                            GradientStop { 
                                                position: 1.0
                                                color: barWindow.isDesktop ? Qt.lighter(mocha.red, 1.3) : Qt.lighter(barWindow.batDynamicColor, 1.3)
                                                Behavior on color { ColorAnimation { duration: 300 } }
                                            }
                                        }
                                    }

                                    Text { 
                                        anchors.verticalCenter: parent.verticalCenter
                                        text: barWindow.isDesktop ? "" : barWindow.batIcon; 
                                        font.family: "Iosevka Nerd Font"; font.pixelSize: barWindow.s(16)
                                        color: "white"
                                    }
                                    Text { 
                                        anchors.verticalCenter: parent.verticalCenter
                                        visible: !barWindow.isDesktop
                                        text: barWindow.batPercent; font.family: "SF Pro Display"; font.pixelSize: barWindow.s(14); font.weight: Font.Black; 
                                        color: "white"
                                    }
                                }
                                MouseArea { id: batMouse; hoverEnabled: true; anchors.fill: parent; onClicked: Quickshell.execDetached(["bash", "-c", "~/.config/hypr/scripts/qs_manager.sh toggle battery"]) }
                            }

                            Rectangle {
                                id: notifPill
                                property bool isHovered: notifMouse.containsMouse
                                radius: barWindow.s(10); height: sysLayout.pillHeight
                                clip: true
                                color: "transparent"

                                property real targetWidth: notifLayoutRow.implicitWidth + barWindow.s(24)
                                width: targetWidth
                                visible: targetWidth > 0
                                Behavior on width { NumberAnimation { duration: 500; easing.type: Easing.OutQuint } }

                                scale: isHovered ? 1.05 : 1.0
                                Behavior on scale { NumberAnimation { duration: 250; easing.type: Easing.OutExpo } }
                                Behavior on color { ColorAnimation { duration: 200 } }

                                property bool initAnimTrigger: false
                                Timer { running: rightContent.showLayout && !notifPill.initAnimTrigger; interval: 220; onTriggered: notifPill.initAnimTrigger = true }
                                opacity: initAnimTrigger ? 1 : 0
                                transform: Translate { y: notifPill.initAnimTrigger ? 0 : barWindow.s(15); Behavior on y { NumberAnimation { duration: 500; easing.type: Easing.OutBack } } }
                                Behavior on opacity { NumberAnimation { duration: 400; easing.type: Easing.OutCubic } }

                                Row {
                                    id: notifLayoutRow
                                    anchors.verticalCenter: parent.verticalCenter
                                    anchors.left: parent.left
                                    anchors.leftMargin: barWindow.s(12)
                                    spacing: barWindow.s(8)

                                    layer.enabled: true
                                    layer.effect: LinearGradient {
                                        start: Qt.point(0, 0)
                                        end: Qt.point(notifLayoutRow.width, 0)
                                        gradient: Gradient {
                                            GradientStop {
                                                position: 0.0
                                                color: (!!topBarRoot.notifModel && topBarRoot.notifModel.count > 0) ? mocha.mauve : mocha.subtext0
                                                Behavior on color { ColorAnimation { duration: 250 } }
                                            }
                                            GradientStop {
                                                position: 1.0
                                                color: (!!topBarRoot.notifModel && topBarRoot.notifModel.count > 0) ? Qt.lighter(mocha.mauve, 1.3) : mocha.text
                                                Behavior on color { ColorAnimation { duration: 250 } }
                                            }
                                        }
                                    }

                                    Text {
                                        anchors.verticalCenter: parent.verticalCenter;
                                        text: (!!topBarRoot.notifModel && topBarRoot.notifModel.count > 0) ? String.fromCodePoint(0xF009E) : String.fromCodePoint(0xF009A);
                                        font.family: "Iosevka Nerd Font"; font.pixelSize: barWindow.s(16);
                                        color: "white"
                                    }
                                }
                                MouseArea { id: notifMouse; hoverEnabled: true; anchors.fill: parent; onClicked: Quickshell.execDetached(["bash", "-c", "~/.config/hypr/scripts/qs_manager.sh toggle notifications"]) }
                            }

                            Rectangle {
                                id: powerPill
                                property bool isHovered: powerMouse.containsMouse
                                radius: barWindow.s(10); height: sysLayout.pillHeight
                                clip: true
                                color: "transparent"

                                property real targetWidth: powerLayoutRow.implicitWidth + barWindow.s(24)
                                width: targetWidth
                                visible: targetWidth > 0
                                Behavior on width { NumberAnimation { duration: 500; easing.type: Easing.OutQuint } }

                                scale: isHovered ? 1.05 : 1.0
                                Behavior on scale { NumberAnimation { duration: 250; easing.type: Easing.OutExpo } }
                                Behavior on color { ColorAnimation { duration: 200 } }

                                property bool initAnimTrigger: false
                                Timer { running: rightContent.showLayout && !powerPill.initAnimTrigger; interval: 235; onTriggered: powerPill.initAnimTrigger = true }
                                opacity: initAnimTrigger ? 1 : 0
                                transform: Translate { y: powerPill.initAnimTrigger ? 0 : barWindow.s(15); Behavior on y { NumberAnimation { duration: 500; easing.type: Easing.OutBack } } }
                                Behavior on opacity { NumberAnimation { duration: 400; easing.type: Easing.OutCubic } }

                                Row {
                                    id: powerLayoutRow
                                    anchors.verticalCenter: parent.verticalCenter
                                    anchors.left: parent.left
                                    anchors.leftMargin: barWindow.s(12)
                                    spacing: barWindow.s(8)

                                    layer.enabled: true
                                    layer.effect: LinearGradient {
                                        start: Qt.point(0, 0)
                                        end: Qt.point(powerLayoutRow.width, 0)
                                        gradient: Gradient {
                                            GradientStop {
                                                position: 0.0
                                                color: false ? mocha.mauve : mocha.subtext0
                                                Behavior on color { ColorAnimation { duration: 250 } }
                                            }
                                            GradientStop {
                                                position: 1.0
                                                color: false ? Qt.lighter(mocha.mauve, 1.3) : mocha.text
                                                Behavior on color { ColorAnimation { duration: 250 } }
                                            }
                                        }
                                    }

                                    Text {
                                        anchors.verticalCenter: parent.verticalCenter;
                                        text: String.fromCodePoint(0xF0425);
                                        font.family: "Iosevka Nerd Font"; font.pixelSize: barWindow.s(16);
                                        color: "white"
                                    }
                                }
                                MouseArea { id: powerMouse; hoverEnabled: true; anchors.fill: parent; onClicked: Quickshell.execDetached(["bash", "-c", "~/.config/hypr/scripts/qs_manager.sh toggle power"]) }
                            }

                            Rectangle {
                                id: datePill
                                property bool isHovered: dateMouse.containsMouse
                                radius: barWindow.s(10)
                                height: sysLayout.pillHeight
                                color:  "transparent"
                                clip: true

                                property real targetWidth: dateLayoutRow.implicitWidth + barWindow.s(24)
                                width: targetWidth
                                Behavior on width { NumberAnimation { duration: 500; easing.type: Easing.OutQuint } }
                                
                                scale: isHovered ? 1.05 : 1.0
                                Behavior on scale { NumberAnimation { duration: 250; easing.type: Easing.OutExpo } }
                                Behavior on color { ColorAnimation { duration: 200 } }

                                property bool initAnimTrigger: false
                                Timer { running: rightContent.showLayout && !datePill.initAnimTrigger; interval: 250; onTriggered: datePill.initAnimTrigger = true }
                                opacity: initAnimTrigger ? 1 : 0
                                transform: Translate { y: datePill.initAnimTrigger ? 0 : barWindow.s(15); Behavior on y { NumberAnimation { duration: 500; easing.type: Easing.OutBack } } }
                                Behavior on opacity { NumberAnimation { duration: 400; easing.type: Easing.OutCubic } }

                                Row {
                                    id: dateLayoutRow
                                    anchors.verticalCenter: parent.verticalCenter
                                    anchors.left: parent.left
                                    anchors.leftMargin: barWindow.s(12)
                                    spacing: barWindow.s(6)

                                    Text {
                                        anchors.verticalCenter: parent.verticalCenter
                                        text: barWindow.dateStr
                                        font.family: "SF Pro Display"
                                        font.pixelSize: barWindow.s(14)
                                        font.weight: Font.Bold
                                        color: mocha.subtext0
                                    }

                                    Text {
                                        anchors.verticalCenter: parent.verticalCenter
                                        text: "•"
                                        font.family: "SF Pro Display"
                                        font.pixelSize: barWindow.s(10)
                                        font.weight: Font.Bold
                                        color: mocha.subtext0
                                    }

                                    Text {
                                         id: timeText
                                         anchors.verticalCenter: parent.verticalCenter
                                         text: barWindow.timeStr
                                         font.family: "SF Pro Display"
                                         font.pixelSize: barWindow.s(18)
                                         font.weight: Font.Black
                                         color: "white"

                                         layer.enabled: true
                                         layer.effect: LinearGradient {
                                             start: Qt.point(0, 0)
                                             end: Qt.point(timeText.width, 0)
                                             gradient: Gradient {
                                                 GradientStop { 
                                                     position: 0.0
                                                     color: mocha.blue
                                                     Behavior on color { ColorAnimation { duration: 250 } }
                                                 }
                                                 GradientStop { 
                                                     position: 1.0
                                                     color: Qt.lighter(mocha.blue, 1.3)
                                                     Behavior on color { ColorAnimation { duration: 250 } }
                                                 }
                                             }
                                         }
                                     }
                                }

                                MouseArea {
                                    id: dateMouse
                                    hoverEnabled: true
                                    anchors.fill: parent
                                    onClicked: Quickshell.execDetached(["bash", "-c", "~/.config/hypr/scripts/qs_manager.sh toggle calendar"])
                                }
                            }

                 }
            }
            Rectangle {
                        id: recButton
                        property bool isHovered: recMouse.containsMouse
                        
                        color: isHovered ? Qt.rgba(mocha.text.r, mocha.text.g, mocha.text.b, 0.08) : "transparent"
                        radius: barWindow.s(6)
                        border.width: 0

                        property real targetWidth: barWindow.isRecording ? barWindow.barHeight : 0
                        width: targetWidth
                        height: barWindow.barHeight 

                        visible: targetWidth > 0 || opacity > 0
                        opacity: barWindow.isRecording ? 1.0 : 0.0
                        clip: true

                        Behavior on width { NumberAnimation { duration: 400; easing.type: Easing.OutQuint } }
                        Behavior on opacity { NumberAnimation { duration: 300 } }
                        
                        scale: isHovered ? 1.05 : 1.0
                        Behavior on scale { NumberAnimation { duration: 250; easing.type: Easing.OutExpo } }
                        Behavior on color { ColorAnimation { duration: 200 } }

                        Text {
                            id: recIcon
                            anchors.centerIn: parent
                            text: "" 
                            font.family: "Iosevka Nerd Font"
                            font.pixelSize: barWindow.s(20)
                            color: mocha.red
                            
                            SequentialAnimation on opacity {
                                running: barWindow.isRecording && !recButton.isHovered
                                loops: Animation.Infinite
                                NumberAnimation { to: 0.3; duration: 600; easing.type: Easing.InOutSine }
                                NumberAnimation { to: 1.0; duration: 600; easing.type: Easing.InOutSine }
                            }
                            SequentialAnimation on scale {
                                running: barWindow.isRecording && !recButton.isHovered
                                loops: Animation.Infinite
                                NumberAnimation { to: 1.15; duration: 600; easing.type: Easing.InOutSine }
                                NumberAnimation { to: 1.0; duration: 600; easing.type: Easing.InOutSine }
                            }
                        }
                        
                        MouseArea {
                            id: recMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            onClicked: {
                                barWindow.isRecording = false; 
                                Quickshell.execDetached(["bash", "-c", "~/.config/hypr/scripts/screenshot.sh"]); 
                            }
                        }
                    }
                }

                Rectangle {
                    id: chargeWarningBox
                    anchors.centerIn: parent
                    
                    height: barWindow.barHeight
                    width: warningRow.implicitWidth + barWindow.s(28)
                    
                    radius: barWindow.s(14)
                    color: Qt.rgba(mocha.base.r, mocha.base.g, mocha.base.b, 0.75)
                    border.width: 1
                    border.color: mocha.red
                    clip: true

                    // low-battery "Charge!" warning: turned off (the battery pill still shows the level)
                    visible: false
                    opacity: visible ? 1.0 : 0.0
                    Behavior on opacity { NumberAnimation { duration: 300 } }
                    Behavior on width { NumberAnimation { duration: 400; easing.type: Easing.OutQuint } }

                    Row {
                        id: warningRow
                        anchors.centerIn: parent
                        spacing: barWindow.s(8)

                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: "󰂃"
                            font.family: "Iosevka Nerd Font"
                            font.pixelSize: barWindow.s(16)
                            color: mocha.red
                            
                            SequentialAnimation on opacity {
                                running: chargeWarningBox.visible
                                loops: Animation.Infinite
                                NumberAnimation { to: 0.4; duration: 800; easing.type: Easing.InOutSine }
                                NumberAnimation { to: 1.0; duration: 800; easing.type: Easing.InOutSine }
                            }
                        }

                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: "Charge!"
                            font.family: "SF Pro Display"
                            font.pixelSize: barWindow.s(14)
                            font.weight: Font.Black
                            color: mocha.red
                        }
                    }
                }
            }
        }
    }
}
