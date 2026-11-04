pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Caelestia.Config
import Caelestia.I18n
import qs.components
import qs.services

StyledRect {
    id: root

    required property bool horizontal
    readonly property color colour: pillInk.c(Colours.palette.m3tertiary) // [macos] adaptive (BarInk)

    BarInk { id: pillInk; pill: root }
    readonly property int padding: Config.bar.clock.background ? Tokens.padding.medium : Tokens.padding.extraSmall
    readonly property var font: Tokens.font.body.builders.small.scale(0.95 * Tokens.sizes.bar.innerWidth / 26) // [macos] smaller bar text

    function fontFor(text: string, metricWidth: int): font {
        // We don't count seconds for the max width because it changes too often
        const scale = text === "11" ? 1.15 : Math.min(1.05, Math.max(hourMetrics.width, minMetrics.width) / metricWidth);
        return root.font.width(scale * 100).letterSpacing(scale).build();
    }

    implicitWidth: horizontal ? Math.ceil(layout.implicitWidth + root.padding * 2) : Tokens.sizes.bar.innerWidth // [macos] whole px (even gaps)
    implicitHeight: horizontal ? Tokens.sizes.bar.innerWidth : layout.implicitHeight + root.padding * 2

    color: Qt.alpha(Colours.tPalette.m3surfaceContainer, Config.bar.clock.background ? Colours.tPalette.m3surfaceContainer.a : 0)
    radius: Tokens.rounding.full

    GridLayout {
        id: layout

        anchors.centerIn: parent
        anchors.alignWhenCentered: false // [macos] the pill is whole px now; a rounded offset made the padding uneven
        columns: root.horizontal ? -1 : 1
        rowSpacing: Tokens.spacing.extraSmall
        columnSpacing: Tokens.spacing.extraSmall

        Loader {
            Layout.alignment: root.horizontal ? Qt.AlignVCenter : Qt.AlignHCenter
            asynchronous: true
            active: Config.bar.clock.showIcon
            visible: active

            sourceComponent: MaterialIcon {
                fontStyle: Tokens.font.icon.builders.small.scale(Tokens.sizes.bar.innerWidth / 26).build() // [macos] with the bar
                text: "calendar_month"
                trimTo: text // [macos] even pill padding
                color: root.colour
            }
        }

        Loader {
            Layout.alignment: root.horizontal ? Qt.AlignVCenter : Qt.AlignHCenter
            asynchronous: true
            active: Config.bar.clock.showDate
            visible: active

            sourceComponent: GridLayout {
                columns: root.horizontal ? -1 : 1
                rowSpacing: layout.rowSpacing - 4
                columnSpacing: layout.columnSpacing - 4

                StyledText {
                    Layout.alignment: root.horizontal ? Qt.AlignVCenter : Qt.AlignHCenter
                    text: Time.format("ddd")
                    font: Tokens.font.body.builders.small.scale(0.9 * Tokens.sizes.bar.innerWidth / 26).build()
                    color: root.colour
                }

                StyledText {
                    Layout.alignment: root.horizontal ? Qt.AlignVCenter : Qt.AlignHCenter
                    text: Time.format("d")
                    font: root.font.scale(1.1).build()
                    color: root.colour
                }

                StyledRect {
                    Layout.fillWidth: !root.horizontal
                    Layout.fillHeight: root.horizontal
                    Layout.leftMargin: root.horizontal ? 4 : -Tokens.padding.extraSmall
                    Layout.rightMargin: root.horizontal ? Tokens.padding.extraSmall / 2 : -Tokens.padding.extraSmall
                    Layout.topMargin: root.horizontal ? -Tokens.padding.extraSmall : 4
                    Layout.bottomMargin: root.horizontal ? -Tokens.padding.extraSmall : Tokens.padding.extraSmall / 2
                    implicitWidth: root.horizontal ? 1 : 0
                    implicitHeight: root.horizontal ? 0 : 1
                    color: pillInk.c(Colours.palette.m3outlineVariant)
                }
            }
        }

        StyledText {
            Layout.alignment: root.horizontal ? Qt.AlignVCenter : Qt.AlignHCenter
            Layout.bottomMargin: root.horizontal ? 1 : 0 // [macos] centred to the pixel: it sat 1 px below the other pills' text
            // [macos] horizontal bar: one "4:09" like macOS, not stacked digits side by side
            // ("04 09") — no leading zero on a 12-hour clock
            text: root.horizontal ? (Units.twelveHourClock ? Time.hourStr.replace(/^0(?=\d)/, "") : Time.hourStr) + ":" + Time.minuteStr : Time.hourStr
            font: root.horizontal ? root.font.build() : root.fontFor(text, hourMetrics.width)
            color: root.colour

            TextMetrics {
                id: hourMetrics

                font: root.font.build()
                text: Time.hourStr
            }
        }

        StyledText {
            visible: !root.horizontal // [macos] in the hour's text when horizontal
            Layout.topMargin: root.horizontal ? 0 : -parent.rowSpacing - 4
            Layout.alignment: root.horizontal ? Qt.AlignVCenter : Qt.AlignHCenter
            text: Time.minuteStr
            font: root.fontFor(text, minMetrics.width)
            color: root.colour

            TextMetrics {
                id: minMetrics

                font: root.font.build()
                text: Time.minuteStr
            }
        }

        Loader {
            Layout.topMargin: root.horizontal ? 0 : -parent.rowSpacing - 4
            Layout.alignment: root.horizontal ? Qt.AlignVCenter : Qt.AlignHCenter
            asynchronous: true
            active: Config.bar.clock.showSeconds
            visible: active

            sourceComponent: StyledText {
                text: Time.format("ss")
                font: root.fontFor(text, secMetrics.width)
                color: root.colour

                TextMetrics {
                    id: secMetrics

                    font: root.font.build()
                    text: Time.format("ss")
                }
            }
        }

        Loader {
            // [macos] horizontal: in line with the time. (parent.spacing doesn't exist on
            // the GridLayout, so the margin was NaN: the label vanished but kept its width)
            Layout.topMargin: root.horizontal ? 0 : -parent.rowSpacing - 4
            Layout.leftMargin: root.horizontal ? 2 : 0
            Layout.bottomMargin: root.horizontal ? 1 : 0 // [macos] same line as the time
            Layout.alignment: root.horizontal ? Qt.AlignVCenter : Qt.AlignHCenter
            asynchronous: true
            active: Units.twelveHourClock
            visible: active

            sourceComponent: StyledText {
                text: Time.amPmStr.toLowerCase()
                font: Tokens.font.body.builders.small.scale(0.9 * Tokens.sizes.bar.innerWidth / 26).build()
                color: root.colour
            }
        }
    }

    HoverWash {} // [macos] the bar's one hover hint
}
