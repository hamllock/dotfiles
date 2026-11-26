import QtQuick
import Quickshell
import Quickshell.Io

Item {
    id: root

    // Explicitly typed as 'color' for strict QML binding
    property color base: "#1e1e2e"
    property color mantle: "#181825"
    property color crust: "#11111b"
    property color text: "#cdd6f4"
    property color subtext0: "#a6adc8"
    property color subtext1: "#bac2de"
    property color surface0: "#313244"
    property color surface1: "#45475a"
    property color surface2: "#585b70"
    property color overlay0: "#6c7086"
    property color overlay1: "#7f849c"
    property color overlay2: "#9399b2"
    property color blue: "#89b4fa"
    property color sapphire: "#74c7ec"
    property color peach: "#fab387"
    property color green: "#40C160"
    property color red: "#EB564E"
    property color mauve: "#cba6f7"
    property color pink: "#f5c2e7"
    property color yellow: "#f9e2af"
    property color maroon: "#eba0ac"
    property color teal: "#94e2d5"

    property string rawJson: ""

    // "#rrggbb" -> grey with the same HSL lightness
    function mono(hex) {
        let m = /^#([0-9a-fA-F]{6})$/.exec(hex);
        if (!m) return hex;
        let n = parseInt(m[1], 16);
        let r = (n >> 16) & 255, g = (n >> 8) & 255, b = n & 255;
        let l = Math.round((Math.max(r, g, b) + Math.min(r, g, b)) / 2);
        let h = l.toString(16).padStart(2, "0");
        return "#" + h + h + h;
    }

    // Reload only when matugen rewrites the file (inotify; no polling, no processes).
    // The slow timer is a safety net in case a change is ever missed.
    FileView {
        id: themeFile
        path: Quickshell.env("HOME") + "/.config/hypr/scripts/quickshell/qs_colors.json"
        watchChanges: true
        onFileChanged: reload()
        onLoaded: root.apply(text())
    }
    Timer { interval: 60000; running: true; repeat: true; onTriggered: themeFile.reload() }

    function apply(raw) {
        let txt = (raw || "").trim();
        if (txt === "" || txt === root.rawJson) return;
        root.rawJson = txt;
        try {
            let c = JSON.parse(txt);
            // Monochrome: every wallpaper colour becomes the grey of the same
            // lightness, so contrast is unchanged but nothing is tinted.
            // red/green stay real red/green for contextual state (battery etc.).
            for (let k in c) if (typeof c[k] === "string") c[k] = root.mono(c[k]);
            c.red = "#EB564E";
            c.green = "#40C160";
            for (let k of ["base", "mantle", "crust", "text", "subtext0", "subtext1", "surface0", "surface1", "surface2",
                           "overlay0", "overlay1", "overlay2", "blue", "sapphire", "peach", "green", "red", "mauve",
                           "pink", "yellow", "maroon", "teal"])
                if (c[k]) root[k] = c[k];
        } catch (e) {}
    }
}
