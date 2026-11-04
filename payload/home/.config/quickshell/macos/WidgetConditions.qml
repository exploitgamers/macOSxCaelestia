import QtQuick

// Weather conditions (replaces the dashboard's Weather tab details):
// feels like, humidity, wind, UV, sunrise and sunset. Click opens the forecast.
Item {
    id: root

    property string size: "small"
    property string widgetId: ""
    property var options: ({}) // Edit "Conditions"…: location, unit (as Weather)

    readonly property var w: place.src

    WeatherPlace {
        id: place

        location: root.options.location ?? ""
        unit: root.options.unit ?? "auto"
    }

    readonly property var tiles: [
        { icon: "thermostat", label: "Feels Like", value: place.t(w.feelsLike ?? 0) },
        { icon: "humidity_percentage", label: "Humidity", value: Math.round(w.humidity ?? 0) + "%" },
        { icon: "air", label: "Wind", value: Math.round(w.wind ?? 0) + " km/h" },
        { icon: "sunny", label: "UV Index", value: Math.round(w.uv ?? 0) },
        { icon: "wb_twilight", label: "Sunrise", value: w.sunrise || "--:--" },
        { icon: "nights_stay", label: "Sunset", value: w.sunset || "--:--" }
    ]

    Text {
        visible: !root.w.loaded
        anchors.centerIn: parent
        text: root.w.failed ? "Weather unavailable" : "Loading…"
        color: Theme.fgDim
        font.family: Theme.font
        font.pixelSize: 13
    }

    Grid {
        visible: root.w.loaded
        anchors.centerIn: parent
        anchors.verticalCenterOffset: root.size === "small" ? 0 : 2 // optical: the values' descent left the medium inks 2 px high
        columns: root.size === "small" ? 2 : 3
        rowSpacing: root.size === "small" ? 6 : 14
        columnSpacing: root.size === "small" ? 10 : 18

        Repeater {
            model: root.size === "small" ? root.tiles.slice(0, 4) : root.tiles

            Column {
                required property var modelData

                width: root.size === "small" ? 64 : 92
                spacing: 1

                // medium: centred in the cell (left-aligned, the grid's ink sat 14 px off centre); small cells are full already
                Row {
                    anchors.horizontalCenter: root.size === "small" ? undefined : parent.horizontalCenter
                    spacing: 3

                    // multicolor where Apple tints it (cyan drop, yellow sun), else the label's grey
                    Symbol {
                        anchors.verticalCenter: parent.verticalCenter
                        name: parent.parent.modelData.icon
                        mode: "multicolor"
                        fill: true
                        size: 13
                        weight: 600 // beside the semibold label
                        color: Theme.fgDim
                    }

                    Text {
                        text: parent.parent.modelData.label.toUpperCase()
                        color: Theme.fgDim
                        font.family: Theme.font
                        font.pixelSize: 9
                        font.weight: Font.DemiBold
                        font.letterSpacing: 0.4
                    }
                }

                Text {
                    anchors.horizontalCenter: root.size === "small" ? undefined : parent.horizontalCenter
                    text: parent.modelData.value
                    color: Theme.fg
                    font.family: Theme.font
                    font.pixelSize: root.size === "small" ? 17 : 20
                    font.weight: Font.Medium
                }
            }
        }
    }
}
