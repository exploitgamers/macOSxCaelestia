import QtQuick

// Weather widget. Small: now. Medium: + next hours. Large: + 5-day forecast.
// Location: the widget's own (Edit "Weather"…), else macos.json widgets.weatherLocation
// (empty = from your IP address). Unit: the widget's own, else widgets.temperatureUnit.
Item {
    id: root

    property string size: "small"
    property string widgetId: ""
    property var options: ({})

    readonly property var w: place.src

    function t(v: real): string {
        return place.t(v);
    }

    WeatherPlace {
        id: place

        location: root.options.location ?? ""
        unit: root.options.unit ?? "auto"
    }

    // SF Symbols' multicolor weather glyphs: yellow sun, cyan rain, grey cloud
    component Icon: Symbol {
        mode: "multicolor"
        fill: true
    }

    Text {
        visible: !root.w.loaded
        anchors.centerIn: parent
        text: root.w.failed ? "Weather unavailable" : "Loading weather…"
        color: Theme.fgDim
        font.family: Theme.font
        font.pixelSize: 13
    }

    Item {
        id: now

        visible: root.w.loaded
        x: 16
        y: 14
        width: root.width - 32
        height: 140

        Text {
            id: placeName

            width: parent.width - 30
            text: root.w.city ?? ""
            rightPadding: arrow.visible ? 16 : 0
            elide: Text.ElideRight
            color: Theme.fg
            font.family: Theme.font
            font.pixelSize: 15
            font.weight: Font.DemiBold
        }

        // your location (from the IP address): Apple's location arrow
        Symbol {
            id: arrow

            visible: !place.custom && !Config.weatherLocation
            x: Math.min(placeName.implicitWidth, placeName.width) - 13
            anchors.verticalCenter: placeName.verticalCenter
            name: "near_me"
            fill: true
            size: 12
            weight: 600
        }

        Text {
            anchors.top: placeName.bottom
            anchors.topMargin: -6
            text: root.t(root.w.temp)
            color: Theme.fg
            font.family: Theme.displayFont
            font.pixelSize: 46
            font.weight: Font.Light
        }

        Icon {
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.topMargin: -2
            name: root.w.icon ?? ""
            size: root.size === "small" ? 26 : 34
        }

        Column {
            anchors.bottom: parent.bottom
            anchors.bottomMargin: root.size === "small" ? 0 : 2
            visible: root.size === "small"

            Text {
                text: root.w.condition ?? ""
                color: Theme.fg
                font.family: Theme.font
                font.pixelSize: 13
                font.weight: Font.Medium
            }

            Text {
                text: `H:${root.t(root.w.high)}  L:${root.t(root.w.low)}`
                color: Theme.fgDim
                font.family: Theme.font
                font.pixelSize: 12
            }
        }

        // medium / large: condition beside the icon instead
        Column {
            visible: root.size !== "small"
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.topMargin: 40

            Text {
                anchors.right: parent.right
                text: root.w.condition ?? ""
                color: Theme.fg
                font.family: Theme.font
                font.pixelSize: 13
                font.weight: Font.Medium
            }

            Text {
                anchors.right: parent.right
                text: `H:${root.t(root.w.high)}  L:${root.t(root.w.low)}`
                color: Theme.fgDim
                font.family: Theme.font
                font.pixelSize: 12
            }
        }
    }

    // next hours
    Row {
        visible: root.w.loaded && root.size !== "small"
        x: 16
        y: 96
        width: root.width - 32

        Repeater {
            model: root.w.hourly ?? []

            Column {
                required property var modelData

                width: (root.width - 32) / 6
                spacing: 2

                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: parent.modelData.hour
                    color: Theme.fgDim
                    font.family: Theme.font
                    font.pixelSize: 11
                    font.weight: Font.Medium
                }

                Icon {
                    anchors.horizontalCenter: parent.horizontalCenter
                    name: WeatherData.iconFor(parent.modelData.code, parent.modelData.isDay)
                    size: 19
                }

                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: root.t(parent.modelData.temp)
                    color: Theme.fg
                    font.family: Theme.font
                    font.pixelSize: 12
                    font.weight: Font.Medium
                }
            }
        }
    }

    // 5-day forecast
    Column {
        visible: root.w.loaded && root.size === "large"
        x: 16
        y: 178
        width: root.width - 32

        Rectangle {
            width: parent.width
            height: 1
            color: Theme.alpha(Theme.fg, 0.12)
        }

        Repeater {
            model: (root.w.daily ?? []).slice(1, 6)

            Item {
                id: day

                required property var modelData

                // range bar: this day's low..high within the week's span
                readonly property real minT: Math.min(...root.w.daily.map(d => d.low))
                readonly property real maxT: Math.max(...root.w.daily.map(d => d.high))

                width: parent.width
                height: 34

                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: day.modelData.day
                    color: Theme.fg
                    font.family: Theme.font
                    font.pixelSize: 13
                    font.weight: Font.Medium
                }

                Icon {
                    x: 58
                    anchors.verticalCenter: parent.verticalCenter
                    name: WeatherData.iconFor(day.modelData.code, true)
                    size: 19
                }

                Text {
                    x: 100
                    width: 34
                    anchors.verticalCenter: parent.verticalCenter
                    horizontalAlignment: Text.AlignRight
                    text: root.t(day.modelData.low)
                    color: Theme.fgDim
                    font.family: Theme.font
                    font.pixelSize: 13
                }

                Rectangle {
                    id: track

                    x: 144
                    width: parent.width - 144 - 46
                    height: 4
                    radius: 2
                    anchors.verticalCenter: parent.verticalCenter
                    color: Theme.alpha(Theme.fg, 0.12)

                    Rectangle {
                        readonly property real span: Math.max(1, day.maxT - day.minT)

                        x: track.width * (day.modelData.low - day.minT) / span
                        width: Math.max(4, track.width * (day.modelData.high - day.modelData.low) / span)
                        height: 4
                        radius: 2
                        // Apple's temperature bar: cool to warm
                        gradient: Gradient {
                            orientation: Gradient.Horizontal

                            GradientStop { position: 0; color: Theme.sys.teal }
                            GradientStop { position: 1; color: Theme.sys.orange }
                        }
                    }
                }

                Text {
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    text: root.t(day.modelData.high)
                    color: Theme.fg
                    font.family: Theme.font
                    font.pixelSize: 13
                    font.weight: Font.Medium
                }
            }
        }
    }
}
