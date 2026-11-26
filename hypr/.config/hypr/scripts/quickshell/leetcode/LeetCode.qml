//@ pragma UseQApplication
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import Quickshell
import Quickshell.Io

// LeetCode window: problem description (with images), editable test cases,
// Run / Submit and a proper results view. Code lives in nvim next to it
// (lc_open.sh tiles kitty+nvim beside this window). Backend: lc.py.
//
//   quickshell -p ~/.config/hypr/scripts/quickshell/leetcode/LeetCode.qml
//   IPC: quickshell ipc -p <this file> call lc open <slug> | run | submit
ShellRoot {
    id: root

    readonly property string dir: Quickshell.env("HOME") + "/.config/hypr/scripts/quickshell/leetcode"
    readonly property string nvimSock: (Quickshell.env("XDG_RUNTIME_DIR") || "/tmp") + "/lc-nvim.sock"

    // ---------------- theme ----------------
    // Palette from the shell's matugen output (../qs_colors.json), re-read on start.
    property color base: "#0d0e13"
    property color mantle: "#1b1b21"
    property color text: "#e4e1e9"
    property color subtext0: "#c7c5d0"
    property color overlay0: "#90909a"
    property color surface0: "#1f1f25"
    property color surface1: "#29292f"
    // un-greyed matugen colours for the problem text (examples, code, headings)
    property color mAccent: "#bcc2ff"
    property color mText: "#e4e1e9"
    property color mSub: "#c7c5d0"
    property color mSurface: "#29292f"
    property color mAccent2: "#e6bad6"
    Process {
        running: true
        command: ["cat", Quickshell.env("HOME") + "/.config/hypr/scripts/quickshell/qs_colors.json"]
        stdout: StdioCollector {
            onStreamFinished: {
                let c; try { c = JSON.parse(this.text); } catch (e) { return; }
                // whole window uses the real matugen palette. Note: matugen's overlay0
                // is a bright colour, so dim text comes from subtext1 instead.
                for (let k of ["base", "mantle", "text", "subtext0", "surface0", "surface1"])
                    if (typeof c[k] === "string") root[k] = c[k];
                if (c.subtext1) root.overlay0 = c.subtext1;
                if (c.peach) root.mAccent2 = c.peach;
                if (c.blue) root.mAccent = c.blue;
                if (c.text) root.mText = c.text;
                if (c.subtext0) root.mSub = c.subtext0;
                if (c.surface1) root.mSurface = c.surface1;
            }
        }
    }
    readonly property color green: "#40C160"
    readonly property color red: "#EB564E"
    readonly property color amber: "#FFB340"
    readonly property color orange: "#FFA116"
    readonly property string ui: "SF Pro Display"
    readonly property string mono: "Maple Mono Normal NF"
    function tint(a) { return Qt.rgba(root.text.r, root.text.g, root.text.b, a); }
    function acc(a) { return Qt.alpha(root.mAccent, a); }
    function diffColor(d) { return d === "Easy" ? root.green : d === "Medium" ? root.amber : d === "Hard" ? root.red : root.subtext0; }

    // ---------------- state ----------------
    property var problem: null
    property var tests: []          // one string per case, a line per parameter
    property var result: null
    property string busy: ""        // "", "fetch", "run", "submit"
    property string error: ""
    property int tab: 0             // 0 description, 1 testcases, 2 result
    property int selCase: 0
    // problem browser
    property bool browsing: false
    property var browseRows: []
    property int browseTotal: 0
    property bool browseLoading: false
    property string fDifficulty: ""      // "", EASY, MEDIUM, HARD
    property string fStatus: ""          // "", NOT_STARTED, AC, TRIED
    property var fTags: []               // topic slugs (all must match)
    property string fSort: "FRONTEND_ID|ASCENDING"
    readonly property var topics: [
        ["array", "Array"], ["string", "String"], ["hash-table", "Hash Table"],
        ["dynamic-programming", "Dynamic Programming"], ["math", "Math"], ["sorting", "Sorting"],
        ["greedy", "Greedy"], ["depth-first-search", "DFS"], ["breadth-first-search", "BFS"],
        ["binary-search", "Binary Search"], ["two-pointers", "Two Pointers"], ["sliding-window", "Sliding Window"],
        ["tree", "Tree"], ["binary-tree", "Binary Tree"], ["graph", "Graph"], ["stack", "Stack"],
        ["monotonic-stack", "Monotonic Stack"], ["heap-priority-queue", "Heap"], ["linked-list", "Linked List"],
        ["backtracking", "Backtracking"], ["bit-manipulation", "Bit Manipulation"], ["prefix-sum", "Prefix Sum"],
        ["matrix", "Matrix"], ["union-find", "Union Find"], ["trie", "Trie"], ["recursion", "Recursion"],
        ["simulation", "Simulation"], ["design", "Design"]
    ]
    function filterJson(extra) {
        let sort = root.fSort.split("|");
        let o = { difficulty: root.fDifficulty, status: root.fStatus, tags: root.fTags,
                  orderBy: sort[0], sortOrder: sort[1] };
        for (let k in extra) o[k] = extra[k];
        return JSON.stringify(o);
    }
    function loadBrowse(reset) {
        if (reset) {
            listProc.running = false;
            root.browseRows = [];
            root.browseTotal = 0;
        } else if (listProc.running || root.browseRows.length >= root.browseTotal) {
            return;
        }
        root.browseLoading = true;
        listProc.command = ["python3", "-I", root.dir + "/lc.py", "list",
                            root.filterJson({ skip: root.browseRows.length, limit: 50 })];
        listProc.running = true;
    }
    function toggleTag(slug) {
        let t = root.fTags.slice(), i = t.indexOf(slug);
        if (i >= 0) t.splice(i, 1); else t.push(slug);
        root.fTags = t;
        loadBrowse(true);
    }
    function browse() {
        root.browsing = true;
        if (root.browseRows.length === 0) loadBrowse(true);
    }

    function open(slug) {
        if (fetchProc.running) return;
        root.busy = "fetch";
        root.error = "";
        fetchProc.command = ["python3", "-I", root.dir + "/lc.py", "fetch", slug || "daily"];
        fetchProc.running = true;
    }
    function judge(kind) {
        if (!root.problem || root.busy !== "") return;
        focusSink.forceActiveFocus();   // commits a test field that is still being edited
        root.busy = kind;
        root.error = "";
        root.result = null;
        root.tab = 2;
        // 1) write tests.txt  2) make nvim save its buffers  3) run/submit
        testsWriter.then = kind;
        testsWriter.command = ["bash", "-c", "printf '%s\\n' \"$2\" > \"$1\"", "_",
                               root.problem.dir + "/tests.txt", root.tests.join("\n")];
        testsWriter.running = true;
    }
    function openEditor(slug) {
        Quickshell.execDetached(["bash", root.dir + "/lc_open.sh", slug]);
    }

    IpcHandler {
        target: "lc"
        function open(slug: string): void { root.browsing = false; root.open(slug); }
        function browse(): void { root.browse(); }
        function run(): void { root.judge("run"); }
        function submit(): void { root.judge("submit"); }
        function tab(i: int): void { root.tab = i; }
        function scroll(frac: real): void { descFlick.contentY = Math.max(0, (descFlick.contentHeight - descFlick.height) * frac); }
    }

    Process {
        id: fetchProc
        stdout: StdioCollector {
            onStreamFinished: {
                root.busy = "";
                let d; try { d = JSON.parse(this.text); } catch (e) { root.error = "Couldn't read lc.py output"; return; }
                if (d.error) { root.error = d.error; return; }
                root.problem = d;
                root.tests = d.tests && d.tests.length ? d.tests : [""];
                root.result = null;
                root.selCase = 0;
                root.tab = 0;
                descFlick.contentY = 0;
            }
        }
    }

    Process {
        id: testsWriter
        property string then: ""
        onExited: {
            saveNvim.then = then;
            saveNvim.command = ["bash", "-c",
                "[ -S \"$1\" ] && timeout 2 nvim --server \"$1\" --remote-expr \"execute('silent! wall')\" >/dev/null 2>&1; true",
                "_", root.nvimSock];
            saveNvim.running = true;
        }
    }
    Process {
        id: saveNvim
        property string then: ""
        onExited: {
            judgeProc.command = ["python3", "-I", root.dir + "/lc.py", then, root.problem.slug];
            judgeProc.running = true;
        }
    }
    Process {
        id: judgeProc
        stdout: StdioCollector {
            onStreamFinished: {
                root.busy = "";
                let d; try { d = JSON.parse(this.text); } catch (e) { root.error = "Couldn't read lc.py output"; return; }
                if (d.error && !d.kind) { root.error = d.error; return; }
                root.result = d;
                root.selCase = 0;
                if (d.cases) for (let i = 0; i < d.cases.length; i++) if (!d.cases[i].passed) { root.selCase = i; break; }
            }
        }
    }
    Process {
        id: listProc
        stdout: StdioCollector {
            onStreamFinished: {
                root.browseLoading = false;
                let d; try { d = JSON.parse(this.text); } catch (e) { return; }
                if (d.error) { root.error = d.error; return; }
                root.browseTotal = d.total;
                root.browseRows = root.browseRows.concat(d.results);
            }
        }
    }
    Process {
        id: randomProc
        stdout: StdioCollector {
            onStreamFinished: {
                root.busy = "";
                let d; try { d = JSON.parse(this.text); } catch (e) { return; }
                if (d.error) { root.error = d.error; return; }
                root.browsing = false;
                root.openEditor(d.slug);
            }
        }
    }
    function randomProblem() {
        if (randomProc.running) return;
        root.busy = "fetch";
        randomProc.command = ["python3", "-I", root.dir + "/lc.py", "random", root.filterJson({})];
        randomProc.running = true;
    }

    Component.onCompleted: {
        open(Quickshell.env("LC_SLUG") || "daily");
        if (Quickshell.env("LC_BROWSE") === "1") browse();
    }

    // ======================================================================
    FloatingWindow {
        id: win
        title: "LeetCode"
        // closing the window ends the app, so the launcher starts a fresh one next time
        onClosed: Qt.quit()
        implicitWidth: 820
        implicitHeight: 1000
        color: root.base

        Item { id: focusSink; focus: false }
        Shortcut { sequence: "Ctrl+Return"; onActivated: root.judge("run") }
        Shortcut { sequence: "Ctrl+Shift+Return"; onActivated: root.judge("submit") }
        Shortcut { sequence: "Ctrl+B"; onActivated: root.browsing ? root.browsing = false : root.browse() }
        Shortcut { sequence: "Ctrl+R"; onActivated: root.randomProblem() }
        Shortcut { sequence: "Ctrl+1"; onActivated: root.tab = 0 }
        Shortcut { sequence: "Ctrl+2"; onActivated: root.tab = 1 }
        Shortcut { sequence: "Ctrl+3"; onActivated: root.tab = 2 }

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 18
            spacing: 14

            // ---------------- top bar ----------------
            RowLayout {
                Layout.fillWidth: true
                spacing: 8
                PillButton {
                    label: root.browsing ? "Back to problem" : "Browse problems"
                    icon: root.browsing ? "\uf060" : "\uf03a"
                    primary: root.browsing
                    enabled: !(root.browsing && root.problem === null)
                    onClicked: root.browsing ? root.browsing = false : root.browse()
                }
                Item { Layout.fillWidth: true }
                PillButton { label: "Random"; icon: "\uf074"; enabled: root.busy === ""; onClicked: root.randomProblem() }
                PillButton { label: "Daily"; icon: "\uf073"; onClicked: { root.browsing = false; root.openEditor("daily"); } }
            }

            // ---------------- problem browser ----------------
            ColumnLayout {
                Layout.fillWidth: true
                Layout.fillHeight: true
                visible: root.browsing
                spacing: 12

                RowLayout {
                    Layout.fillWidth: true
                    Text {
                        Layout.fillWidth: true
                        text: "Problems"
                        color: root.text
                        font.family: root.ui; font.weight: Font.Bold; font.pixelSize: 24
                    }
                    Text {
                        text: root.browseLoading && root.browseRows.length === 0 ? "Loading…"
                            : root.browseTotal.toLocaleString(Qt.locale("en_US"), "f", 0) + " problems"
                        color: root.overlay0
                        font.family: root.ui; font.pixelSize: 13
                    }
                }

                // difficulty / status / sort
                Flow {
                    Layout.fillWidth: true
                    spacing: 6
                    Repeater {
                        model: [["", "All"], ["EASY", "Easy"], ["MEDIUM", "Medium"], ["HARD", "Hard"]]
                        FilterChip {
                            label: modelData[1]
                            on: root.fDifficulty === modelData[0]
                            fg: modelData[0] === "" ? root.mAccent : root.diffColor(modelData[1])
                            onClicked: { root.fDifficulty = modelData[0]; root.loadBrowse(true); }
                        }
                    }
                    Item { width: 10; height: 1 }
                    Repeater {
                        model: [["", "Any status"], ["NOT_STARTED", "Todo"], ["TRIED", "Attempted"], ["AC", "Solved"]]
                        FilterChip {
                            label: modelData[1]
                            on: root.fStatus === modelData[0]
                            onClicked: { root.fStatus = modelData[0]; root.loadBrowse(true); }
                        }
                    }
                    Item { width: 10; height: 1 }
                    Repeater {
                        model: [["FRONTEND_ID|ASCENDING", "# order"], ["AC_RATE|DESCENDING", "Easiest first"], ["AC_RATE|ASCENDING", "Hardest first"]]
                        FilterChip {
                            label: modelData[1]
                            on: root.fSort === modelData[0]
                            onClicked: { root.fSort = modelData[0]; root.loadBrowse(true); }
                        }
                    }
                }

                // topics
                Flow {
                    Layout.fillWidth: true
                    spacing: 6
                    Repeater {
                        model: root.topics
                        FilterChip {
                            label: modelData[1]
                            small: true
                            on: root.fTags.indexOf(modelData[0]) >= 0
                            onClicked: root.toggleTag(modelData[0])
                        }
                    }
                }

                // list
                Rectangle {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    radius: 20
                    color: root.mantle
                    border.width: 1
                    border.color: root.tint(0.06)
                    clip: true

                    Text {
                        anchors.centerIn: parent
                        visible: !root.browseLoading && root.browseRows.length === 0
                        text: "No problems match these filters"
                        color: root.overlay0
                        font.family: root.ui; font.pixelSize: 14
                    }
                    Spinner { anchors.centerIn: parent; visible: root.browseLoading && root.browseRows.length === 0 }

                    ListView {
                        id: browseList
                        anchors.fill: parent
                        anchors.margins: 6
                        clip: true
                        model: root.browseRows
                        boundsBehavior: Flickable.StopAtBounds
                        ScrollBar.vertical: ThinBar {}
                        onContentYChanged: if (contentY + height > contentHeight - 400) root.loadBrowse(false)
                        footer: Item {
                            width: browseList.width
                            height: root.browseLoading && root.browseRows.length > 0 ? 44 : 0
                            Spinner { anchors.centerIn: parent; visible: parent.height > 0; scale: 0.7 }
                        }
                        delegate: Rectangle {
                            width: browseList.width - 8
                            height: 46
                            radius: 12
                            color: bMa.containsMouse && !modelData.paid ? root.acc(0.12) : "transparent"
                            opacity: modelData.paid ? 0.4 : 1
                            RowLayout {
                                anchors.fill: parent
                                anchors.leftMargin: 14
                                anchors.rightMargin: 14
                                spacing: 12
                                Text {
                                    Layout.preferredWidth: 16
                                    text: modelData.status === "ac" ? "\uf00c" : modelData.status === "notac" ? "\uf10c" : modelData.paid ? "\uf023" : ""
                                    color: modelData.status === "ac" ? root.green : modelData.status === "notac" ? root.amber : root.overlay0
                                    font.family: root.mono; font.pixelSize: 12
                                }
                                Text {
                                    Layout.fillWidth: true
                                    elide: Text.ElideRight
                                    text: modelData.id + ". " + modelData.title
                                    color: root.text
                                    font.family: root.ui; font.pixelSize: 14
                                }
                                Text {
                                    text: modelData.tags.join(" · ")
                                    color: root.overlay0
                                    font.family: root.ui; font.pixelSize: 12
                                    elide: Text.ElideRight
                                    Layout.maximumWidth: 260
                                }
                                Text {
                                    text: modelData.acRate + "%"
                                    color: root.subtext0
                                    font.family: root.ui; font.pixelSize: 12
                                    Layout.preferredWidth: 36
                                    horizontalAlignment: Text.AlignRight
                                }
                                Text {
                                    text: modelData.difficulty
                                    color: root.diffColor(modelData.difficulty)
                                    font.family: root.ui; font.weight: Font.DemiBold; font.pixelSize: 12
                                    Layout.preferredWidth: 54
                                    horizontalAlignment: Text.AlignRight
                                }
                            }
                            MouseArea {
                                id: bMa
                                anchors.fill: parent
                                hoverEnabled: true
                                enabled: !modelData.paid
                                cursorShape: Qt.PointingHandCursor
                                onClicked: { root.browsing = false; root.openEditor(modelData.slug); }
                            }
                        }
                    }
                }
            }

            // ---------------- title ----------------
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 8
                visible: root.problem !== null && !root.browsing

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 10
                    Text {
                        Layout.fillWidth: true
                        elide: Text.ElideRight
                        text: root.problem ? root.problem.id + ". " + root.problem.title : ""
                        color: root.text
                        font.family: root.ui; font.weight: Font.Bold; font.pixelSize: 24
                    }
                    PillButton { label: "nvim"; icon: ""; onClicked: root.openEditor(root.problem.slug) }
                    PillButton { label: "Web"; icon: ""; onClicked: Quickshell.execDetached(["xdg-open", root.problem.url]) }
                }
                Flow {
                    Layout.fillWidth: true
                    spacing: 6
                    Chip { label: root.problem ? root.problem.difficulty : ""; fg: root.diffColor(root.problem ? root.problem.difficulty : ""); filled: true }
                    Chip { label: root.problem ? root.problem.acRate + "% accepted" : "" }
                    Chip { label: root.problem ? "  " + root.problem.likes : "" }
                    Repeater {
                        model: root.problem ? root.problem.tags : []
                        Chip { label: modelData; outlined: true }
                    }
                }
            }

            // ---------------- tabs ----------------
            Row {
                Layout.fillWidth: true
                visible: !root.browsing
                spacing: 6
                Repeater {
                    model: ["Description", "Testcases", "Result"]
                    Rectangle {
                        readonly property bool on: root.tab === index
                        width: tabRow.implicitWidth + 28
                        height: 34
                        radius: 17
                        color: on ? root.acc(0.18) : tMa.containsMouse ? root.tint(0.06) : "transparent"
                        Behavior on color { ColorAnimation { duration: 150 } }
                        Row {
                            id: tabRow
                            anchors.centerIn: parent
                            spacing: 7
                            Text {
                                text: modelData + (index === 1 ? "  " + root.tests.length : "")
                                color: on ? root.mAccent : root.subtext0
                                font.family: root.ui; font.weight: on ? Font.DemiBold : Font.Normal; font.pixelSize: 14
                            }
                            Rectangle {   // result status dot
                                visible: index === 2 && (root.result !== null || root.busy === "run" || root.busy === "submit")
                                anchors.verticalCenter: parent.verticalCenter
                                width: 7; height: 7; radius: 4
                                color: root.busy !== "" ? root.amber : root.result && root.result.ok ? root.green : root.red
                            }
                        }
                        MouseArea { id: tMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.tab = index }
                    }
                }
            }

            // ---------------- content ----------------
            Rectangle {
                Layout.fillWidth: true
                Layout.fillHeight: true
                visible: !root.browsing
                radius: 20
                color: root.mantle
                border.width: 1
                border.color: root.tint(0.06)
                clip: true

                // loading / error overlay
                Text {
                    anchors.centerIn: parent
                    visible: root.problem === null
                    text: root.error !== "" ? root.error : "Loading…"
                    color: root.error !== "" ? root.red : root.overlay0
                    font.family: root.ui; font.pixelSize: 15
                    width: parent.width - 60
                    horizontalAlignment: Text.AlignHCenter
                    wrapMode: Text.WordWrap
                }

                StackLayout {
                    anchors.fill: parent
                    anchors.margins: 4
                    currentIndex: root.tab
                    visible: root.problem !== null

                    // ---- description ----
                    Flickable {
                        id: descFlick
                        clip: true
                        contentWidth: width
                        contentHeight: descCol.implicitHeight + 40
                        boundsBehavior: Flickable.StopAtBounds
                        ScrollBar.vertical: ThinBar {}

                        Column {
                            id: descCol
                            x: 20; y: 18
                            width: descFlick.width - 40
                            spacing: 18

                            Text {
                                width: parent.width
                                wrapMode: Text.Wrap
                                textFormat: Text.RichText
                                color: root.text
                                linkColor: root.mAccent
                                font.family: root.ui
                                font.pixelSize: 15
                                lineHeight: 1.15
                                text: root.problem ?
                                    "<style>"
                                    // matugen palette: accent for example headings/values, surface for code
                                    + "pre { font-family: '" + root.mono + "'; font-size: 13px; color: " + root.mSub + "; background-color: " + root.mSurface + "; }"
                                    + "code { font-family: '" + root.mono + "'; font-size: 13px; color: " + root.mText + "; background-color: " + root.mSurface + "; }"
                                    + "strong { color: " + root.mText + "; }"
                                    + ".example { color: " + root.mAccent + "; }"
                                    + ".example-block { color: " + root.mSub + "; margin-left: 14px; }"
                                    + ".example-io { font-family: '" + root.mono + "'; font-size: 13px; color: " + root.mAccent + "; }"
                                    + "li { margin-bottom: 4px; }"
                                    + "</style>" + root.problem.content : ""
                                onLinkActivated: (link) => Quickshell.execDetached(["xdg-open", link])
                            }

                            // hints (click to reveal)
                            Repeater {
                                model: root.problem ? root.problem.hints : []
                                Rectangle {
                                    id: hint
                                    property bool shown: false
                                    width: descCol.width
                                    height: hintCol.implicitHeight + 22
                                    radius: 14
                                    color: hMa.containsMouse ? root.surface1 : root.surface0
                                    Column {
                                        id: hintCol
                                        x: 14; y: 11
                                        width: parent.width - 28
                                        spacing: 6
                                        Text {
                                            text: (hint.shown ? "  Hint " : "  Show hint ") + (index + 1)
                                            color: root.mAccent2
                                            font.family: root.ui; font.weight: Font.DemiBold; font.pixelSize: 13
                                        }
                                        Text {
                                            visible: hint.shown
                                            width: parent.width
                                            wrapMode: Text.Wrap
                                            text: modelData
                                            color: root.subtext0
                                            font.family: root.ui; font.pixelSize: 14
                                        }
                                    }
                                    MouseArea { id: hMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: hint.shown = !hint.shown }
                                }
                            }
                        }
                    }

                    // ---- testcases ----
                    Flickable {
                        clip: true
                        contentWidth: width
                        contentHeight: testCol.implicitHeight + 40
                        boundsBehavior: Flickable.StopAtBounds
                        ScrollBar.vertical: ThinBar {}

                        Column {
                            id: testCol
                            x: 18; y: 16
                            width: parent.width - 36
                            spacing: 12

                            Repeater {
                                model: root.tests.length
                                Rectangle {
                                    id: caseCard
                                    readonly property int ci: index
                                    readonly property var lines: (root.tests[ci] || "").split("\n")
                                    width: testCol.width
                                    height: caseInner.implicitHeight + 28
                                    radius: 16
                                    color: root.surface0
                                    border.width: 1
                                    border.color: root.tint(0.06)

                                    Column {
                                        id: caseInner
                                        x: 16; y: 14
                                        width: parent.width - 32
                                        spacing: 10
                                        RowLayout {
                                            width: parent.width
                                            Text {
                                                Layout.fillWidth: true
                                                text: "Case " + (caseCard.ci + 1)
                                                color: root.text
                                                font.family: root.ui; font.weight: Font.DemiBold; font.pixelSize: 14
                                            }
                                            Text {
                                                visible: root.tests.length > 1
                                                text: ""
                                                color: delMa.containsMouse ? root.red : root.overlay0
                                                font.family: root.mono; font.pixelSize: 13
                                                MouseArea {
                                                    id: delMa
                                                    anchors.fill: parent; anchors.margins: -8
                                                    hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                                    onClicked: { let t = root.tests.slice(); t.splice(caseCard.ci, 1); root.tests = t; }
                                                }
                                            }
                                        }
                                        Repeater {
                                            model: root.problem ? root.problem.params : []
                                            Column {
                                                width: caseInner.width
                                                spacing: 5
                                                Text { text: modelData + " ="; color: root.subtext0; font.family: root.mono; font.pixelSize: 12 }
                                                Rectangle {
                                                    width: parent.width
                                                    height: Math.max(36, field.implicitHeight + 14)
                                                    radius: 10
                                                    color: field.activeFocus ? root.acc(0.08) : root.surface1
                                                    border.width: 1
                                                    border.color: field.activeFocus ? root.acc(0.55) : "transparent"
                                                    TextEdit {
                                                        id: field
                                                        anchors.fill: parent
                                                        anchors.margins: 9
                                                        text: caseCard.lines[index] !== undefined ? caseCard.lines[index] : ""
                                                        color: root.text
                                                        selectionColor: root.acc(0.35)
                                                        font.family: root.mono; font.pixelSize: 13
                                                        wrapMode: TextEdit.WrapAnywhere
                                                        selectByMouse: true
                                                        // values are single-line: Enter just commits (Ctrl+Enter still runs)
                                                        Keys.onReturnPressed: (e) => {
                                                            if (e.modifiers & Qt.ControlModifier) { e.accepted = false; return; }
                                                            focusSink.forceActiveFocus();
                                                            e.accepted = true;
                                                        }
                                                        onEditingFinished: {
                                                            let ls = caseCard.lines.slice();
                                                            while (ls.length < root.problem.params.length) ls.push("");
                                                            ls[index] = text.replace(/\n/g, "");
                                                            let t = root.tests.slice();
                                                            t[caseCard.ci] = ls.join("\n");
                                                            root.tests = t;
                                                        }
                                                    }
                                                }
                                            }
                                        }
                                    }
                                }
                            }

                            PillButton {
                                label: "Add case"
                                icon: ""
                                onClicked: { let t = root.tests.slice(); t.push(t.length ? t[t.length - 1] : ""); root.tests = t; }
                            }
                        }
                    }

                    // ---- result ----
                    Flickable {
                        clip: true
                        contentWidth: width
                        contentHeight: resCol.implicitHeight + 40
                        boundsBehavior: Flickable.StopAtBounds
                        ScrollBar.vertical: ThinBar {}

                        // idle / busy placeholder
                        Column {
                            anchors.centerIn: parent
                            visible: root.result === null
                            spacing: 14
                            Spinner { anchors.horizontalCenter: parent.horizontalCenter; visible: root.busy === "run" || root.busy === "submit" }
                            Text {
                                anchors.horizontalCenter: parent.horizontalCenter
                                text: root.busy === "run" ? "Running…" : root.busy === "submit" ? "Judging submission…"
                                    : root.error !== "" ? root.error : "Run (Ctrl+Enter) or Submit (Ctrl+Shift+Enter)"
                                color: root.error !== "" && root.busy === "" ? root.red : root.overlay0
                                font.family: root.ui; font.pixelSize: 15
                            }
                        }

                        Column {
                            id: resCol
                            x: 20; y: 18
                            width: parent.width - 40
                            spacing: 16
                            visible: root.result !== null

                            // status line
                            Column {
                                spacing: 4
                                Text {
                                    text: root.result ? root.result.status : ""
                                    color: root.result && root.result.ok ? root.green : root.red
                                    font.family: root.ui; font.weight: Font.Bold; font.pixelSize: 26
                                }
                                Text {
                                    visible: text !== ""
                                    text: !root.result ? ""
                                        : root.result.kind === "submit" && root.result.total
                                            ? root.result.passed + " / " + root.result.total + " testcases passed"
                                        : root.result.kind === "run" && root.result.runtime && root.result.runtime !== "N/A"
                                            ? "Runtime " + root.result.runtime : ""
                                    color: root.subtext0
                                    font.family: root.ui; font.pixelSize: 14
                                }
                            }

                            // submit: runtime / memory with percentiles
                            Row {
                                width: parent.width
                                spacing: 10
                                visible: root.result !== null && root.result.kind === "submit" && root.result.ok
                                Repeater {
                                    model: root.result && root.result.kind === "submit" ? [
                                        { icon: "", label: "Runtime", value: root.result.runtime, pct: root.result.runtimePct },
                                        { icon: "", label: "Memory", value: root.result.memory, pct: root.result.memoryPct }
                                    ] : []
                                    Rectangle {
                                        width: (parent.width - 10) / 2
                                        height: 84
                                        radius: 16
                                        color: root.surface0
                                        Column {
                                            anchors.left: parent.left; anchors.leftMargin: 18
                                            anchors.verticalCenter: parent.verticalCenter
                                            spacing: 4
                                            Text { text: modelData.icon + "  " + modelData.label; color: root.subtext0; font.family: root.mono; font.pixelSize: 12 }
                                            Text { text: modelData.value; color: root.text; font.family: root.ui; font.weight: Font.Bold; font.pixelSize: 22 }
                                            Text {
                                                visible: modelData.pct !== null && modelData.pct !== undefined
                                                text: "Beats " + modelData.pct + "%"
                                                color: root.green
                                                font.family: root.ui; font.pixelSize: 13
                                            }
                                        }
                                    }
                                }
                            }

                            // compile / runtime error
                            Rectangle {
                                width: parent.width
                                visible: root.result !== null && root.result.error !== ""
                                height: errText.implicitHeight + 28
                                radius: 14
                                color: Qt.alpha(root.red, 0.1)
                                border.width: 1
                                border.color: Qt.alpha(root.red, 0.3)
                                Text {
                                    id: errText
                                    x: 14; y: 14
                                    width: parent.width - 28
                                    text: root.result ? root.result.error : ""
                                    color: "#ffb4ae"
                                    wrapMode: Text.WrapAnywhere
                                    font.family: root.mono; font.pixelSize: 12
                                }
                            }

                            // run: case selector
                            Row {
                                spacing: 6
                                visible: root.result !== null && root.result.kind === "run" && root.result.error === ""
                                Repeater {
                                    model: root.result && root.result.cases ? root.result.cases : []
                                    Rectangle {
                                        readonly property bool on: root.selCase === index
                                        width: cRow.implicitWidth + 24
                                        height: 32
                                        radius: 16
                                        color: on ? root.acc(0.18) : cMa.containsMouse ? root.tint(0.06) : "transparent"
                                        Row {
                                            id: cRow
                                            anchors.centerIn: parent
                                            spacing: 6
                                            Rectangle { anchors.verticalCenter: parent.verticalCenter; width: 7; height: 7; radius: 4; color: modelData.passed ? root.green : root.red }
                                            Text { text: "Case " + (index + 1); color: on ? root.text : root.subtext0; font.family: root.ui; font.pixelSize: 13 }
                                        }
                                        MouseArea { id: cMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.selCase = index }
                                    }
                                }
                            }

                            // details of the selected / failing case
                            Repeater {
                                model: {
                                    let r = root.result;
                                    if (!r || r.error !== "") return [];
                                    let c = r.kind === "run" ? (r.cases || [])[root.selCase] : r.failing;
                                    if (!c) return [];
                                    let rows = [];
                                    let inp = c.input || [];
                                    for (let i = 0; i < inp.length; i++)
                                        rows.push({ label: (r.params && r.params[i] ? r.params[i] : "input") + " =", value: inp[i], color: root.text });
                                    rows.push({ label: "Output", value: String(c.output), color: c.passed === false || r.kind === "submit" ? root.red : root.text });
                                    rows.push({ label: "Expected", value: String(c.expected), color: root.green });
                                    if (c.stdout) rows.push({ label: "Stdout", value: String(c.stdout), color: root.subtext0 });
                                    if (r.kind === "submit") rows.unshift({ label: "Failing testcase", value: "", color: root.text, header: true });
                                    return rows;
                                }
                                Column {
                                    width: resCol.width
                                    spacing: 6
                                    Text { text: modelData.label; color: root.subtext0; font.family: modelData.header ? root.ui : root.mono; font.pixelSize: modelData.header ? 15 : 12; font.weight: modelData.header ? Font.DemiBold : Font.Normal }
                                    Rectangle {
                                        visible: !modelData.header
                                        width: parent.width
                                        height: valText.implicitHeight + 22
                                        radius: 10
                                        color: root.surface0
                                        Text {
                                            id: valText
                                            x: 12; y: 11
                                            width: parent.width - 24
                                            text: modelData.value
                                            color: modelData.color
                                            wrapMode: Text.WrapAnywhere
                                            textFormat: Text.PlainText
                                            font.family: root.mono; font.pixelSize: 13
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }

            // ---------------- bottom bar ----------------
            RowLayout {
                Layout.fillWidth: true
                visible: !root.browsing
                spacing: 10
                Text {
                    Layout.fillWidth: true
                    elide: Text.ElideRight
                    text: root.busy === "fetch" ? "Loading problem…"
                        : root.problem ? root.problem.lang.toUpperCase().replace("CPP", "C++") + "  ·  " + root.problem.file.replace(Quickshell.env("HOME"), "~") : ""
                    color: root.overlay0
                    font.family: root.ui; font.pixelSize: 12
                }
                PillButton {
                    label: root.busy === "run" ? "Running…" : "Run"
                    icon: ""
                    enabled: root.problem !== null && root.busy === ""
                    onClicked: root.judge("run")
                }
                PillButton {
                    label: root.busy === "submit" ? "Judging…" : "Submit"
                    icon: ""
                    primary: true
                    enabled: root.problem !== null && root.busy === ""
                    onClicked: root.judge("submit")
                }
            }
        }
    }

    // ======================================================================
    component PillButton: Rectangle {
        id: pb
        property string label: ""
        property string icon: ""
        property bool primary: false
        signal clicked()
        implicitWidth: pbRow.implicitWidth + 30
        implicitHeight: 38
        Layout.preferredWidth: implicitWidth
        Layout.preferredHeight: implicitHeight
        radius: height / 2
        opacity: enabled ? 1 : 0.45
        color: primary ? (pbMa.containsMouse ? Qt.lighter(root.mAccent, 1.08) : root.mAccent)
                       : (pbMa.containsMouse ? root.surface1 : root.surface0)
        border.width: primary ? 0 : 1
        border.color: root.tint(0.1)
        scale: pbMa.pressed ? 0.96 : 1
        Behavior on color { ColorAnimation { duration: 150 } }
        Behavior on scale { NumberAnimation { duration: 120 } }
        Row {
            id: pbRow
            anchors.centerIn: parent
            spacing: 8
            Text {
                visible: pb.icon !== ""
                anchors.verticalCenter: parent.verticalCenter
                text: pb.icon
                color: pb.primary ? root.base : root.subtext0
                font.family: root.mono; font.pixelSize: 12
            }
            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: pb.label
                color: pb.primary ? root.base : root.text
                font.family: root.ui; font.weight: Font.DemiBold; font.pixelSize: 13
            }
        }
        MouseArea { id: pbMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: pb.clicked() }
    }

    component FilterChip: Rectangle {
        id: fc
        property string label: ""
        property bool on: false
        property bool small: false
        property color fg: root.mAccent
        signal clicked()
        width: fcText.implicitWidth + (small ? 18 : 24)
        height: small ? 28 : 32
        radius: height / 2
        color: on ? Qt.alpha(fg, 0.2) : fcMa.containsMouse ? root.surface1 : root.surface0
        border.width: 1
        border.color: on ? Qt.alpha(fg, 0.6) : root.tint(0.06)
        Behavior on color { ColorAnimation { duration: 120 } }
        Text {
            id: fcText
            anchors.centerIn: parent
            text: fc.label
            color: fc.on ? fc.fg : root.subtext0
            font.family: root.ui; font.weight: fc.on ? Font.DemiBold : Font.Normal; font.pixelSize: fc.small ? 12 : 13
        }
        MouseArea { id: fcMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: fc.clicked() }
    }

    component Chip: Rectangle {
        property string label: ""
        property color fg: root.subtext0
        property bool filled: false
        property bool outlined: false
        visible: label !== ""
        width: chipText.implicitWidth + 18
        height: 24
        radius: 12
        color: filled ? Qt.alpha(fg, 0.18) : outlined ? "transparent" : root.surface1
        border.width: outlined ? 1 : 0
        border.color: root.tint(0.14)
        Text {
            id: chipText
            anchors.centerIn: parent
            text: parent.label
            color: parent.fg
            font.family: root.ui; font.weight: parent.filled ? Font.DemiBold : Font.Normal; font.pixelSize: 12
        }
    }

    component ThinBar: ScrollBar {
        width: 6
        padding: 0
        policy: ScrollBar.AsNeeded
        contentItem: Rectangle { implicitWidth: 6; radius: 3; color: root.acc(0.45) }
        background: Item {}
    }

    component Spinner: Item {
        width: 28; height: 28
        Rectangle {
            anchors.fill: parent
            radius: width / 2
            color: "transparent"
            border.width: 3
            border.color: root.tint(0.15)
        }
        Rectangle {
            width: 7; height: 7; radius: 4
            color: root.mAccent
            x: parent.width / 2 - width / 2; y: -1
        }
        RotationAnimation on rotation { from: 0; to: 360; duration: 900; loops: Animation.Infinite; running: parent.visible }
    }
}
