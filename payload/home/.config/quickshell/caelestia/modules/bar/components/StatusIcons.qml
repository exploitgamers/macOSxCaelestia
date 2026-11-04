pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Caelestia.Config
import qs.components
import qs.services
import qs.utils
import qs.modules.bar.components.status

StyledRect {
    id: root

    required property bool horizontal
    property color colour: pillInk.c(Colours.palette.m3secondary) // [macos] adaptive (BarInk)

    BarInk { id: pillInk; pill: root }
    readonly property alias items: iconColumn

    readonly property int spacing: Tokens.spacing.medium / 2

    // Index of the first/last entry that isn't collapsed, for edge margin gating
    readonly property int firstPresent: {
        const values = model.values;
        for (let i = 0; i < values.length; i++)
            if (!collapsed(values[i]))
                return i;
        return -1;
    }
    readonly property int lastPresent: {
        const values = model.values;
        for (let i = values.length - 1; i >= 0; i--)
            if (!collapsed(values[i]))
                return i;
        return -1;
    }

    // Entries that can shrink to nothing, spacing included
    function collapsed(entry: var): bool {
        if (entry.id === "lockStatus")
            return !Hypr.capsLock && !Hypr.numLock;
        return false;
    }

    color: Colours.tPalette.m3surfaceContainer
    radius: Tokens.rounding.full

    clip: true
    implicitWidth: horizontal ? Math.ceil(iconColumn.implicitWidth + Tokens.padding.medium * 2) : Tokens.sizes.bar.innerWidth // [macos] whole px (even gaps)
    implicitHeight: horizontal ? Tokens.sizes.bar.innerWidth : iconColumn.implicitHeight + Tokens.padding.medium * 2

    GridLayout {
        id: iconColumn

        // Only one orientation's anchors resolve, the others are undefined
        // qmllint disable Quick.anchor-combinations
        anchors.left: root.horizontal ? undefined : parent.left
        anchors.right: root.horizontal ? undefined : parent.right
        anchors.bottom: root.horizontal ? undefined : parent.bottom
        anchors.horizontalCenter: root.horizontal ? parent.horizontalCenter : undefined
        anchors.alignWhenCentered: false // [macos] the pill is whole px now; a rounded offset made the padding uneven
        anchors.verticalCenter: root.horizontal ? parent.verticalCenter : undefined
        anchors.bottomMargin: root.horizontal ? 0 : Tokens.padding.medium
        // qmllint enable Quick.anchor-combinations

        columns: root.horizontal ? -1 : 1
        rowSpacing: 0
        columnSpacing: 0

        Repeater {
            model: ScriptModel {
                id: model

                values: root.Config.bar.statusIcons.values.filter(e => e.enabled)
            }

            DelegateChooser {
                role: "id"

                DelegateChoice {
                    roleValue: "lockStatus"
                    delegate: EntryWrapper {
                        LockStatus {
                            colour: root.colour
                            parentSpacing: root.spacing
                            horizontal: root.horizontal
                        }
                    }
                }
                DelegateChoice {
                    roleValue: "audio"
                    delegate: EntryWrapper {
                        margin: Tokens.spacing.extraSmall / 2

                        MaterialIcon {
                            animate: true
                            text: Icons.getVolumeIcon(Audio.volume, Audio.muted)
                            color: root.colour
                            fontStyle: Tokens.font.icon.builders.medium.scale(Tokens.sizes.bar.innerWidth / 26).build() // [macos] with the bar
                            fill: 1
                        }
                    }
                }
                DelegateChoice {
                    roleValue: "microphone"
                    delegate: EntryWrapper {
                        margin: Tokens.spacing.extraSmall / 2
                        name: "audio" // Mic opens audio popout

                        MaterialIcon {
                            animate: true
                            text: Icons.getMicVolumeIcon(Audio.sourceVolume, Audio.sourceMuted)
                            color: root.colour
                            fontStyle: Tokens.font.icon.builders.medium.scale(Tokens.sizes.bar.innerWidth / 26).build() // [macos] with the bar
                            fill: 1
                        }
                    }
                }
                DelegateChoice {
                    roleValue: "kbLayout"
                    delegate: EntryWrapper {
                        StyledText {
                            animate: true
                            text: Hypr.kbLayout
                            color: root.colour
                            font: Tokens.font.mono.builders.medium.scale(Tokens.sizes.bar.innerWidth / 26).build() // [macos] with the bar
                        }
                    }
                }
                DelegateChoice {
                    roleValue: "network"
                    delegate: EntryWrapper {
                        MaterialIcon {
                            fontStyle: Tokens.font.icon.builders.small.scale(Tokens.sizes.bar.innerWidth / 26).build() // [macos] with the bar
                            animate: true
                            text: Nmcli.activeEthernet ? "cable" : Nmcli.active ? Icons.getNetworkIcon(Nmcli.active.strength ?? 0) : "wifi_off"
                            color: root.colour
                            mode: !Nmcli.activeEthernet && Nmcli.active ? "hierarchical" : "mono" // [macos] unlit arcs dimmed
                            underlay: "wifi"
                        }
                    }
                }
                DelegateChoice {
                    roleValue: "bluetooth"
                    delegate: EntryWrapper {
                        BluetoothStatus {
                            colour: root.colour
                            horizontal: root.horizontal
                        }
                    }
                }
                DelegateChoice {
                    roleValue: "battery"
                    delegate: EntryWrapper {
                        BatteryStatus {
                            colour: root.colour
                        }
                    }
                }
            }
        }
    }

    component EntryWrapper: Item {
        required property var modelData
        required property int index
        property int margin: root.spacing / 2
        readonly property bool present: !root.collapsed(modelData)
        property real topGap: present && index !== root.firstPresent ? margin : 0
        property real bottomGap: present && index !== root.lastPresent ? margin : 0
        default property Item item
        property string name: modelData.id.toLowerCase()

        // the gaps run along the bar: above/below in a column, left/right in a row
        Layout.topMargin: root.horizontal ? 0 : Math.round(topGap)
        Layout.bottomMargin: root.horizontal ? 0 : Math.round(bottomGap)
        Layout.leftMargin: root.horizontal ? Math.round(topGap) : 0
        Layout.rightMargin: root.horizontal ? Math.round(bottomGap) : 0
        Layout.alignment: root.horizontal ? Qt.AlignVCenter : Qt.AlignHCenter

        implicitWidth: item?.implicitWidth ?? 0
        implicitHeight: item?.implicitHeight ?? 0

        children: item

        Behavior on topGap {
            Anim {
                type: Anim.SlowEffects
            }
        }

        Behavior on bottomGap {
            Anim {
                type: Anim.SlowEffects
            }
        }
    }

    HoverWash {} // [macos] the bar's one hover hint
}
