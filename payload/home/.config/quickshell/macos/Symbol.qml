import QtQuick

// SF-Symbols-style glyph (Apple HIG "SF Symbols"): Material Symbols Rounded, its weight matched to the
// text beside it, drawn in one of SF's rendering modes. Use it for every glyph instead of a bare Text.
//   mono          one colour (default)
//   hierarchical  the filled shape at low opacity under the outline: SF's layered depth
//   palette       the filled shape in `secondary` under the outline in `color`
//   multicolor    filled, in the symbol's own Apple colour (Theme.symbolTints), else `color`
Item {
    id: s

    property string name
    property real size: 16
    property color color: Theme.fg
    property color secondary: Theme.alpha(color, 0.35)
    property string mode: "mono"
    property bool fill: false
    property int weight: 500 // 400 next to body text, 600 next to bold labels (SF matches the text weight)

    readonly property string tint: mode === "multicolor" ? Theme.symbolTint(name) : ""
    readonly property color main: tint !== "" ? tint : color
    readonly property bool layered: mode === "hierarchical" || mode === "palette"

    implicitWidth: size
    implicitHeight: size

    component Glyph: Text {
        anchors.centerIn: parent
        text: s.name
        font.family: "Material Symbols Rounded"
        font.pixelSize: s.size
        renderType: Text.QtRendering
    }

    Glyph {
        visible: s.layered
        color: s.mode === "palette" ? s.secondary : Theme.alpha(s.main, 0.32)
        font.variableAxes: ({ "FILL": 1, "wght": s.weight, "opsz": Math.max(20, Math.min(48, s.size)) })
    }

    Glyph {
        color: s.main
        font.variableAxes: ({ "FILL": (s.fill || s.mode === "multicolor") ? 1 : 0, "wght": s.weight, "opsz": Math.max(20, Math.min(48, s.size)) })
    }
}
