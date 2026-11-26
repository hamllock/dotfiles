pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// CPU / RAM / temperature / network rates for the top bar and the Tools popup.
// Reads /proc and /sys directly every 2 s (no shell, no child processes): CPU and
// network are the difference between two readings. Only runs while something
// has subscribed.
Item {
    id: root

    // --- Centralized Properties ---
    property int cpu: 0
    property int ramPercent: 0
    property real ramGb: 0.0
    property int temp: 0
    property real netRx: 0
    property real netTx: 0

    // --- Lifecycle Management ---
    property int subscribers: 0

    function subscribe() {
        subscribers++;
        if (subscribers === 1) {
            if (root.tempPath === "") tempFinder.running = true;
            root.tick();
            fetchTimer.restart();
        }
    }

    function unsubscribe() {
        subscribers = Math.max(0, subscribers - 1);
        if (subscribers === 0) fetchTimer.stop();
    }

    Timer {
        id: fetchTimer
        interval: 2000
        repeat: true
        running: false
        onTriggered: root.tick()
    }

    function tick() {
        statFile.reload();
        netFile.reload();
        memFile.reload();
        if (root.tempPath !== "") tempFile.reload();
    }

    // ---- CPU: /proc/stat "cpu" line, busy share since the last reading ----
    property var lastCpu: null
    FileView {
        id: statFile
        path: "/proc/stat"
        onLoaded: {
            let f = text().split("\n")[0].trim().split(/\s+/).slice(1, 9).map(Number);
            let idle = f[3] + f[4];
            let total = f.reduce((a, b) => a + b, 0);
            if (root.lastCpu) {
                let dt = total - root.lastCpu.total, di = idle - root.lastCpu.idle;
                if (dt > 0) root.cpu = Math.round(100 * (dt - di) / dt);
            }
            root.lastCpu = { total: total, idle: idle };
        }
    }

    // ---- Network: bytes on ethernet / wifi interfaces since the last reading ----
    property var lastNet: null
    FileView {
        id: netFile
        path: "/proc/net/dev"
        onLoaded: {
            let rx = 0, tx = 0;
            for (let line of text().split("\n").slice(2)) {
                let m = line.trim().match(/^([^:]+):\s*(.*)$/);
                if (!m || !/^[ew]/i.test(m[1])) continue;
                let v = m[2].split(/\s+/).map(Number);
                rx += v[0]; tx += v[8];
            }
            let now = Date.now();
            if (root.lastNet) {
                let secs = (now - root.lastNet.t) / 1000;
                if (secs > 0) {
                    root.netRx = Math.max(0, (rx - root.lastNet.rx) / secs);
                    root.netTx = Math.max(0, (tx - root.lastNet.tx) / secs);
                }
            }
            root.lastNet = { rx: rx, tx: tx, t: now };
        }
    }

    // ---- RAM: MemTotal - MemAvailable ----
    FileView {
        id: memFile
        path: "/proc/meminfo"
        onLoaded: {
            let total = 0, avail = 0;
            for (let line of text().split("\n")) {
                if (line.indexOf("MemTotal:") === 0) total = parseInt(line.split(/\s+/)[1]);
                else if (line.indexOf("MemAvailable:") === 0) avail = parseInt(line.split(/\s+/)[1]);
            }
            if (total > 0) {
                let used = total - avail;
                root.ramPercent = Math.round(100 * used / total);
                root.ramGb = Math.round(used / 1024 / 1024 * 10) / 10;
            }
        }
    }

    // ---- Temperature: CPU sensor found once, then read like the rest ----
    property string tempPath: ""
    Process {
        id: tempFinder
        command: ["bash", "-c",
            "for h in /sys/class/hwmon/hwmon*; do n=$(cat $h/name 2>/dev/null); " +
            "case $n in coretemp|k10temp|zenpower|cpu_thermal|bcm2835_thermal) [ -f $h/temp1_input ] && { echo $h/temp1_input; exit; };; esac; done; " +
            "for z in /sys/class/thermal/thermal_zone*; do t=$(cat $z/type 2>/dev/null); " +
            "case $t in x86_pkg_temp|cpu_thermal|cpu-thermal) echo $z/temp; exit;; esac; done; " +
            "[ -f /sys/class/thermal/thermal_zone0/temp ] && echo /sys/class/thermal/thermal_zone0/temp"]
        stdout: StdioCollector {
            onStreamFinished: { root.tempPath = this.text.trim(); if (root.tempPath !== "") tempFile.reload(); }
        }
    }
    FileView {
        id: tempFile
        path: root.tempPath
        onLoaded: {
            let raw = parseInt(text());
            if (!isNaN(raw)) root.temp = raw > 1000 ? Math.round(raw / 1000) : raw;
        }
    }
}
