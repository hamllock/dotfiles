import QtQuick
import QtQuick.Effects

// The round "hero" orb at the top of the Wi-Fi / Bluetooth / Claude popups, in the
// spirit of the Volume and Battery orbs: shadowed core, accent rim, soft inner glow
// that breathes while `active`, bouncy hover. Put the orb's content inside it.
Item {
    id: orb
    property color accent: "white"
    property color base: "black"
    property bool active: false
    property bool hoverable: true
    default property alias content: core.data
    signal clicked()

    scale: ma.pressed ? 0.94 : (ma.containsMouse && hoverable ? 1.06 : 1.0)
    Behavior on scale { NumberAnimation { duration: 400; easing.type: Easing.OutBack } }

    MultiEffect {
        source: core
        anchors.fill: core
        shadowEnabled: true
        shadowColor: "#000000"
        shadowOpacity: 0.5
        shadowBlur: 1.2
        shadowVerticalOffset: 6
        z: -1
    }

    Rectangle {
        id: core
        anchors.fill: parent
        radius: width / 2
        color: orb.base
        border.width: 2
        border.color: orb.active ? Qt.lighter(orb.accent, 1.1) : Qt.rgba(orb.accent.r, orb.accent.g, orb.accent.b, 0.25)
        clip: true
        Behavior on border.color { ColorAnimation { duration: 400 } }

        // inner glow, breathing while active
        Rectangle {
            id: glow
            anchors.centerIn: parent
            width: parent.width * 1.1; height: width; radius: width / 2
            property real breath: 0
            SequentialAnimation on breath {
                running: orb.active; loops: Animation.Infinite
                NumberAnimation { to: 1; duration: 1800; easing.type: Easing.InOutSine }
                NumberAnimation { to: 0; duration: 1800; easing.type: Easing.InOutSine }
            }
            opacity: orb.active ? 0.22 + 0.16 * breath : 0.06
            Behavior on opacity { NumberAnimation { duration: 500 } }
            gradient: Gradient {
                GradientStop { position: 0.0; color: Qt.lighter(orb.accent, 1.25) }
                GradientStop { position: 1.0; color: orb.base }
            }
        }
    }

    MouseArea {
        id: ma
        anchors.fill: parent
        hoverEnabled: orb.hoverable
        cursorShape: orb.hoverable ? Qt.PointingHandCursor : Qt.ArrowCursor
        onClicked: orb.clicked()
    }
}
