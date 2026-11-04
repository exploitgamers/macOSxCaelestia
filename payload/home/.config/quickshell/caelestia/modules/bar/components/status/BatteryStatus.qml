import QtQuick
import Caelestia.Config
import Quickshell.Services.UPower
import qs.components
import qs.services
import qs.utils

// [macos] macOS's menu-bar battery: a translucent outline body with a terminal nub on the right and
// a level fill — green while charging (with a bolt), red when low on battery. No battery (desktop):
// upstream's power-profile symbol.
Item {
    id: root

    required property color colour

    readonly property var dev: UPower.displayDevice
    readonly property bool charging: [UPowerDeviceState.Charging, UPowerDeviceState.FullyCharged, UPowerDeviceState.PendingCharge].includes(dev.state)
    readonly property real level: Math.max(0, Math.min(1, dev.percentage))
    readonly property bool low: UPower.onBattery && level <= 0.2

    // the body is ~half the bar's height and twice as wide, like macOS's 27×13 pt glyph in a 24 pt bar
    readonly property int bodyH: Math.round(Tokens.sizes.bar.innerWidth * 0.48)
    readonly property int bodyW: Math.round(bodyH * 2.1)

    // [macos] + 3: the nub (1 px gap + 1.5 px) spilled 0.5 px past a + 2 slot into the pill's right padding
    implicitWidth: dev.isLaptopBattery ? bodyW + 3 : profile.implicitWidth
    implicitHeight: dev.isLaptopBattery ? bodyH : profile.implicitHeight

    MaterialIcon {
        id: profile

        visible: !root.dev.isLaptopBattery
        fontStyle: Tokens.font.icon.builders.small.scale(Tokens.sizes.bar.innerWidth / 26).build() // [macos] with the bar
        animate: true
        text: PowerProfiles.profile === PowerProfile.PowerSaver ? "energy_savings_leaf" : PowerProfiles.profile === PowerProfile.Performance ? "rocket_launch" : "balance"
        color: root.colour
        fill: 1
    }

    Rectangle {
        id: body

        visible: root.dev.isLaptopBattery
        width: root.bodyW
        height: root.bodyH
        radius: Math.round(height * 0.3)
        color: "transparent"
        border.width: 1
        border.color: Qt.alpha(root.colour, 0.45)

        Rectangle { // level
            x: 2
            y: 2
            height: parent.height - 4
            width: Math.max(height * 0.5, (parent.width - 4) * root.level)
            radius: Math.max(1, parent.radius - 2)
            color: root.charging ? Colours.sys.green : root.low ? Colours.sys.red : root.colour

            Behavior on width {
                Anim {}
            }
            Behavior on color {
                CAnim {}
            }
        }

        MaterialIcon { // bolt, with a thin dark outline so it reads over any fill
            anchors.centerIn: parent
            visible: root.charging && root.level < 1
            text: "bolt"
            fill: 1
            color: "white"
            style: Text.Outline
            styleColor: Qt.alpha("black", 0.45)
            fontStyle: Tokens.font.icon.builders.small.size(Math.round((root.bodyH + 2) * 0.75)).build()
        }
    }

    Rectangle { // terminal nub
        visible: root.dev.isLaptopBattery
        anchors.left: body.right
        anchors.leftMargin: 1
        anchors.verticalCenter: body.verticalCenter
        width: 1.5
        height: Math.round(root.bodyH * 0.36)
        radius: 1
        color: Qt.alpha(root.colour, 0.45)
    }
}
