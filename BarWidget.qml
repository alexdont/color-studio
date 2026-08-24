import QtQuick
import qs.Commons
import qs.Ui

// Left-click: instant screen pick. Right-click: open the studio overlay.
// All state lives in the service; the corner dot wears the last-picked color.
BarWidget {
  id: root
  moduleName: "io.github.alexdont.color-studio"

  readonly property var svc: bar && bar.shell ? bar.shell.serviceFor(moduleName) : null
  readonly property string lastColor: svc ? svc.lastColor : ""

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: "󰈊"
    horizontalMargin: 7.5
    onPressed: function(b) {
      if (!root.svc) return
      if (b === Qt.RightButton) root.svc.toggleStudio()
      else root.svc.pick()
    }

    Rectangle {
      visible: root.lastColor !== ""
      width: Style.space(7)
      height: Style.space(7)
      radius: width / 2
      color: root.lastColor || "transparent"
      border.width: 1
      border.color: button.foreground
      anchors.right: parent.right
      anchors.bottom: parent.bottom
      anchors.margins: Style.space(2)
    }
  }
}
