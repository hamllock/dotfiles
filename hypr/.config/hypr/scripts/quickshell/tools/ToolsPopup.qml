import QtQuick
import QtQuick.Layouts
import QtQuick.Window
import Quickshell
import "../"

// Tools popup (dashboard "Tools" button): the Draw pad, Timer and System usage that used
// to live in the screen-edge sidebar, side by side. Main.qml preloads this popup and keeps
// it alive, so a running timer / stopwatch / pomodoro keeps going while it's closed.
Item {
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

    // one scale for the column of small tools; Draw stretches to the column's height
    readonly property real gap: s(20)
    readonly property real k: 1.15

    // ---------------- intro (replays on every open) ----------------
    property real intro: 0
    property real introCards: 0
    ParallelAnimation {
        id: introAnim
        running: true
        NumberAnimation { target: root; property: "intro"; from: 0; to: 1; duration: 700; easing.type: Easing.OutExpo }
        SequentialAnimation {
            PauseAnimation { duration: 120 }
            NumberAnimation { target: root; property: "introCards"; from: 0; to: 1; duration: 900; easing.type: Easing.OutCubic }
        }
    }
    onVisibleChanged: if (visible) introAnim.restart()

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

        RowLayout {
            anchors.centerIn: parent
            spacing: root.gap

            // Draw: as tall as Timer + System together
            ToolCard {
                src: "../quickactions/DrawAction.qml"
                baseW: 600; baseH: 500
                scaleK: root.k * (340 + 250 + root.gap / root.s(1) / root.k) / 500
                order: 0
            }

            ColumnLayout {
                spacing: root.gap
                ToolCard { src: "../quickactions/Timer.qml"; baseW: 400; baseH: 340; scaleK: root.k; order: 1 }
                ToolCard { src: "../quickactions/SystemUsage.qml"; baseW: 400; baseH: 250; scaleK: root.k; order: 2 }
            }
        }
    }

    // A tool module on the card + background tiles it lays itself onto (as the sidebar drew them)
    component ToolCard: Item {
        id: card
        property url src
        property real baseW
        property real baseH
        property real scaleK: 1
        property int order: 0

        Layout.preferredWidth: root.s(baseW) * scaleK
        Layout.preferredHeight: root.s(baseH) * scaleK

        // cards ease in one after another
        readonly property real enter: Math.max(0, Math.min(1, root.introCards * 1.6 - order * 0.25))
        opacity: enter
        transform: Translate { y: root.s(24) * (1 - card.enter) }

        Rectangle {
            anchors.fill: parent
            radius: root.s(26)
            color: Qt.rgba(root.base.r, root.base.g, root.base.b, 0.55)
            border.width: 1
            border.color: Qt.rgba(root.text.r, root.text.g, root.text.b, 0.07)
        }

        Item {
            id: tiles
            anchors.fill: parent
            anchors.margins: root.s(15) * card.scaleK
            readonly property real sp: root.s(10) * card.scaleK
            readonly property var layout: {
                let req = loader.item ? loader.item.requestedLayoutTemplate : undefined;
                if (req === undefined) return [{ x: 0, y: 0, w: 1, h: 1 }];
                if (typeof req === "number")
                    return req === 0 ? [{x:0,y:0,w:0.5,h:0.5},{x:0.5,y:0,w:0.5,h:0.5},{x:0,y:0.5,w:0.5,h:0.5},{x:0.5,y:0.5,w:0.5,h:0.5}]
                                     : [{ x: 0, y: 0, w: 1, h: 1 }];
                return req;
            }
            Repeater {
                model: tiles.layout
                Rectangle {
                    x: modelData.x * tiles.width + (modelData.x > 0 ? tiles.sp / 2 : 0)
                    y: modelData.y * tiles.height + (modelData.y > 0 ? tiles.sp / 2 : 0)
                    width: modelData.w * tiles.width - ((modelData.x > 0 ? tiles.sp / 2 : 0) + ((modelData.x + modelData.w) < 0.99 ? tiles.sp / 2 : 0))
                    height: modelData.h * tiles.height - ((modelData.y > 0 ? tiles.sp / 2 : 0) + ((modelData.y + modelData.h) < 0.99 ? tiles.sp / 2 : 0))
                    radius: root.s(12) * card.scaleK
                    color: Qt.rgba(root.text.r, root.text.g, root.text.b, 0.05)
                    border.width: 1
                    border.color: Qt.rgba(root.text.r, root.text.g, root.text.b, 0.08)
                }
            }
        }

        Loader {
            id: loader
            anchors.fill: parent
            anchors.margins: root.s(15) * card.scaleK
            source: card.src
            // context the modules read (same names the sidebar gave them)
            property var scaleFunc: (v) => root.s(v) * card.scaleK
            property var mochaColors: _theme
            property string activeEdge: "left"
            property bool isCurrentTarget: root.visible
        }
    }
}
