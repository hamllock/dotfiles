.pragma library

function getScale(mw, mh, userScale) {
    if (arguments.length === 2) {
        userScale = mh;
        mh = mw * (1080.0 / 1920.0);
    }

    if (mw <= 0 || mh <= 0) return 1.0;
    
    let rw = mw / 1920.0;
    let rh = mh / 1080.0;
    let r = Math.min(rw, rh);
    
    let baseScale = 1.0;
    
    if (r <= 1.0) {
        baseScale = Math.max(0.35, Math.pow(r, 0.85));
    } else {
        baseScale = Math.pow(r, 0.5);
    }
    
    return baseScale * (userScale !== undefined ? userScale : 1.0);
}

function s(val, scale) {
    return Math.round(val * scale);
}

function getLayout(name, mx, my, mw, mh, userScale) {
    let scale = getScale(mw, mh, userScale);

    let base = {
        // --- Top Right Popups ---
        "battery":   { w: s(480, scale), h: s(560, scale), rx: mw - s(484, scale), ry: s(60, scale), comp: "battery/BatteryPopup.qml" },
        "claude":    { w: s(460, scale), h: s(520, scale), rx: mw - s(464, scale), ry: s(60, scale), comp: "claude/ClaudePopup.qml" },
        "wifi":      { w: s(460, scale), h: s(720, scale), rx: mw - s(464, scale), ry: s(60, scale), comp: "wifi/WifiPopup.qml" },
        "bluetooth": { w: s(460, scale), h: s(720, scale), rx: mw - s(464, scale), ry: s(60, scale), comp: "bluetooth/BluetoothPopup.qml" },
        "volume":    { w: s(450, scale), h: s(720, scale), rx: mw - s(455, scale), ry: s(60, scale), comp: "volume/VolumePopup.qml" },
        "notifications": { w: s(360, scale), h: s(640, scale), rx: mw - s(364, scale), ry: s(60, scale), comp: "notifications/NotificationCenter.qml" },
        "power":     { w: s(380, scale), h: s(380, scale), rx: mw - s(384, scale), ry: s(60, scale), comp: "power/PowerMenu.qml" },
        
        // --- Central Standard Tools ---
        "clipboard": { w: s(800, scale), h: s(700, scale), rx: Math.floor((mw/2)-(s(800, scale)/2)), ry: Math.floor((mh/2)-(s(700, scale)/2)), comp: "clipboard/ClipboardManager.qml" },

        // --- Central Large Tools ---
        "dash":      { w: s(1500, scale), h: s(1060, scale), rx: Math.floor((mw/2)-(s(1500, scale)/2)), ry: Math.floor((mh/2)-(s(1060, scale)/2)), comp: "dash/DashPopup.qml" },
        "autoclicker": { w: s(480, scale), h: s(600, scale), rx: Math.floor((mw/2)-(s(480, scale)/2)), ry: Math.floor((mh/2)-(s(600, scale)/2)), comp: "autoclicker/AutoclickerPopup.qml" },
        "settings":  { w: s(1340, scale), h: s(960, scale), rx: Math.floor((mw/2)-(s(1340, scale)/2)), ry: Math.floor((mh/2)-(s(960, scale)/2)), comp: "settings/SettingsPopup.qml" },
        "tools":     { w: s(1390, scale), h: s(770, scale), rx: Math.floor((mw/2)-(s(1390, scale)/2)), ry: Math.floor((mh/2)-(s(770, scale)/2)), comp: "tools/ToolsPopup.qml" },
        "focustime": { w: s(900, scale), h: s(700, scale), rx: Math.floor((mw/2)-(s(900, scale)/2)), ry: Math.floor((mh/2)-(s(700, scale)/2)), comp: "focustime/FocusTimePopup.qml" },

        // --- Extralarge / Custom Centered ---
        "calendar":  { w: s(1450, scale), h: s(750, scale), rx: mw - s(1455, scale), ry: s(60, scale), comp: "calendar/CalendarPopup.qml" },
        

        
        // --- Utility ---
        "hidden":    { w: 1, h: 1, rx: -5000 - mx, ry: -5000 - my, comp: "" } 
    };

    if (!base[name]) return null;
    
    let t = base[name];
    t.x = mx + t.rx;
    t.y = my + t.ry;
    
    return t;
}

function getPopupLayout(mw, mh, userScale) {
    if (arguments.length === 2) {
        userScale = mh;
        mh = mw * (1080.0 / 1920.0);
    }
    
    let scale = getScale(mw, mh, userScale);
    return {
        w: s(350, scale),
        marginTop: s(60, scale),
        marginRight: s(20, scale),
        spacing: s(12, scale),
        radius: s(24, scale), // = corner_radius of qs_popups_glass in hyprliquid.json
        padding: s(12, scale)
    };
}
