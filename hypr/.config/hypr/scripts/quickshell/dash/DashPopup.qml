import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import QtQuick.Window
import Quickshell
import Quickshell.Io
import Quickshell.Widgets
import "../"

// Startup dash: GitHub contribution heatmap + todo list.
// Opened with SUPER+G (qs_manager.sh toggle dash) and once at login.
// Heatmap data: dash/github_contrib.sh (gh api, cached 30 min).
// Todos: plain markdown checklist in ~/todo.md ("- [ ] task" / "- [x] task"),
// so it can be edited from a terminal too.
FocusScope {
    id: root

    // Main.qml hands every widget these
    property var notifModel
    property var liveNotifs
    property real layoutWidth
    property real layoutHeight

    Scaler { id: scaler; currentWidth: Screen.width; currentHeight: Screen.height }
    function s(v) { return scaler.s(v); }

    // -------------------------------------------------------------------------
    // COLORS
    // -------------------------------------------------------------------------
    MatugenColors { id: _theme }
    readonly property color base: _theme.base
    readonly property color text: _theme.text
    readonly property color subtext0: _theme.subtext0
    readonly property color overlay0: _theme.overlay0
    readonly property color surface0: _theme.surface0
    readonly property color surface1: _theme.surface1
    readonly property color green: _theme.green
    readonly property color red: _theme.red

    readonly property string uiFont: "SF Pro Display"
    readonly property string monoFont: "Maple Mono Normal NF"

    function heat(level) {
        if (level <= 0) return Qt.rgba(root.text.r, root.text.g, root.text.b, 0.07);
        // GitHub's own dark-mode contribution greens, a touch less saturated
        return ["", "#133F29", "#0B6233", "#339948", "#48C45D"][Math.min(level, 4)];
    }

    // -------------------------------------------------------------------------
    // INTRO ANIMATIONS
    // -------------------------------------------------------------------------
    property real introMain: 0
    property real introHeader: 0
    property real introTodo: 0
    property real gridIntro: 0       // 0..1, drives the per-cell wave

    ParallelAnimation {
        running: true
        NumberAnimation { target: root; property: "introMain"; from: 0; to: 1; duration: 700; easing.type: Easing.OutQuart }
        SequentialAnimation {
            PauseAnimation { duration: 80 }
            NumberAnimation { target: root; property: "introHeader"; from: 0; to: 1; duration: 700; easing.type: Easing.OutBack; easing.overshoot: 1.0 }
        }
        SequentialAnimation {
            PauseAnimation { duration: 220 }
            NumberAnimation { target: root; property: "introTodo"; from: 0; to: 1; duration: 750; easing.type: Easing.OutExpo }
        }
    }

    NumberAnimation {
        id: gridWave
        target: root; property: "gridIntro"; from: 0; to: 1
        duration: 1400; easing.type: Easing.Linear
    }

    // per-cell delay (ms) along a diagonal sweep, then a 320ms springy pop
    readonly property real waveSpan: 53 * 16 + 7 * 30 + 320
    function cellProgress(col, row) {
        let t = (root.gridIntro * root.waveSpan - (col * 16 + row * 30)) / 320;
        t = Math.max(0, Math.min(1, t));
        let c1 = 1.9, c3 = c1 + 1, u = t - 1;
        return 1 + c3 * u * u * u + c1 * u * u;   // easeOutBack
    }

    // -------------------------------------------------------------------------
    // CLOCK / GREETING
    // -------------------------------------------------------------------------
    property var now: new Date()
    Timer { interval: 1000; running: true; repeat: true; onTriggered: root.now = new Date() }

    readonly property string greeting: {
        let h = root.now.getHours();
        if (h < 5) return "Up late";
        if (h < 12) return "Good morning";
        if (h < 18) return "Good afternoon";
        return "Good evening";
    }
    property string userName: Quickshell.env("USER")

    // -------------------------------------------------------------------------
    // GITHUB DATA
    // -------------------------------------------------------------------------
    readonly property string contribScript: Quickshell.env("HOME") + "/.config/hypr/scripts/quickshell/dash/github_contrib.sh"

    property var days: []            // [{d, c, l, col, row}]
    property var cellIndex: ({})     // "col,row" -> day
    property var monthLabels: []     // [{col, name}]
    property int weekCount: 53
    property string ghLogin: ""
    property int ghTotal: 0
    property int streakNow: 0
    property int streakBest: 0
    property int bestDayCount: 0
    property string bestDayDate: ""
    property string ghError: ""
    property bool loading: false
    property var hoverDay: null
    property bool forceNext: false

    Process {
        id: ghFetch
        command: ["bash", root.contribScript]
        stdout: StdioCollector {
            onStreamFinished: root.ingest(this.text)
        }
        onRunningChanged: root.loading = running
    }

    // LeetCode daily problem (dash/leetcode_daily.sh, public API, cached for the day)
    readonly property string dashDir: Quickshell.env("HOME") + "/.config/hypr/scripts/quickshell/dash"
    property var lcDaily: ({})
    Process {
        id: lcFetch
        command: ["bash", root.dashDir + "/leetcode_daily.sh"]
        stdout: StdioCollector {
            onStreamFinished: { try { root.lcDaily = JSON.parse(this.text); } catch (e) {} }
        }
    }
    // LeetCode solution language (leetcode/lc.py lang; only languages nvim has a server for)
    property string lcLang: "cpp"
    readonly property var lcLangs: [
        { v: "cpp", l: "C++", i: 0xF0672 }, { v: "c", l: "C", i: 0xF0671 }, { v: "python3", l: "Python", i: 0xF0320 },
        { v: "javascript", l: "JavaScript", i: 0xF031E }, { v: "typescript", l: "TypeScript", i: 0xF06E6 },
        { v: "rust", l: "Rust", i: 0xF1617 }, { v: "php", l: "PHP", i: 0xF031F }
    ]
    readonly property var lcLangCur: lcLangs.find(x => x.v === lcLang) || lcLangs[0]
    property bool lcLangOpen: false
    readonly property string lcPy: root.dashDir + "/../leetcode/lc.py"
    Process {
        id: lcLangFetch
        command: ["python3", "-I", root.lcPy, "lang"]
        running: true
        stdout: StdioCollector {
            onStreamFinished: { try { let d = JSON.parse(this.text); if (d.lang) root.lcLang = d.lang; } catch (e) {} }
        }
    }
    function setLcLang(v) {
        root.lcLang = v;
        root.lcLangOpen = false;
        Quickshell.execDetached(["python3", "-I", root.lcPy, "lang", v]);
    }

    // LeetCode profile: solved counts + 53-week submission calendar (dash/leetcode_stats.py)
    property var lcStats: ({})
    property var lcDays: []
    property var lcCellIndex: ({})
    property var lcMonths: []
    property var lcHover: null
    property real lcIntro: 0
    NumberAnimation { id: lcWave; target: root; property: "lcIntro"; from: 0; to: 1; duration: 1400 }
    function lcProgress(col, row) {
        let t = (root.lcIntro * root.waveSpan - (col * 16 + row * 30)) / 320;
        t = Math.max(0, Math.min(1, t));
        let c1 = 1.9, c3 = c1 + 1, u = t - 1;
        return 1 + c3 * u * u * u + c1 * u * u;
    }
    readonly property color lcOrange: "#FFA116"
    function lcHeat(level) {
        if (level <= 0) return Qt.rgba(root.text.r, root.text.g, root.text.b, 0.07);
        return Qt.alpha(root.lcOrange, [0, 0.32, 0.55, 0.78, 1.0][level]);
    }
    Process {
        id: lcStatsFetch
        command: ["python3", "-I", root.dashDir + "/leetcode_stats.py"]
        stdout: StdioCollector {
            onStreamFinished: {
                let d; try { d = JSON.parse(this.text); } catch (e) { return; }
                root.lcStats = d;
                if (!d.weeks) return;
                const MONTHS = ["Jan","Feb","Mar","Apr","May","Jun","Jul","Aug","Sep","Oct","Nov","Dec"];
                let out = [], idx = {}, months = [], lastMonth = -1;
                for (let w = 0; w < d.weeks.length; w++) {
                    for (let i = 0; i < d.weeks[w].length; i++) {
                        let day = d.weeks[w][i];
                        let dt = new Date(day.d + "T00:00:00Z");
                        let cell = { d: day.d, c: day.c, l: day.l, col: w, row: dt.getUTCDay() };
                        out.push(cell);
                        idx[w + "," + cell.row] = cell;
                        if (cell.row === 0 || (w === 0 && i === 0)) {
                            let m = dt.getUTCMonth();
                            if (m !== lastMonth) {
                                if (!(months.length && w - months[months.length - 1].col < 3)) months.push({ col: w, name: MONTHS[m] });
                                lastMonth = m;
                            }
                        }
                    }
                }
                root.lcCellIndex = idx;
                root.lcMonths = months;
                root.lcDays = out;
                root.lcIntro = 0;
                lcWave.restart();
            }
        }
    }

    // -------------------------------------------------------------------------
    // GYM (~/gym.md, logged by hand: one "YYYY-MM-DD optional note" line per session)
    // Click a heatmap cell to toggle that day; "Log today" / Enter logs today.
    // dash/gym.sh does the same from a terminal.
    // -------------------------------------------------------------------------
    readonly property string gymPath: Quickshell.env("HOME") + "/gym.md"
    readonly property int gymGoal: 5                // sessions per week that keep the week streak alive
    readonly property color gymColor: "#FF375F"
    property var gymEntries: []      // [{d, n}] newest first
    property bool gymLoaded: false
    property var gymDays: []
    property var gymCellIndex: ({})
    property var gymMonths: []
    property var gymHover: null
    property real gymIntro: 0
    property int gymTotal: 0
    property int gymThisWeek: 0
    property int gymWeekStreak: 0
    property int gymBestWeekStreak: 0
    property var gymLast: null
    property bool gymToday: false
    NumberAnimation { id: gymWave; target: root; property: "gymIntro"; from: 0; to: 1; duration: 1400 }
    function gymProgress(col, row) {
        let t = (root.gymIntro * root.waveSpan - (col * 16 + row * 30)) / 320;
        t = Math.max(0, Math.min(1, t));
        let c1 = 1.9, c3 = c1 + 1, u = t - 1;
        return 1 + c3 * u * u * u + c1 * u * u;
    }
    function gymHeat(level) {
        if (level <= 0) return Qt.rgba(root.text.r, root.text.g, root.text.b, 0.07);
        return Qt.alpha(root.gymColor, [0, 0.32, 0.55, 0.78, 1.0][level]);
    }
    function isoDate(dt) {
        let p = (n) => (n < 10 ? "0" : "") + n;
        return dt.getFullYear() + "-" + p(dt.getMonth() + 1) + "-" + p(dt.getDate());
    }

    Process {
        id: gymReader
        command: ["bash", "-c", "cat \"$1\" 2>/dev/null", "_", root.gymPath]
        stdout: StdioCollector {
            onStreamFinished: {
                let out = [];
                let lines = this.text.split("\n");
                for (let i = 0; i < lines.length; i++) {
                    let m = /^\s*(?:[-*]\s+)?(\d{4}-\d{2}-\d{2})\s*(.*)$/.exec(lines[i]);
                    if (m) out.push({ d: m[1], n: m[2].trim() });
                }
                root.gymEntries = out;
                root.gymLoaded = true;
                root.gymBuild(true);
            }
        }
    }
    Process { id: gymWriter }

    function gymSave() {
        if (!root.gymLoaded) return;
        let sorted = root.gymEntries.slice().sort((a, b) => a.d < b.d ? 1 : a.d > b.d ? -1 : 0);
        root.gymEntries = sorted;
        let body = sorted.map(e => e.d + (e.n ? " " + e.n : "")).join("\n");
        if (body) body += "\n";
        gymWriter.running = false;
        gymWriter.command = ["bash", "-c", "printf '%s' \"$2\" > \"$1.tmp\" && mv \"$1.tmp\" \"$1\"", "_", root.gymPath, body];
        gymWriter.running = true;
        root.gymBuild(false);
    }
    function gymToggleDay(d) {
        if (d > root.isoDate(new Date())) return;      // no logging the future
        let has = root.gymEntries.some(e => e.d === d);
        root.gymEntries = has ? root.gymEntries.filter(e => e.d !== d)
                              : root.gymEntries.concat([{ d: d, n: "" }]);
        root.gymSave();
    }
    // Enter / button: log today with an optional note (updates the note if already logged)
    function gymLogToday(note) {
        let d = root.isoDate(new Date());
        note = (note || "").trim();
        if (root.gymEntries.some(e => e.d === d)) {
            if (note === "") { root.gymToggleDay(d); return; }   // button on a logged day = undo
            root.gymEntries = root.gymEntries.map(e => e.d === d ? { d: e.d, n: note } : e);
        } else {
            root.gymEntries = root.gymEntries.concat([{ d: d, n: note }]);
        }
        root.gymSave();
    }

    function gymBuild(animate) {
        let perDay = {};
        for (let i = 0; i < root.gymEntries.length; i++) {
            let e = root.gymEntries[i];
            if (!perDay[e.d]) perDay[e.d] = { c: 0, notes: [] };
            perDay[e.d].c++;
            if (e.n) perDay[e.d].notes.push(e.n);
        }
        // 53 Sunday-first columns ending today, same shape as GitHub/LeetCode
        const MONTHS = ["Jan","Feb","Mar","Apr","May","Jun","Jul","Aug","Sep","Oct","Nov","Dec"];
        let now = new Date();
        let today = new Date(now.getFullYear(), now.getMonth(), now.getDate());
        let startOff = today.getDay() + 52 * 7;
        let out = [], idx = {}, months = [], lastMonth = -1, weekCounts = [];
        let total = 0, last = null;
        for (let i = 0; i <= startOff; i++) {
            let dt = new Date(today.getFullYear(), today.getMonth(), today.getDate() - startOff + i);
            let col = Math.floor(i / 7), row = dt.getDay();
            let d = root.isoDate(dt);
            let pd = perDay[d];
            let c = pd ? pd.c : 0;
            let cell = { d: d, c: c, l: c > 0 ? 4 : 0, n: pd ? pd.notes.join(", ") : "", col: col, row: row };
            out.push(cell);
            idx[col + "," + row] = cell;
            if (weekCounts.length <= col) weekCounts.push(0);
            if (c > 0) { weekCounts[col]++; total++; last = cell; }
            if (row === 0) {
                let m = dt.getMonth();
                if (m !== lastMonth) {
                    if (!(months.length && col - months[months.length - 1].col < 3)) months.push({ col: col, name: MONTHS[m] });
                    lastMonth = m;
                }
            }
        }
        // week streak: consecutive weeks hitting the goal (this week counts once it's hit)
        let best = 0, run = 0;
        for (let w = 0; w < weekCounts.length; w++) {
            if (weekCounts[w] >= root.gymGoal) { run++; best = Math.max(best, run); } else run = 0;
        }
        let cur = 0, w = weekCounts.length - 1;
        if (w >= 0 && weekCounts[w] < root.gymGoal) w--;
        while (w >= 0 && weekCounts[w] >= root.gymGoal) { cur++; w--; }

        root.gymTotal = total;
        root.gymThisWeek = weekCounts.length ? weekCounts[weekCounts.length - 1] : 0;
        root.gymWeekStreak = cur;
        root.gymBestWeekStreak = best;
        root.gymLast = last;
        root.gymToday = !!perDay[root.isoDate(today)];
        root.gymCellIndex = idx;
        root.gymMonths = months;
        root.gymDays = out;
        if (animate) { root.gymIntro = 0; gymWave.restart(); }
    }

    function lcColor(d) {
        if (d === "Easy") return "#40C160";
        if (d === "Medium") return "#FFB340";
        if (d === "Hard") return "#EB564E";
        return root.subtext0;
    }

    // GitHub avatar (dash/github_avatar.sh, cached a day)
    readonly property string avatarScript: Quickshell.env("HOME") + "/.config/hypr/scripts/quickshell/dash/github_avatar.sh"
    property string avatarPath: ""
    property int avatarRev: 0
    Process {
        id: avatarFetch
        command: ["bash", root.avatarScript]
        stdout: StdioCollector {
            onStreamFinished: {
                let p = this.text.trim();
                if (p !== "") { root.avatarPath = p; root.avatarRev++; }
            }
        }
    }

    function refresh(force) {
        if (ghFetch.running) return;
        ghFetch.command = force ? ["bash", root.contribScript, "--force"] : ["bash", root.contribScript];
        ghFetch.running = true;
        if (force && !lcStatsFetch.running) {
            lcStatsFetch.command = ["python3", "-I", root.dashDir + "/leetcode_stats.py", "--force"];
            lcStatsFetch.running = true;
        }
        if (force && !gymReader.running) gymReader.running = true;   // pick up edits made in a terminal
        if (!avatarFetch.running) {
            avatarFetch.command = force ? ["bash", root.avatarScript, "--force"] : ["bash", root.avatarScript];
            avatarFetch.running = true;
        }
    }

    function ingest(txt) {
        let data;
        try { data = JSON.parse(txt); } catch (e) { root.ghError = "couldn't parse GitHub data"; return; }
        if (data.error) { root.ghError = data.error; return; }
        root.ghError = "";

        const MONTHS = ["Jan","Feb","Mar","Apr","May","Jun","Jul","Aug","Sep","Oct","Nov","Dec"];
        let out = [], idx = {}, months = [], lastMonth = -1;
        let flat = [];
        for (let w = 0; w < data.weeks.length; w++) {
            let wk = data.weeks[w];
            for (let i = 0; i < wk.length; i++) {
                let day = wk[i];
                let dt = new Date(day.d + "T00:00:00Z");
                let cell = { d: day.d, c: day.c, l: day.l, col: w, row: dt.getUTCDay() };
                out.push(cell);
                idx[w + "," + cell.row] = cell;
                flat.push(cell);
                if (cell.row === 0 || (w === 0 && i === 0)) {
                    let m = dt.getUTCMonth();
                    if (m !== lastMonth) {
                        // skip a label squeezed against the previous one
                        if (!(months.length && w - months[months.length - 1].col < 3)) months.push({ col: w, name: MONTHS[m] });
                        lastMonth = m;
                    }
                }
            }
        }

        // streaks + best day
        let best = 0, run = 0, bestC = 0, bestD = "";
        for (let i = 0; i < flat.length; i++) {
            if (flat[i].c > 0) { run++; best = Math.max(best, run); } else run = 0;
            if (flat[i].c > bestC) { bestC = flat[i].c; bestD = flat[i].d; }
        }
        let cur = 0, j = flat.length - 1;
        if (j >= 0 && flat[j].c === 0) j--;           // today not done yet: streak still alive
        while (j >= 0 && flat[j].c > 0) { cur++; j--; }

        root.weekCount = data.weeks.length;
        root.ghLogin = data.login;
        root.ghTotal = data.total;
        root.streakNow = cur;
        root.streakBest = best;
        root.bestDayCount = bestC;
        root.bestDayDate = bestD;
        root.cellIndex = idx;
        root.monthLabels = months;
        root.days = out;
        root.gridIntro = 0;
        gridWave.restart();
    }

    function prettyDate(iso) {
        if (!iso) return "";
        let d = new Date(iso + "T00:00:00");
        return d.toLocaleDateString(Qt.locale("en_US"), "ddd, MMM d");
    }

    // -------------------------------------------------------------------------
    // TODOS (~/todo.md)
    // -------------------------------------------------------------------------
    readonly property string todoPath: Quickshell.env("HOME") + "/todo.md"
    ListModel { id: todoModel }
    property bool todosLoaded: false
    readonly property int openCount: { root.modelRev; let n = 0; for (let i = 0; i < todoModel.count; i++) if (!todoModel.get(i).done) n++; return n; }
    property bool todoBulk: false
    property int modelRev: 0   // bumped on every change so openCount re-evaluates

    Process {
        id: todoReader
        command: ["bash", "-c", "cat \"$1\" 2>/dev/null", "_", root.todoPath]
        stdout: StdioCollector {
            onStreamFinished: {
                // bulk reload: no per-row animations. A row still sliding in when the row
                // height settles keeps its old y and ends up on top of another (Qt ListView)
                root.todoBulk = true;
                todoModel.clear();
                let lines = this.text.split("\n");
                for (let i = 0; i < lines.length; i++) {
                    let line = lines[i];
                    if (line.trim() === "") continue;
                    let m = /^\s*[-*]\s*\[([ xX])\]\s?(.*)$/.exec(line);
                    if (m) todoModel.append({ text: m[2], done: m[1] !== " " });
                    else todoModel.append({ text: line.replace(/^\s*[-*]\s+/, ""), done: false });
                }
                root.todosLoaded = true;
                root.modelRev++;
                Qt.callLater(() => root.todoBulk = false);
            }
        }
    }

    Process {
        id: todoWriter
        onRunningChanged: if (!running && root.saveAgain) { root.saveAgain = false; root.saveTodos(); }
    }
    property bool saveAgain: false

    Timer { id: saveDebounce; interval: 120; onTriggered: root.saveTodos() }

    function saveTodos() {
        if (!root.todosLoaded) return;
        if (todoWriter.running) { root.saveAgain = true; return; }
        let lines = [];
        for (let i = 0; i < todoModel.count; i++) {
            let t = todoModel.get(i);
            lines.push("- [" + (t.done ? "x" : " ") + "] " + t.text);
        }
        let body = lines.length ? lines.join("\n") + "\n" : "";
        todoWriter.command = ["bash", "-c", "printf '%s' \"$2\" > \"$1.tmp\" && mv \"$1.tmp\" \"$1\"", "_", root.todoPath, body];
        todoWriter.running = true;
    }

    function changed() { root.modelRev++; saveDebounce.restart(); }

    function addTodo(t) {
        t = t.trim();
        if (t === "") return;
        todoModel.insert(0, { text: t, done: false });
        changed();
    }
    function toggleTodo(i) { todoModel.setProperty(i, "done", !todoModel.get(i).done); changed(); }
    function removeTodo(i) { todoModel.remove(i); changed(); }
    function clearDone() {
        for (let i = todoModel.count - 1; i >= 0; i--) if (todoModel.get(i).done) todoModel.remove(i);
        changed();
    }

    // drag-to-reorder: the grip moves the row live through the model while the
    // pointer crosses row boundaries; saved once on release
    property int dragIndex: -1
    property real dragPointerY: 0     // pointer y in the list's viewport
    property int dragEdge: 0          // -1/1 while near the top/bottom edge (auto-scroll)

    function dragTrack(area, m) {
        let p = area.mapToItem(todoList, m.x, m.y);
        root.dragPointerY = p.y;
        let zone = root.s(36);
        root.dragEdge = p.y < zone ? -1 : (p.y > todoList.height - zone ? 1 : 0);
        dragReorder();
    }
    function dragReorder() {
        if (root.dragIndex < 0) return;
        let y = root.dragPointerY + todoList.contentY;
        let target = Math.max(0, Math.min(todoModel.count - 1, Math.floor(y / todoList.pitch)));
        if (target !== root.dragIndex) {
            todoModel.move(root.dragIndex, target, 1);
            root.dragIndex = target;
        }
    }
    function dragEnd() {
        if (root.dragIndex < 0) return;
        root.dragIndex = -1;
        root.dragEdge = 0;
        changed();
    }

    Component.onCompleted: {
        lcFetch.running = true;
        lcStatsFetch.running = true;
        refresh(false);
        todoReader.running = true;
        gymReader.running = true;
    }

    // -------------------------------------------------------------------------
    // UI
    // -------------------------------------------------------------------------
    Item {
        anchors.fill: parent
        scale: 0.92 + 0.08 * root.introMain
        opacity: root.introMain
        transform: Translate { y: root.s(15) * (1 - root.introMain) }

        // liquid glass: radius must match qs-master corner_radius (config/hyprliquid.json);
        // near-clear fill, the glass tint does the colouring
        Rectangle {
            anchors.fill: parent
            radius: 48
            color: Qt.rgba(root.base.r, root.base.g, root.base.b, 0.06)
        }

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: root.s(36)
            spacing: root.s(20)

            // ---------------- HEADER ----------------
            RowLayout {
                Layout.fillWidth: true
                opacity: root.introHeader
                transform: Translate { y: root.s(-18) * (1 - root.introHeader) }
                spacing: root.s(16)

                // GitHub avatar: click opens your profile
                Item {
                    Layout.preferredWidth: root.s(58)
                    Layout.preferredHeight: root.s(58)
                    visible: root.avatarPath !== ""
                    scale: avatarMa.containsMouse ? 1.06 : 1.0
                    Behavior on scale { NumberAnimation { duration: 220; easing.type: Easing.OutBack } }

                    Rectangle {   // soft ring
                        anchors.fill: parent
                        anchors.margins: -root.s(3)
                        radius: width / 2
                        color: "transparent"
                        border.width: root.s(2)
                        border.color: Qt.rgba(root.text.r, root.text.g, root.text.b, avatarMa.containsMouse ? 0.45 : 0.18)
                        Behavior on border.color { ColorAnimation { duration: 180 } }
                    }
                    ClippingRectangle {
                        anchors.fill: parent
                        radius: width / 2
                        color: root.surface0
                        Image {
                            anchors.fill: parent
                            source: root.avatarPath !== "" ? "file://" + root.avatarPath + "?r=" + root.avatarRev : ""
                            fillMode: Image.PreserveAspectCrop
                            sourceSize.width: root.s(116); sourceSize.height: root.s(116)
                            smooth: true; mipmap: true
                            cache: false
                        }
                    }
                    MouseArea {
                        id: avatarMa
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: if (root.ghLogin !== "") Quickshell.execDetached(["xdg-open", "https://github.com/" + root.ghLogin])
                    }
                }

                Column {
                    Layout.fillWidth: true
                    spacing: root.s(2)
                    Text {
                        text: root.greeting + ", " + root.userName
                        color: root.text
                        font.family: root.uiFont; font.weight: Font.Bold; font.pixelSize: root.s(30)
                    }
                    Text {
                        text: root.now.toLocaleDateString(Qt.locale("en_US"), "dddd, MMMM d")
                        color: root.subtext0
                        font.family: root.uiFont; font.pixelSize: root.s(15)
                    }
                }

                // Quick launch: popups that otherwise only have keybinds
                RowLayout {
                    Layout.alignment: Qt.AlignVCenter
                    spacing: root.s(8)
                    Repeater {
                        model: [
                            { label: "Tools",      icon: 0xF1064, target: "tools" },
                            { label: "Focus time", icon: 0xF051B, target: "focustime" },
                            { label: "Settings",   icon: 0xF0493, target: "settings" }
                        ]
                        Rectangle {
                            Layout.preferredWidth: quickRow.implicitWidth + root.s(36)
                            Layout.preferredHeight: root.s(38)
                            radius: height / 2
                            color: Qt.rgba(root.text.r, root.text.g, root.text.b, quickMa.containsMouse ? 0.12 : 0.06)
                            border.width: 1
                            border.color: Qt.rgba(root.text.r, root.text.g, root.text.b, 0.12)
                            scale: quickMa.pressed ? 0.96 : quickMa.containsMouse ? 1.03 : 1.0
                            Behavior on color { ColorAnimation { duration: 150 } }
                            Behavior on scale { NumberAnimation { duration: 200; easing.type: Easing.OutBack } }
                            Row {
                                id: quickRow
                                anchors.centerIn: parent
                                spacing: root.s(9)
                                Text {
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: String.fromCodePoint(modelData.icon)
                                    color: root.subtext0
                                    font.family: root.monoFont; font.pixelSize: root.s(15)
                                }
                                Text {
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: modelData.label
                                    color: root.text
                                    font.family: root.uiFont; font.weight: Font.DemiBold; font.pixelSize: root.s(14)
                                }
                            }
                            MouseArea {
                                id: quickMa
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: Quickshell.execDetached(["bash", Quickshell.env("HOME") + "/.config/hypr/scripts/qs_manager.sh", "toggle", modelData.target])
                            }
                        }
                    }
                }

                Text {
                    text: Qt.formatTime(root.now, "hh:mm")
                    color: root.text
                    font.family: root.uiFont; font.weight: Font.Black; font.pixelSize: root.s(44)
                    font.letterSpacing: root.s(-1)
                }
            }

            // cards side by side: heatmap left, todo right (full height = more tasks)
            RowLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: root.s(20)

            ColumnLayout {
            Layout.preferredWidth: root.s(960)
            Layout.maximumWidth: root.s(960)
            Layout.fillHeight: true
            spacing: root.s(20)

            // ---------------- HEATMAP CARD ----------------
            Rectangle {
                id: heatCard
                Layout.fillWidth: true
                Layout.preferredHeight: heatCol.implicitHeight + root.s(48)
                radius: root.s(26)
                color: Qt.rgba(root.base.r, root.base.g, root.base.b, 0.55)
                border.width: 1
                border.color: Qt.rgba(root.text.r, root.text.g, root.text.b, 0.07)
                opacity: root.introHeader
                transform: Translate { y: root.s(20) * (1 - root.introHeader) }

                Column {
                    id: heatCol
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.margins: root.s(24)
                    spacing: root.s(18)

                    // title row
                    Item {
                        width: parent.width
                        height: root.s(24)
                        Row {
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: root.s(10)
                            Text {
                                text: ""
                                color: root.text
                                font.family: root.monoFont; font.pixelSize: root.s(20)
                                anchors.verticalCenter: parent.verticalCenter
                            }
                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                color: root.subtext0
                                font.family: root.uiFont; font.pixelSize: root.s(15)
                                textFormat: Text.StyledText
                                text: root.ghError !== "" ? root.ghError
                                    : root.ghLogin === "" ? "Loading contributions…"
                                    : "<b><font color='" + root.text + "'>" + root.ghTotal + "</font></b> contributions in the last year · " + root.ghLogin
                            }
                        }
                        // refresh
                        Text {
                            id: refreshIcon
                            anchors.right: parent.right
                            anchors.verticalCenter: parent.verticalCenter
                            text: ""
                            color: refreshMa.containsMouse ? root.text : root.overlay0
                            font.family: root.monoFont; font.pixelSize: root.s(16)
                            Behavior on color { ColorAnimation { duration: 150 } }
                            RotationAnimation on rotation {
                                running: root.loading
                                from: 0; to: 360; duration: 900; loops: Animation.Infinite
                                onRunningChanged: if (!running) refreshIcon.rotation = 0
                            }
                            MouseArea {
                                id: refreshMa
                                anchors.fill: parent; anchors.margins: -root.s(8)
                                hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                onClicked: root.refresh(true)
                            }
                        }
                    }

                    // grid with month + weekday labels
                    Item {
                        id: gridArea
                        width: parent.width
                        readonly property real labelW: root.s(34)
                        readonly property real pitch: Math.floor((width - labelW) / root.weekCount)
                        readonly property real gap: Math.max(2, Math.round(pitch * 0.2))
                        readonly property real cell: pitch - gap
                        height: root.s(18) + pitch * 7

                        // month labels
                        Repeater {
                            model: root.monthLabels
                            Text {
                                x: gridArea.labelW + modelData.col * gridArea.pitch
                                y: 0
                                text: modelData.name
                                color: root.subtext0
                                font.family: root.uiFont; font.pixelSize: root.s(12)
                                opacity: Math.min(1, root.gridIntro * 3)
                            }
                        }
                        // weekday labels
                        Repeater {
                            model: [[1, "Mon"], [3, "Wed"], [5, "Fri"]]
                            Text {
                                x: 0
                                y: root.s(18) + modelData[0] * gridArea.pitch + (gridArea.cell - height) / 2
                                text: modelData[1]
                                color: root.subtext0
                                font.family: root.uiFont; font.pixelSize: root.s(11)
                                opacity: Math.min(1, root.gridIntro * 3)
                            }
                        }

                        Item {
                            id: cells
                            x: gridArea.labelW
                            y: root.s(18)
                            width: gridArea.pitch * root.weekCount
                            height: gridArea.pitch * 7

                            Repeater {
                                model: root.days
                                Rectangle {
                                    readonly property real p: root.cellProgress(modelData.col, modelData.row)
                                    readonly property bool isHover: root.hoverDay !== null && root.hoverDay.d === modelData.d
                                    readonly property bool isToday: index === root.days.length - 1
                                    x: modelData.col * gridArea.pitch
                                    y: modelData.row * gridArea.pitch
                                    width: gridArea.cell
                                    height: gridArea.cell
                                    radius: Math.max(2, gridArea.cell * 0.28)
                                    color: root.heat(modelData.l)
                                    scale: p * (isHover ? 1.35 : 1.0)
                                    opacity: Math.min(1, p * 1.5)
                                    border.width: isToday ? 1 : 0
                                    border.color: root.text
                                    z: isHover ? 2 : 1
                                    Behavior on scale { enabled: root.gridIntro >= 1; NumberAnimation { duration: 140; easing.type: Easing.OutBack } }
                                }
                            }

                            MouseArea {
                                anchors.fill: parent
                                hoverEnabled: true
                                onPositionChanged: (m) => {
                                    let c = Math.floor(m.x / gridArea.pitch), r = Math.floor(m.y / gridArea.pitch);
                                    let d = root.cellIndex[c + "," + r];
                                    root.hoverDay = d ? d : null;
                                }
                                onExited: root.hoverDay = null
                            }
                        }
                    }

                    // stats
                    Row {
                        width: parent.width
                        spacing: root.s(10)
                        Repeater {
                            model: [
                                { icon: "", label: "Current streak", value: root.streakNow + (root.streakNow === 1 ? " day" : " days") },
                                { icon: "", label: "Longest streak", value: root.streakBest + (root.streakBest === 1 ? " day" : " days") },
                                { icon: "", label: "Best day", value: root.bestDayCount + " · " + root.prettyDate(root.bestDayDate) },
                                { icon: "", label: "This year", value: root.ghTotal + " total" }
                            ]
                            Rectangle {
                                width: (parent.width - root.s(30)) / 4
                                height: root.s(54)
                                radius: root.s(16)
                                color: Qt.rgba(root.text.r, root.text.g, root.text.b, 0.05)
                                opacity: Math.max(0, Math.min(1, root.gridIntro * 2.5 - index * 0.25))
                                transform: Translate { y: root.s(10) * (1 - Math.max(0, Math.min(1, root.gridIntro * 2.5 - index * 0.25))) }
                                Row {
                                    anchors.left: parent.left; anchors.leftMargin: root.s(14)
                                    anchors.verticalCenter: parent.verticalCenter
                                    spacing: root.s(12)
                                    Text {
                                        text: modelData.icon
                                        color: index === 0 && root.streakNow > 0 ? root.green : root.subtext0
                                        font.family: root.monoFont; font.pixelSize: root.s(18)
                                        anchors.verticalCenter: parent.verticalCenter
                                    }
                                    Column {
                                        anchors.verticalCenter: parent.verticalCenter
                                        Text { text: modelData.value; color: root.text; font.family: root.uiFont; font.weight: Font.DemiBold; font.pixelSize: root.s(16) }
                                        Text { text: modelData.label; color: root.overlay0; font.family: root.uiFont; font.pixelSize: root.s(12) }
                                    }
                                }
                            }
                        }
                    }
                }
            }

            // ---------------- LEETCODE CARD ----------------
            Rectangle {
                Layout.fillWidth: true
                Layout.fillHeight: true
                radius: root.s(26)
                color: Qt.rgba(root.base.r, root.base.g, root.base.b, 0.55)
                border.width: 1
                border.color: Qt.rgba(root.text.r, root.text.g, root.text.b, 0.07)
                opacity: root.introTodo
                transform: Translate { y: root.s(24) * (1 - root.introTodo) }

                Column {
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.margins: root.s(24)
                    spacing: root.s(16)

                    // title + solved counts
                    Item {
                        width: parent.width
                        height: root.s(24)
                        Row {
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: root.s(10)
                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                text: "\uf121"
                                color: root.lcOrange
                                font.family: root.monoFont; font.pixelSize: root.s(18)
                            }
                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                textFormat: Text.StyledText
                                color: root.subtext0
                                font.family: root.uiFont; font.pixelSize: root.s(15)
                                text: root.lcStats.error ? root.lcStats.error
                                    : !root.lcStats.solved ? "Loading LeetCode…"
                                    : "<b><font color='" + root.text + "'>" + root.lcStats.solved.all + "</font></b> solved · "
                                      + root.lcStats.total + " submissions in the last year · " + root.lcStats.login
                            }
                        }
                        Row {
                            anchors.right: parent.right
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: root.s(14)
                            visible: !!root.lcStats.solved
                            Repeater {
                                model: [["Easy", "easy"], ["Med", "medium"], ["Hard", "hard"]]
                                Row {
                                    spacing: root.s(5)
                                    Text {
                                        text: modelData[0]
                                        color: root.lcColor(modelData[0] === "Med" ? "Medium" : modelData[0])
                                        font.family: root.uiFont; font.weight: Font.DemiBold; font.pixelSize: root.s(13)
                                    }
                                    Text {
                                        text: root.lcStats.solved ? root.lcStats.solved[modelData[1]] + "/" + root.lcStats.totals[modelData[1]] : ""
                                        color: root.subtext0
                                        font.family: root.uiFont; font.pixelSize: root.s(13)
                                    }
                                }
                            }
                        }
                    }

                    // submission heatmap (same geometry as the GitHub one)
                    Item {
                        id: lcGrid
                        width: parent.width
                        readonly property real labelW: root.s(34)
                        readonly property real pitch: Math.floor((width - labelW) / 53)
                        readonly property real gap: Math.max(2, Math.round(pitch * 0.2))
                        readonly property real cell: pitch - gap
                        height: root.s(18) + pitch * 7

                        Repeater {
                            model: root.lcMonths
                            Text {
                                x: lcGrid.labelW + modelData.col * lcGrid.pitch
                                text: modelData.name
                                color: root.subtext0
                                font.family: root.uiFont; font.pixelSize: root.s(12)
                                opacity: Math.min(1, root.lcIntro * 3)
                            }
                        }
                        Repeater {
                            model: [[1, "Mon"], [3, "Wed"], [5, "Fri"]]
                            Text {
                                y: root.s(18) + modelData[0] * lcGrid.pitch + (lcGrid.cell - height) / 2
                                text: modelData[1]
                                color: root.subtext0
                                font.family: root.uiFont; font.pixelSize: root.s(11)
                                opacity: Math.min(1, root.lcIntro * 3)
                            }
                        }
                        Item {
                            x: lcGrid.labelW
                            y: root.s(18)
                            width: lcGrid.pitch * 53
                            height: lcGrid.pitch * 7
                            Repeater {
                                model: root.lcDays
                                Rectangle {
                                    readonly property real p: root.lcProgress(modelData.col, modelData.row)
                                    readonly property bool isHover: root.lcHover !== null && root.lcHover.d === modelData.d
                                    x: modelData.col * lcGrid.pitch
                                    y: modelData.row * lcGrid.pitch
                                    width: lcGrid.cell; height: lcGrid.cell
                                    radius: Math.max(2, lcGrid.cell * 0.28)
                                    color: root.lcHeat(modelData.l)
                                    scale: p * (isHover ? 1.35 : 1.0)
                                    opacity: Math.min(1, p * 1.5)
                                    border.width: index === root.lcDays.length - 1 ? 1 : 0
                                    border.color: root.text
                                    z: isHover ? 2 : 1
                                    Behavior on scale { enabled: root.lcIntro >= 1; NumberAnimation { duration: 140; easing.type: Easing.OutBack } }
                                }
                            }
                            MouseArea {
                                anchors.fill: parent
                                hoverEnabled: true
                                onPositionChanged: (m) => {
                                    let d = root.lcCellIndex[Math.floor(m.x / lcGrid.pitch) + "," + Math.floor(m.y / lcGrid.pitch)];
                                    root.lcHover = d ? d : null;
                                }
                                onExited: root.lcHover = null
                            }
                        }
                    }

                    // daily problem (title / chips) + side-by-side buttons
                    RowLayout {
                        width: parent.width
                        spacing: root.s(16)

                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: root.s(6)
                            Text {
                                Layout.fillWidth: true
                                elide: Text.ElideRight
                                text: root.lcDaily.title ? "Daily · " + root.lcDaily.id + ". " + root.lcDaily.title : "Couldn't load today's problem"
                                color: root.text
                                font.family: root.uiFont; font.weight: Font.Bold; font.pixelSize: root.s(17)
                            }
                            Flow {
                                Layout.fillWidth: true
                                spacing: root.s(6)
                                visible: !!root.lcDaily.title
                                Rectangle {   // difficulty
                                    width: diffText.implicitWidth + root.s(16); height: root.s(22); radius: height / 2
                                    color: Qt.alpha(root.lcColor(root.lcDaily.difficulty), 0.18)
                                    Text {
                                        id: diffText
                                        anchors.centerIn: parent
                                        text: root.lcDaily.difficulty || ""
                                        color: root.lcColor(root.lcDaily.difficulty)
                                        font.family: root.uiFont; font.weight: Font.DemiBold; font.pixelSize: root.s(12)
                                    }
                                }
                                Rectangle {
                                    width: acText.implicitWidth + root.s(16); height: root.s(22); radius: height / 2
                                    color: Qt.rgba(root.text.r, root.text.g, root.text.b, 0.07)
                                    Text {
                                        id: acText
                                        anchors.centerIn: parent
                                        text: (root.lcDaily.acRate !== undefined ? root.lcDaily.acRate : "?") + "% accepted"
                                        color: root.subtext0
                                        font.family: root.uiFont; font.pixelSize: root.s(12)
                                    }
                                }
                                Repeater {
                                    model: root.lcDaily.tags || []
                                    Rectangle {
                                        width: tagText.implicitWidth + root.s(16); height: root.s(22); radius: height / 2
                                        color: "transparent"
                                        border.width: 1
                                        border.color: Qt.rgba(root.text.r, root.text.g, root.text.b, 0.14)
                                        Text {
                                            id: tagText
                                            anchors.centerIn: parent
                                            text: modelData
                                            color: root.subtext0
                                            font.family: root.uiFont; font.pixelSize: root.s(12)
                                        }
                                    }
                                }
                            }
                        }

                        RowLayout {
                            Layout.alignment: Qt.AlignVCenter
                            spacing: root.s(8)

                            // solution language: opens the dropdown (drawn at the end of the file, above the cards)
                            Rectangle {
                                id: lcLangBtn
                                Layout.preferredWidth: lcLangBtnRow.implicitWidth + root.s(34)
                                Layout.preferredHeight: root.s(38)
                                radius: height / 2
                                color: Qt.rgba(root.text.r, root.text.g, root.text.b, lcLangBtnMa.containsMouse || root.lcLangOpen ? 0.12 : 0.06)
                                border.width: 1
                                border.color: Qt.rgba(root.text.r, root.text.g, root.text.b, 0.12)
                                scale: lcLangBtnMa.pressed ? 0.96 : lcLangBtnMa.containsMouse ? 1.03 : 1.0
                                Behavior on color { ColorAnimation { duration: 150 } }
                                Behavior on scale { NumberAnimation { duration: 200; easing.type: Easing.OutBack } }
                                Row {
                                    id: lcLangBtnRow
                                    anchors.centerIn: parent
                                    spacing: root.s(8)
                                    Text {
                                        anchors.verticalCenter: parent.verticalCenter
                                        text: String.fromCodePoint(root.lcLangCur.i)
                                        color: root.subtext0
                                        font.family: root.monoFont; font.pixelSize: root.s(15)
                                    }
                                    Text {
                                        anchors.verticalCenter: parent.verticalCenter
                                        text: root.lcLangCur.l
                                        color: root.text
                                        font.family: root.uiFont; font.weight: Font.DemiBold; font.pixelSize: root.s(14)
                                    }
                                    Text {
                                        anchors.verticalCenter: parent.verticalCenter
                                        text: "\uf078"
                                        color: root.subtext0
                                        font.family: root.monoFont; font.pixelSize: root.s(10)
                                        rotation: root.lcLangOpen ? 180 : 0
                                        Behavior on rotation { NumberAnimation { duration: 300; easing.type: Easing.OutBack } }
                                    }
                                }
                                MouseArea {
                                    id: lcLangBtnMa
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: {
                                        let p = lcLangBtn.mapToItem(root, 0, lcLangBtn.height);
                                        lcLangMenu.anchorX = p.x;
                                        lcLangMenu.anchorY = p.y;
                                        root.lcLangOpen = !root.lcLangOpen;
                                    }
                                }
                            }

                            Repeater {
                                model: [
                                    { label: "Browse", icon: "\uf002", arg: "", primary: false },
                                    { label: "Solve daily", icon: "\uf061", arg: "daily", primary: true }
                                ]
                                Rectangle {
                                    Layout.preferredWidth: btnRow.implicitWidth + root.s(36)
                                    Layout.preferredHeight: root.s(38)
                                    radius: height / 2
                                    color: modelData.primary
                                        ? Qt.rgba(root.text.r, root.text.g, root.text.b, btnMa.containsMouse ? 0.95 : 0.85)
                                        : Qt.rgba(root.text.r, root.text.g, root.text.b, btnMa.containsMouse ? 0.12 : 0.06)
                                    border.width: modelData.primary ? 0 : 1
                                    border.color: Qt.rgba(root.text.r, root.text.g, root.text.b, 0.12)
                                    scale: btnMa.pressed ? 0.96 : btnMa.containsMouse ? 1.03 : 1.0
                                    Behavior on color { ColorAnimation { duration: 150 } }
                                    Behavior on scale { NumberAnimation { duration: 200; easing.type: Easing.OutBack } }
                                    Row {
                                        id: btnRow
                                        anchors.centerIn: parent
                                        spacing: root.s(9)
                                        Text {
                                            anchors.verticalCenter: parent.verticalCenter
                                            text: modelData.label
                                            color: modelData.primary ? root.base : root.text
                                            font.family: root.uiFont; font.weight: Font.DemiBold; font.pixelSize: root.s(14)
                                        }
                                        Text {
                                            anchors.verticalCenter: parent.verticalCenter
                                            text: modelData.icon
                                            color: modelData.primary ? root.base : root.subtext0
                                            font.family: root.monoFont; font.pixelSize: root.s(13)
                                        }
                                    }
                                    MouseArea {
                                        id: btnMa
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: Quickshell.execDetached(["bash", root.dashDir + "/leetcode_open.sh", modelData.arg])
                                    }
                                }
                            }
                        }
                    }
                }
            }

            // ---------------- GYM CARD ----------------
            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: gymCol.implicitHeight + root.s(48)
                radius: root.s(26)
                color: Qt.rgba(root.base.r, root.base.g, root.base.b, 0.55)
                border.width: 1
                border.color: Qt.rgba(root.text.r, root.text.g, root.text.b, 0.07)
                opacity: root.introTodo
                transform: Translate { y: root.s(28) * (1 - root.introTodo) }

                Column {
                    id: gymCol
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.margins: root.s(24)
                    spacing: root.s(16)

                    // title (shows the hovered day) + note field + log button
                    RowLayout {
                        width: parent.width
                        height: root.s(34)
                        spacing: root.s(10)
                        Text {
                            text: ""
                            color: root.gymColor
                            font.family: root.monoFont; font.pixelSize: root.s(18)
                        }
                        Text {
                            Layout.fillWidth: true
                            elide: Text.ElideRight
                            textFormat: Text.StyledText
                            color: root.subtext0
                            font.family: root.uiFont; font.pixelSize: root.s(15)
                            text: root.gymHover !== null
                                ? "<b><font color='" + root.text + "'>" + root.prettyDate(root.gymHover.d) + "</font></b> · "
                                  + (root.gymHover.c > 0 ? (root.gymHover.n || "trained") : "rest day")
                                : "<b><font color='" + root.text + "'>" + root.gymTotal + "</font></b> sessions in the last year"
                        }
                        Rectangle {
                            Layout.preferredWidth: root.s(230)
                            Layout.preferredHeight: root.s(34)
                            radius: height / 2
                            color: Qt.rgba(root.text.r, root.text.g, root.text.b, gymInput.activeFocus ? 0.08 : 0.05)
                            border.width: 1
                            border.color: Qt.rgba(root.text.r, root.text.g, root.text.b, gymInput.activeFocus ? 0.18 : 0.0)
                            Behavior on color { ColorAnimation { duration: 150 } }
                            TextField {
                                id: gymInput
                                anchors.fill: parent
                                anchors.leftMargin: root.s(14); anchors.rightMargin: root.s(14)
                                background: Item {}
                                color: root.text
                                font.family: root.uiFont; font.pixelSize: root.s(13)
                                placeholderText: root.gymToday ? "Change today's note…" : "What did you train?"
                                placeholderTextColor: root.overlay0
                                verticalAlignment: TextInput.AlignVCenter
                                Keys.onReturnPressed: { root.gymLogToday(text); text = ""; }
                                Keys.onEnterPressed: { root.gymLogToday(text); text = ""; }
                            }
                        }
                        Rectangle {
                            Layout.preferredWidth: gymBtnRow.implicitWidth + root.s(32)
                            Layout.preferredHeight: root.s(34)
                            radius: height / 2
                            color: root.gymToday
                                ? Qt.alpha(root.gymColor, gymBtnMa.containsMouse ? 0.32 : 0.22)
                                : Qt.rgba(root.text.r, root.text.g, root.text.b, gymBtnMa.containsMouse ? 0.95 : 0.85)
                            scale: gymBtnMa.pressed ? 0.96 : gymBtnMa.containsMouse ? 1.03 : 1.0
                            Behavior on color { ColorAnimation { duration: 150 } }
                            Behavior on scale { NumberAnimation { duration: 200; easing.type: Easing.OutBack } }
                            Row {
                                id: gymBtnRow
                                anchors.centerIn: parent
                                spacing: root.s(8)
                                Text {
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: root.gymToday ? (gymBtnMa.containsMouse && gymInput.text === "" ? "Undo" : "Logged") : "Log today"
                                    color: root.gymToday ? root.gymColor : root.base
                                    font.family: root.uiFont; font.weight: Font.DemiBold; font.pixelSize: root.s(14)
                                }
                                Text {
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: root.gymToday ? "" : ""
                                    color: root.gymToday ? root.gymColor : root.base
                                    font.family: root.monoFont; font.pixelSize: root.s(13)
                                }
                            }
                            MouseArea {
                                id: gymBtnMa
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: { root.gymLogToday(gymInput.text); gymInput.text = ""; }
                            }
                        }
                    }

                    // heatmap (same geometry as the others); click a day to toggle it
                    Item {
                        id: gymGrid
                        width: parent.width
                        readonly property real labelW: root.s(34)
                        readonly property real pitch: Math.floor((width - labelW) / 53)
                        readonly property real gap: Math.max(2, Math.round(pitch * 0.2))
                        readonly property real cell: pitch - gap
                        height: root.s(18) + pitch * 7

                        Repeater {
                            model: root.gymMonths
                            Text {
                                x: gymGrid.labelW + modelData.col * gymGrid.pitch
                                text: modelData.name
                                color: root.subtext0
                                font.family: root.uiFont; font.pixelSize: root.s(12)
                                opacity: Math.min(1, root.gymIntro * 3)
                            }
                        }
                        Repeater {
                            model: [[1, "Mon"], [3, "Wed"], [5, "Fri"]]
                            Text {
                                y: root.s(18) + modelData[0] * gymGrid.pitch + (gymGrid.cell - height) / 2
                                text: modelData[1]
                                color: root.subtext0
                                font.family: root.uiFont; font.pixelSize: root.s(11)
                                opacity: Math.min(1, root.gymIntro * 3)
                            }
                        }
                        Item {
                            x: gymGrid.labelW
                            y: root.s(18)
                            width: gymGrid.pitch * 53
                            height: gymGrid.pitch * 7
                            Repeater {
                                model: root.gymDays
                                Rectangle {
                                    readonly property real p: root.gymProgress(modelData.col, modelData.row)
                                    readonly property bool isHover: root.gymHover !== null && root.gymHover.d === modelData.d
                                    x: modelData.col * gymGrid.pitch
                                    y: modelData.row * gymGrid.pitch
                                    width: gymGrid.cell; height: gymGrid.cell
                                    radius: Math.max(2, gymGrid.cell * 0.28)
                                    color: root.gymHeat(modelData.l)
                                    Behavior on color { ColorAnimation { duration: 180 } }
                                    scale: p * (isHover ? 1.35 : 1.0)
                                    opacity: Math.min(1, p * 1.5)
                                    border.width: index === root.gymDays.length - 1 ? 1 : 0
                                    border.color: root.text
                                    z: isHover ? 2 : 1
                                    Behavior on scale { enabled: root.gymIntro >= 1; NumberAnimation { duration: 140; easing.type: Easing.OutBack } }
                                }
                            }
                            MouseArea {
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: root.gymHover !== null ? Qt.PointingHandCursor : Qt.ArrowCursor
                                function cellAt(m) { return root.gymCellIndex[Math.floor(m.x / gymGrid.pitch) + "," + Math.floor(m.y / gymGrid.pitch)] || null; }
                                onPositionChanged: (m) => root.gymHover = cellAt(m)
                                onExited: root.gymHover = null
                                onClicked: (m) => {
                                    let d = cellAt(m);
                                    if (!d) return;
                                    root.gymToggleDay(d.d);
                                    root.gymHover = root.gymCellIndex[d.col + "," + d.row];
                                }
                            }
                        }
                    }

                    // stats
                    Row {
                        width: parent.width
                        spacing: root.s(10)
                        Repeater {
                            model: [
                                { icon: "", label: "This week (goal " + root.gymGoal + ")", value: root.gymThisWeek + " / " + root.gymGoal },
                                { icon: "", label: "Week streak", value: root.gymWeekStreak + (root.gymWeekStreak === 1 ? " week" : " weeks") },
                                { icon: "", label: "Longest week streak", value: root.gymBestWeekStreak + (root.gymBestWeekStreak === 1 ? " week" : " weeks") },
                                { icon: "", label: "Last session", value: root.gymLast ? root.prettyDate(root.gymLast.d) : "—" }
                            ]
                            Rectangle {
                                width: (parent.width - root.s(30)) / 4
                                height: root.s(54)
                                radius: root.s(16)
                                color: Qt.rgba(root.text.r, root.text.g, root.text.b, 0.05)
                                opacity: Math.max(0, Math.min(1, root.gymIntro * 2.5 - index * 0.25))
                                Row {
                                    anchors.left: parent.left; anchors.leftMargin: root.s(14)
                                    anchors.verticalCenter: parent.verticalCenter
                                    spacing: root.s(12)
                                    Text {
                                        text: modelData.icon
                                        color: (index === 0 && root.gymThisWeek >= root.gymGoal) || (index === 1 && root.gymWeekStreak > 0) ? root.gymColor : root.subtext0
                                        font.family: root.monoFont; font.pixelSize: root.s(18)
                                        anchors.verticalCenter: parent.verticalCenter
                                    }
                                    Column {
                                        anchors.verticalCenter: parent.verticalCenter
                                        Text { text: modelData.value; color: root.text; font.family: root.uiFont; font.weight: Font.DemiBold; font.pixelSize: root.s(16) }
                                        Text { text: modelData.label; color: root.overlay0; font.family: root.uiFont; font.pixelSize: root.s(12) }
                                    }
                                }
                            }
                        }
                    }
                }
            }
            }   // left column

            // ---------------- TODO CARD ----------------
            Rectangle {
                Layout.fillWidth: true
                Layout.minimumWidth: root.s(380)
                Layout.fillHeight: true
                radius: root.s(26)
                color: Qt.rgba(root.base.r, root.base.g, root.base.b, 0.55)
                border.width: 1
                border.color: Qt.rgba(root.text.r, root.text.g, root.text.b, 0.07)
                opacity: root.introTodo
                transform: Translate { x: root.s(30) * (1 - root.introTodo) }

                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: root.s(22)
                    spacing: root.s(12)

                    // title
                    RowLayout {
                        Layout.fillWidth: true
                        Text {
                            text: ""
                            color: root.text
                            font.family: root.monoFont; font.pixelSize: root.s(18)
                        }
                        Text {
                            Layout.fillWidth: true
                            leftPadding: root.s(4)
                            text: { root.modelRev; return "Todo  <font color='" + root.overlay0 + "'>" + (todoModel.count === 0 ? "" : root.openCount === 0 ? "all done ✓" : root.openCount + " left") + "</font>"; }
                            textFormat: Text.StyledText
                            color: root.text
                            font.family: root.uiFont; font.weight: Font.DemiBold; font.pixelSize: root.s(17)
                        }
                        Text {
                            visible: { root.modelRev; return todoModel.count - root.openCount > 0; }
                            text: "Clear done"
                            color: clearMa.containsMouse ? root.text : root.overlay0
                            font.family: root.uiFont; font.pixelSize: root.s(13)
                            Behavior on color { ColorAnimation { duration: 150 } }
                            MouseArea {
                                id: clearMa
                                anchors.fill: parent; anchors.margins: -root.s(6)
                                hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                onClicked: root.clearDone()
                            }
                        }
                    }

                    // input
                    Rectangle {
                        Layout.fillWidth: true
                        Layout.preferredHeight: root.s(46)
                        radius: root.s(16)
                        color: Qt.rgba(root.text.r, root.text.g, root.text.b, input.activeFocus ? 0.08 : 0.05)
                        border.width: 1
                        border.color: Qt.rgba(root.text.r, root.text.g, root.text.b, input.activeFocus ? 0.18 : 0.0)
                        Behavior on color { ColorAnimation { duration: 150 } }
                        Behavior on border.color { ColorAnimation { duration: 150 } }

                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: root.s(16)
                            anchors.rightMargin: root.s(12)
                            spacing: root.s(10)
                            Text {
                                text: ""
                                color: input.activeFocus ? root.text : root.overlay0
                                font.family: root.monoFont; font.pixelSize: root.s(14)
                                Behavior on color { ColorAnimation { duration: 150 } }
                            }
                            TextField {
                                id: input
                                Layout.fillWidth: true
                                Layout.fillHeight: true
                                background: Item {}
                                color: root.text
                                font.family: root.uiFont
                                font.pixelSize: root.s(15)
                                placeholderText: "Add a task and press Enter…"
                                placeholderTextColor: root.overlay0
                                verticalAlignment: TextInput.AlignVCenter
                                focus: true
                                Keys.onReturnPressed: { root.addTodo(text); text = ""; }
                                Keys.onEnterPressed: { root.addTodo(text); text = ""; }
                            }
                        }
                    }

                    // list (drag the grip to reorder; thin scrollbar + edge fades when it overflows)
                    Item {
                        Layout.fillWidth: true
                        Layout.fillHeight: true

                        ListView {
                            id: todoList
                            anchors.fill: parent
                            clip: true
                            spacing: root.s(4)
                            model: todoModel
                            boundsBehavior: Flickable.StopAtBounds
                            interactive: root.dragIndex < 0

                            readonly property bool scrollable: contentHeight > height + 1
                            readonly property real pitch: root.s(44) + spacing

                            add: Transition {
                                enabled: !root.todoBulk
                                ParallelAnimation {
                                    NumberAnimation { property: "opacity"; from: 0; to: 1; duration: 320; easing.type: Easing.OutCubic }
                                    NumberAnimation { property: "x"; from: -root.s(24); to: 0; duration: 420; easing.type: Easing.OutBack }
                                }
                            }
                            remove: Transition {
                                enabled: !root.todoBulk
                                ParallelAnimation {
                                    NumberAnimation { property: "opacity"; to: 0; duration: 200; easing.type: Easing.InCubic }
                                    NumberAnimation { property: "x"; to: root.s(40); duration: 220; easing.type: Easing.InCubic }
                                }
                            }
                            move: Transition {
                                enabled: !root.todoBulk
                                NumberAnimation { properties: "y"; duration: 180; easing.type: Easing.OutCubic }
                            }
                            moveDisplaced: Transition {
                                enabled: !root.todoBulk
                                NumberAnimation { properties: "y"; duration: 220; easing.type: Easing.OutCubic }
                            }
                            displaced: Transition {
                                enabled: !root.todoBulk
                                NumberAnimation { properties: "y"; duration: 260; easing.type: Easing.OutCubic }
                            }

                            ScrollBar.vertical: ScrollBar {
                                id: vbar
                                policy: todoList.scrollable ? ScrollBar.AlwaysOn : ScrollBar.AlwaysOff
                                width: root.s(6)
                                padding: 0
                                background: Rectangle {
                                    radius: width / 2
                                    color: Qt.rgba(root.text.r, root.text.g, root.text.b, 0.05)
                                }
                                contentItem: Rectangle {
                                    implicitWidth: root.s(6)
                                    radius: width / 2
                                    color: Qt.rgba(root.text.r, root.text.g, root.text.b,
                                                   vbar.pressed ? 0.55 : (vbar.hovered || todoList.moving) ? 0.4 : 0.22)
                                    Behavior on color { ColorAnimation { duration: 150 } }
                                }
                            }

                            // auto-scroll while dragging near the top/bottom edge
                            Timer {
                                interval: 16; repeat: true
                                running: root.dragIndex >= 0 && root.dragEdge !== 0
                                onTriggered: {
                                    let maxY = Math.max(0, todoList.contentHeight - todoList.height);
                                    todoList.contentY = Math.max(0, Math.min(maxY, todoList.contentY + root.dragEdge * root.s(6)));
                                    root.dragReorder();
                                }
                            }

                            Text {
                                anchors.centerIn: parent
                                visible: root.todosLoaded && todoModel.count === 0
                                text: "Nothing on the list. Enjoy it."
                                color: root.overlay0
                                font.family: root.uiFont; font.pixelSize: root.s(14)
                            }

                            delegate: Rectangle {
                                id: row
                                required property int index
                                required property string text
                                required property bool done
                                readonly property bool dragging: root.dragIndex === index
                                width: todoList.width - (todoList.scrollable ? root.s(14) : 0)
                                height: root.s(44)
                                radius: root.s(14)
                                z: dragging ? 10 : 1
                                scale: dragging ? 1.025 : 1
                                color: dragging ? Qt.rgba(root.text.r, root.text.g, root.text.b, 0.12)
                                     : rowMa.containsMouse ? Qt.rgba(root.text.r, root.text.g, root.text.b, 0.06) : "transparent"
                                border.width: dragging ? 1 : 0
                                border.color: Qt.rgba(root.text.r, root.text.g, root.text.b, 0.18)
                                Behavior on color { ColorAnimation { duration: 120 } }
                                Behavior on scale { NumberAnimation { duration: 160; easing.type: Easing.OutBack } }

                                MouseArea {
                                    id: rowMa
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: root.toggleTodo(row.index)
                                }

                                RowLayout {
                                    anchors.fill: parent
                                    anchors.leftMargin: root.s(6)
                                    anchors.rightMargin: root.s(12)
                                    spacing: root.s(8)

                                    // drag grip (2x3 dots)
                                    Item {
                                        Layout.preferredWidth: root.s(16)
                                        Layout.fillHeight: true
                                        opacity: row.dragging ? 1 : (rowMa.containsMouse || gripMa.containsMouse) ? 0.9 : 0.25
                                        Behavior on opacity { NumberAnimation { duration: 120 } }
                                        Grid {
                                            anchors.centerIn: parent
                                            columns: 2; rowSpacing: root.s(3); columnSpacing: root.s(3)
                                            Repeater {
                                                model: 6
                                                Rectangle {
                                                    width: root.s(3); height: width; radius: width / 2
                                                    color: row.dragging || gripMa.containsMouse ? root.text : root.subtext0
                                                }
                                            }
                                        }
                                        MouseArea {
                                            id: gripMa
                                            anchors.fill: parent
                                            anchors.margins: -root.s(4)
                                            hoverEnabled: true
                                            preventStealing: true
                                            cursorShape: pressed ? Qt.ClosedHandCursor : Qt.OpenHandCursor
                                            onPressed: (m) => { root.dragIndex = row.index; root.dragTrack(gripMa, m); }
                                            onPositionChanged: (m) => { if (pressed) root.dragTrack(gripMa, m); }
                                            onReleased: root.dragEnd()
                                            onCanceled: root.dragEnd()
                                        }
                                    }

                                    // check circle
                                    Rectangle {
                                        Layout.preferredWidth: root.s(22)
                                        Layout.preferredHeight: root.s(22)
                                        radius: width / 2
                                        color: row.done ? root.green : "transparent"
                                        border.width: row.done ? 0 : 2
                                        border.color: rowMa.containsMouse ? root.subtext0 : root.overlay0
                                        Behavior on color { ColorAnimation { duration: 200 } }
                                        Text {
                                            anchors.centerIn: parent
                                            text: ""
                                            color: "#0d0d0d"
                                            font.family: root.monoFont; font.pixelSize: root.s(12)
                                            scale: row.done ? 1 : 0
                                            Behavior on scale { NumberAnimation { duration: 260; easing.type: Easing.OutBack; easing.overshoot: 2.5 } }
                                        }
                                    }

                                    Text {
                                        Layout.fillWidth: true
                                        leftPadding: root.s(4)
                                        text: row.text
                                        elide: Text.ElideRight
                                        color: row.done ? root.overlay0 : root.text
                                        font.family: root.uiFont; font.pixelSize: root.s(15)
                                        font.strikeout: row.done
                                        Behavior on color { ColorAnimation { duration: 200 } }
                                    }

                                    // delete
                                    Text {
                                        text: ""
                                        color: delMa.containsMouse ? root.red : root.overlay0
                                        opacity: (rowMa.containsMouse || delMa.containsMouse) && !row.dragging ? 1 : 0
                                        font.family: root.monoFont; font.pixelSize: root.s(14)
                                        Behavior on opacity { NumberAnimation { duration: 120 } }
                                        Behavior on color { ColorAnimation { duration: 120 } }
                                        MouseArea {
                                            id: delMa
                                            anchors.fill: parent; anchors.margins: -root.s(8)
                                            hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                            onClicked: root.removeTodo(row.index)
                                        }
                                    }
                                }
                            }
                        }

                        // edge fades: hint that there's more above / below
                        Rectangle {
                            anchors.top: parent.top
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.rightMargin: root.s(14)
                            height: root.s(28)
                            opacity: todoList.scrollable && !todoList.atYBeginning ? 1 : 0
                            Behavior on opacity { NumberAnimation { duration: 180 } }
                            gradient: Gradient {
                                GradientStop { position: 0; color: Qt.rgba(root.base.r, root.base.g, root.base.b, 0.85) }
                                GradientStop { position: 1; color: Qt.rgba(root.base.r, root.base.g, root.base.b, 0) }
                            }
                        }
                        Rectangle {
                            anchors.bottom: parent.bottom
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.rightMargin: root.s(14)
                            id: bottomFade
                            height: root.s(36)
                            opacity: todoList.scrollable && !todoList.atYEnd ? 1 : 0
                            Behavior on opacity { NumberAnimation { duration: 180 } }
                            gradient: Gradient {
                                GradientStop { position: 0; color: Qt.rgba(root.base.r, root.base.g, root.base.b, 0) }
                                GradientStop { position: 1; color: Qt.rgba(root.base.r, root.base.g, root.base.b, 0.85) }
                            }
                            Text {
                                anchors.horizontalCenter: parent.horizontalCenter
                                anchors.bottom: parent.bottom
                                anchors.bottomMargin: root.s(2)
                                text: ""
                                color: root.subtext0
                                font.family: root.monoFont; font.pixelSize: root.s(14)
                                SequentialAnimation on anchors.bottomMargin {
                                    loops: Animation.Infinite
                                    running: bottomFade.opacity > 0
                                    NumberAnimation { to: root.s(6); duration: 600; easing.type: Easing.InOutSine }
                                    NumberAnimation { to: root.s(2); duration: 600; easing.type: Easing.InOutSine }
                                }
                            }
                        }
                    }
                }
            }
            }
        }
    }

    // ---------------- LeetCode language dropdown (above everything) ----------------
    MouseArea {   // click outside closes it
        anchors.fill: parent
        z: 99
        visible: root.lcLangOpen
        onClicked: root.lcLangOpen = false
    }
    Rectangle {
        id: lcLangMenu
        property real anchorX: 0
        property real anchorY: 0
        z: 100
        x: anchorX
        y: anchorY + root.s(8)
        width: root.s(200)
        height: lcLangCol.implicitHeight + root.s(12)
        radius: root.s(20)
        color: Qt.rgba(root.base.r, root.base.g, root.base.b, 0.96)
        border.width: 1
        border.color: Qt.rgba(root.text.r, root.text.g, root.text.b, 0.12)
        transformOrigin: Item.Top
        opacity: root.lcLangOpen ? 1 : 0
        scale: root.lcLangOpen ? 1 : 0.92
        visible: opacity > 0.01
        Behavior on opacity { NumberAnimation { duration: 180 } }
        Behavior on scale { NumberAnimation { duration: 260; easing.type: Easing.OutBack } }

        Column {
            id: lcLangCol
            x: root.s(6); y: root.s(6)
            width: parent.width - root.s(12)
            Repeater {
                model: root.lcLangs
                Rectangle {
                    width: lcLangCol.width
                    height: root.s(38)
                    radius: height / 2
                    readonly property bool sel: root.lcLang === modelData.v
                    color: sel ? Qt.rgba(root.text.r, root.text.g, root.text.b, 0.85)
                               : (itemMa.containsMouse ? Qt.rgba(root.text.r, root.text.g, root.text.b, 0.08) : "transparent")
                    Behavior on color { ColorAnimation { duration: 120 } }
                    Row {
                        anchors.left: parent.left; anchors.leftMargin: root.s(14)
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: root.s(10)
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            width: root.s(18)
                            text: String.fromCodePoint(modelData.i)
                            color: parent.parent.sel ? root.base : root.subtext0
                            font.family: root.monoFont; font.pixelSize: root.s(15)
                        }
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: modelData.l
                            color: parent.parent.sel ? root.base : root.text
                            font.family: root.uiFont; font.weight: Font.DemiBold; font.pixelSize: root.s(14)
                        }
                    }
                    MouseArea {
                        id: itemMa
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.setLcLang(modelData.v)
                    }
                }
            }
        }
    }
}
