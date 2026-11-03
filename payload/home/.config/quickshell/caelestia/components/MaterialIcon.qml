import QtQuick
import Caelestia.Config
import qs.services

StyledText {
    id: root

    property real fill
    property int grade: Colours.light ? 0 : -25
    property font fontStyle: Tokens.font.icon.small
    // [macos] SF Symbols look: Medium weight like SF's menu-bar/Control Center glyphs (Material's 400 reads
    // thin beside Inter), and the optical size set for the drawn size (Material Symbols' opsz runs 20–48)
    property int weight: fontStyle.weight > Font.Normal ? fontStyle.weight : Font.Medium
    // [macos] SF rendering mode: "mono", or "hierarchical" = `underlay` filled at low opacity under the
    // glyph (e.g. the full wifi fan dimmed under a 1-bar one, like macOS's signal symbols)
    property string mode: "mono"
    property string underlay: text

    function build(f: real): font {
        return Tokens.font.icon.size(fontStyle.pointSize).weight(weight).vaxes(fontStyle.variableAxes).vaxis("opsz", Math.max(20, Math.min(48, fontStyle.pointSize * 4 / 3))).fill(f.toFixed(1)).grade(grade).build();
    }

    font: build(fill)

    Loader {
        z: -1
        anchors.fill: parent
        active: root.mode === "hierarchical"

        sourceComponent: Text {
            text: root.underlay
            font: root.build(1)
            color: Qt.alpha(root.color, 0.3)
            renderType: root.renderType
            horizontalAlignment: root.horizontalAlignment
            verticalAlignment: root.verticalAlignment
        }
    }
}
