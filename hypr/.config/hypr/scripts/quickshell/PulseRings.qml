import QtQuick

// Concentric rings that expand out of an orb and fade (Wi-Fi / Bluetooth / Claude heroes).
// Size it like the orb it sits behind. While `running` is false the rings fade away.
Item {
    id: pr
    property color color: "white"
    property bool running: true
    property int rings: 3
    property int duration: 2600
    property real maxScale: 1.7
    property real lineWidth: 2
    property real strength: 0.5

    property real level: running ? 1 : 0
    Behavior on level { NumberAnimation { duration: 600; easing.type: Easing.OutCubic } }

    // one shared phase keeps the rings evenly spaced
    property real phase: 0
    NumberAnimation on phase {
        from: 0; to: 1; duration: pr.duration
        loops: Animation.Infinite
        running: pr.level > 0
    }

    Repeater {
        model: pr.rings
        Rectangle {
            readonly property real t: (pr.phase + index / pr.rings) % 1
            anchors.centerIn: parent
            width: pr.width; height: pr.height
            radius: width / 2
            color: "transparent"
            border.width: pr.lineWidth
            border.color: pr.color
            scale: 1 + (pr.maxScale - 1) * t
            opacity: pr.level * pr.strength * (1 - t) * (1 - t)
            visible: opacity > 0.005
        }
    }
}
