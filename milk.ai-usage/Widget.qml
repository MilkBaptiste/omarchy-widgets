pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import qs.Ui
import qs.Commons

BarWidget {
    id: root
    moduleName: "milk.ai-usage"
    Component.onCompleted: console.log("AI usage widget revision 1.2 loaded: explicit used labels and multiline popup")
    property bool fitCompact: false        // set by milk.bar-fit: one line, the tighter limit per service
    implicitWidth: (fitCompact ? compactLine.implicitWidth + 12 : 332) + fitArrow.implicitWidth
    // Collapse arrow: the user's own choice, saved in ~/.cache/milk.bar-fit/milk.ai-usage.json.
    // milk.bar-fit reads fitPinned and also shrinks this widget on its own if the bar gets too full.
    property bool fitPinned: false
    readonly property string fitPath: Quickshell.env("HOME") + "/.cache/milk.bar-fit/milk.ai-usage.json"
    function setFitPinned(value) {
        fitPinned = value
        fitCompact = value
        Quickshell.execDetached(["python3", "-I", "-c",
            "import json,os,sys; p=sys.argv[1]; os.makedirs(os.path.dirname(p),exist_ok=True); open(p,'w').write(json.dumps({'collapsed': sys.argv[2]=='1'}))",
            fitPath, value ? "1" : "0"])
    }
    FileView {
        path: root.fitPath
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: { try { root.fitPinned = !!JSON.parse(text()).collapsed } catch (e) { root.fitPinned = false } }
    }
    function tightest(service) {
        var best = -1;
        ["5h", "week"].forEach(function(key) {
            var w = (service.windows || {})[key];
            if (w && (!w.reset || w.reset > root.now)) best = Math.max(best, Math.round(w.used));
        });
        return best;
    }
    implicitHeight: 26

    property var usage: [{name: "Codex", stale: true}, {name: "Claude", stale: true}]
    property double now: Date.now() / 1000
    readonly property color ink: bar ? bar.foreground : "#e6e6e6"
    readonly property string typeface: bar && bar.fontFamily ? bar.fontFamily : "monospace"

    function alpha(color, opacity) { return Qt.rgba(color.r, color.g, color.b, opacity) }
    function stale(service) { return !!service.stale || now - (service.updated || 0) > 300 }
    function refresh() { if (!reader.running) reader.running = true }
    function tooltip(service) {
        var text = service.name + " · subscription usage";
        ["5h", "week"].forEach(function(key) {
            var window = (service.windows || {})[key];
            var label = key === "5h" ? "5 hours" : "Weekly";
            var expired = window && window.reset && window.reset <= root.now;
            text += "\n" + label + "   " + (window && !expired ? Math.round(window.used) + "% used" : "Awaiting update");
            if (window && window.reset)
                text += "\nResets " + new Date(window.reset * 1000).toLocaleString();
        });
        if (service.updated) text += "\n\nUpdated " + new Date(service.updated * 1000).toLocaleTimeString();
        if (root.stale(service)) text += "\nStale · " + (service.error || "waiting for fresh data");
        return text + "\nRefreshes every 2 minutes";
    }

    Process {
        id: reader
        command: ["python3", Qt.resolvedUrl("usage.py").toString().replace("file://", "")]
        stdout: StdioCollector {
            onStreamFinished: {
                try { root.usage = JSON.parse(text) } catch (e) {}
            }
        }
    }
    Timer {
        interval: 15000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: { root.now = Date.now() / 1000; root.refresh() }
    }

    Text {
        id: compactLine
        visible: root.fitCompact
        anchors.verticalCenter: parent.verticalCenter
        x: 6
        font.family: root.typeface
        font.pixelSize: 10
        font.weight: Font.DemiBold
        color: root.ink
        text: root.usage.map(function(s) { var u = root.tightest(s); return s.name + " " + (u < 0 ? "—" : u + "%") }).join("  ·  ")
        MouseArea { id: compactMouse; anchors.fill: parent; hoverEnabled: true }
        ToolTip.visible: compactMouse.containsMouse
        ToolTip.delay: 350
        ToolTip.text: root.usage.map(function(s) { return root.tooltip(s) }).join("\n\n")
    }
    WidgetButton {
        id: fitArrow
        bar: root.bar
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        fontSize: Style.font.caption
        horizontalMargin: 4
        text: root.fitPinned ? "▸" : "◂"
        tooltipText: root.fitPinned ? "Expand Claude/Codex usage" : root.fitCompact ? "Shrunk automatically: the bar is full.\nClick to keep it collapsed." : "Collapse Claude/Codex usage"
        onPressed: function(b) { root.setFitPinned(!root.fitPinned) }
    }
    Row {
        visible: !root.fitCompact
        anchors.verticalCenter: parent.verticalCenter
        x: 0
        spacing: 6
        Repeater {
            model: root.usage
            delegate: Rectangle {
                id: service
                required property var modelData
                readonly property bool isStale: root.stale(modelData)
                readonly property color accent: modelData.name === "Codex" ? "#83c5be" : "#d9a58a"
                width: 163
                height: 26
                radius: 6
                color: root.alpha(root.ink, mouse.containsMouse ? 0.09 : 0.035)
                border.width: 1
                border.color: root.alpha(root.ink, mouse.containsMouse ? 0.18 : 0.075)
                Behavior on color { ColorAnimation { duration: 140 } }
                Behavior on border.color { ColorAnimation { duration: 140 } }

                Rectangle {
                    x: 5
                    anchors.verticalCenter: parent.verticalCenter
                    width: 2
                    height: 12
                    radius: 1
                    color: service.isStale ? root.alpha(root.ink, 0.3) : service.accent
                    Behavior on color { ColorAnimation { duration: 200 } }
                }
                Text {
                    x: 11
                    width: 40
                    anchors.verticalCenter: parent.verticalCenter
                    text: service.modelData.name
                    font.family: root.typeface
                    font.pixelSize: 10
                    font.weight: Font.DemiBold
                    color: root.ink
                    opacity: service.isStale ? 0.55 : 0.95
                }
                // A hollow status dot marks stale data without shifting the labels.
                Rectangle {
                    x: 47
                    y: 3
                    width: 3
                    height: 3
                    radius: 2
                    visible: service.isStale
                    color: "transparent"
                    border.width: 1
                    border.color: "#d8b270"
                }
                Column {
                    x: 57
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 1
                    Repeater {
                        model: ["5h", "week"]
                        delegate: Row {
                            id: meter
                            required property string modelData
                            readonly property var window: (service.modelData.windows || {})[modelData]
                            readonly property bool valid: !!window && (!window.reset || window.reset > root.now)
                            readonly property real used: valid ? Math.min(100, Math.max(0, window.used)) : 0
                            readonly property color tint: !valid || service.isStale ? root.alpha(root.ink, 0.35)
                                : used >= 90 ? "#e58a8a" : used >= 70 ? "#d8b270" : service.accent
                            height: 10
                            spacing: 4
                            Text {
                                width: 13
                                anchors.verticalCenter: parent.verticalCenter
                                text: meter.modelData === "week" ? "7d" : "5h"
                                font.family: root.typeface
                                font.pixelSize: 9
                                color: root.alpha(root.ink, 0.55)
                            }
                            Rectangle {
                                width: 24
                                height: 3
                                radius: 1.5
                                anchors.verticalCenter: parent.verticalCenter
                                color: root.alpha(root.ink, 0.12)
                                Rectangle {
                                    width: parent.width * meter.used / 100
                                    height: parent.height
                                    radius: parent.radius
                                    color: meter.tint
                                    Behavior on width { NumberAnimation { duration: 350; easing.type: Easing.OutCubic } }
                                    Behavior on color { ColorAnimation { duration: 200 } }
                                }
                            }
                            Text {
                                width: 52
                                anchors.verticalCenter: parent.verticalCenter
                                horizontalAlignment: Text.AlignRight
                                text: meter.valid ? Math.round(meter.used) + "% used" : "—"
                                font.family: root.typeface
                                font.pixelSize: 9
                                color: meter.valid && !service.isStale ? root.ink : root.alpha(root.ink, 0.4)
                            }
                        }
                    }
                }
                // Own the popup geometry and text contrast for multiline details.
                Timer {
                    id: hoverDelay
                    interval: 350
                    running: mouse.containsMouse
                }
                PopupWindow {
                    id: details
                    visible: mouse.containsMouse && !hoverDelay.running && !!service.QsWindow.window
                    color: "transparent"
                    implicitWidth: 330
                    implicitHeight: detailsText.implicitHeight + 28
                    anchor {
                        id: detailsAnchor
                        window: service.QsWindow.window
                        adjustment: PopupAdjustment.Slide
                        edges: Edges.Top | Edges.Left
                        gravity: Edges.Bottom | Edges.Right
                        rect.width: 1
                        rect.height: 1
                        onAnchoring: {
                            var host = service.QsWindow.window;
                            if (!host) return;
                            var x = service.width / 2 - details.implicitWidth / 2;
                            var y = service.height + 6;
                            var position = root.bar ? root.bar.position : "top";
                            if (position === "bottom") y = -details.implicitHeight - 6;
                            else if (position === "left") { x = service.width + 6; y = 0; }
                            else if (position === "right") { x = -details.implicitWidth - 6; y = 0; }
                            var point = host.contentItem.mapFromItem(service, x, y);
                            detailsAnchor.rect.x = Math.round(point.x);
                            detailsAnchor.rect.y = Math.round(point.y);
                        }
                    }
                    Rectangle {
                        anchors.fill: parent
                        color: "#20252d"
                        border.color: service.accent
                        border.width: 1
                        radius: 8
                        Text {
                            id: detailsText
                            x: 14
                            y: 14
                            width: 302
                            text: root.tooltip(service.modelData)
                            textFormat: Text.PlainText
                            wrapMode: Text.Wrap
                            color: "#f0f3f6"
                            font.family: root.typeface
                            font.pixelSize: 12
                            lineHeight: 1.2
                        }
                    }
                }
                MouseArea {
                    id: mouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.refresh()
                }
            }
        }
    }
}
