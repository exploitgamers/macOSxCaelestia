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
    // [macos] trims the box to this glyph's ink (no side bearings), for an icon at a pill's edge or beside a
    // label: Material's ~2 px bearings made the padding and the icon-to-label gap uneven. Name the widest
    // glyph an icon switches between so the pill keeps its width.
    property string trimTo

    function build(f: real): font {
        return Tokens.font.icon.size(fontStyle.pointSize).weight(weight).vaxes(fontStyle.variableAxes).vaxis("opsz", Math.max(20, Math.min(48, fontStyle.pointSize * 4 / 3))).fill(f.toFixed(1)).grade(grade).build();
    }

    font: build(fill)
    leftPadding: trimTo ? -ink.tightBoundingRect.x : 0
    rightPadding: trimTo ? ink.tightBoundingRect.right - ink.advanceWidth : 0
    // [macos] Text's box is ceil(ascent + descent) with the line at its top, so every glyph sat ~0.3 px above
    // the box centre (a full device px in the bar once the baseline snapped); put the line box in the middle
    transform: Translate {
        y: root.text ? (root.contentHeight - lineMetrics.height) / 2 : 0
    }

    FontMetrics {
        id: lineMetrics
        font: root.font
    }

    TextMetrics {
        id: ink
        font: root.font
        text: root.trimTo
    }

    Loader {
        z: -1
        anchors.fill: parent
        active: root.mode === "hierarchical"

        sourceComponent: Text {
            text: root.underlay
            font: root.build(1)
            color: Qt.alpha(root.color, 0.3)
            renderType: root.renderType
            leftPadding: root.leftPadding
            rightPadding: root.rightPadding
            horizontalAlignment: root.horizontalAlignment
            verticalAlignment: root.verticalAlignment
        }
    }
}
