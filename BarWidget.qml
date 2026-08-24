import QtQuick
import qs.Commons
import qs.Ui

// Left-click: instant screen pick. Right-click: open the studio overlay.
// All state lives in the service; the corner dot wears the last-picked color.
BarWidget {
  id: root
  moduleName: "io.github.alexdont.color-studio"

  // Resolved lazily and re-tried: at shell startup the widget can be built
  // before the service registers, and a one-shot binding would then hold
  // null forever — leaving left-click dead until something reloaded us.
  property var svc: null
  readonly property string lastColor: svc ? svc.lastColor : ""

  function resolveSvc() {
    if (!svc && bar && bar.shell) svc = bar.shell.serviceFor(moduleName)
    return svc
  }

  onBarChanged: resolveSvc()
  Component.onCompleted: resolveSvc()

  Timer {
    interval: 400
    repeat: true
    running: !root.svc
    onTriggered: root.resolveSvc()
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: "󰈊"
    horizontalMargin: 7.5
    onPressed: function(b) {
      var s = root.resolveSvc()
      if (!s) return
      if (b === Qt.RightButton) s.toggleStudio()
      else s.pick()
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
