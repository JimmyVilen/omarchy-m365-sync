import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Model.js" as Model

Panel {
  id: root
  moduleName: "jimmy.rclone"
  ipcTarget: "jimmy.rclone"
  manageIpc: false

  // Cursor rows: one per mount, then the re-login row.
  property int cursorIndex: 0
  property bool cursorActive: false

  readonly property color foreground: bar ? bar.foreground : Color.foreground
  readonly property color urgent: bar ? bar.urgent : Color.urgent
  readonly property color dim: Qt.darker(foreground, 1.55)
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family
  readonly property bool problem: rclone.overall === "auth" || rclone.overall === "error"
  readonly property int rowCount: rclone.mounts.length + 1
  readonly property bool loginSelected: cursorIndex === rclone.mounts.length

  function selectedMount() {
    return cursorIndex < rclone.mounts.length ? rclone.mounts[cursorIndex] : null
  }

  function moveCursor(dy) {
    cursorActive = true
    cursorIndex = Math.max(0, Math.min(rowCount - 1, cursorIndex + dy))
  }

  function activateCursor() {
    if (loginSelected) rclone.reauth()
    else rclone.openFolder(selectedMount())
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  onOpenedChanged: if (opened) {
    cursorActive = false
    cursorIndex = 0
    rclone.refresh()
    Qt.callLater(function() { keyCatcher.forceActiveFocus() })
  }

  Service {
    id: rclone
    settings: root.settings
  }

  IpcHandler {
    target: root.ipcTarget
    function open(): void { root.open() }
    function close(): void { root.close() }
    function toggle(): void { root.toggle() }
    function refresh(): string { rclone.refresh(); return "ok" }
    function status(): string { return rclone.overall }
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: Model.stateGlyph(rclone.overall)
    active: root.problem
    dimmed: rclone.overall === "none"
    tooltipText: Model.overallText(rclone)
    onPressed: function(buttonCode) {
      if (buttonCode === Qt.RightButton) rclone.refresh()
      else if (buttonCode === Qt.MiddleButton) rclone.openFolder(null)
      else root.toggle()
    }
  }

  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(380))
    contentHeight: panel.fittedContentHeight(column.implicitHeight, Style.space(560))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onMoveRequested: function(dx, dy) {
        if (!root.cursorActive) { root.cursorActive = true; return }
        root.moveCursor(dy)
      }
      onActivateRequested: if (root.cursorActive) root.activateCursor()
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }
      onTextKey: function(t) {
        var key = String(t).toLowerCase()
        var mount = root.selectedMount()
        if (key === "r") rclone.restart(mount)
        else if (key === "l") rclone.showLog(mount)
        else if (key === "o") rclone.openFolder(mount)
        else if (key === "i") rclone.reauth()
      }

      Flickable {
        id: panelFlick
        anchors.fill: parent
        contentWidth: width
        contentHeight: column.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        flickableDirection: Flickable.VerticalFlick
        interactive: contentHeight > height
        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

        Column {
          id: column
          width: panelFlick.width
          spacing: Style.space(12)

          PanelHero {
            id: hero
            width: parent.width
            title: "Microsoft 365"
            meta: Model.overallText(rclone)
            foreground: root.foreground
            fontFamily: root.fontFamily
            iconComponent: Component {
              Text {
                text: Model.stateGlyph(rclone.overall)
                color: root.problem ? root.urgent : root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.display
              }
            }
          }

          Text {
            textFormat: Text.PlainText
            visible: rclone.actionStatus !== "" || rclone.lastError !== ""
            width: parent.width
            text: rclone.actionStatus !== "" ? rclone.actionStatus : rclone.lastError
            color: rclone.lastError !== "" && rclone.actionStatus === "" ? root.urgent : root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
            wrapMode: Text.WordWrap
          }

          PanelSectionHeader {
            text: "MONTERINGAR"
            foreground: root.foreground
            fontFamily: root.fontFamily
          }

          Text {
            visible: rclone.mounts.length === 0
            width: parent.width
            text: "Inga rclone-mount@-tjänster hittades."
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.body
            horizontalAlignment: Text.AlignHCenter
          }

          Column {
            width: parent.width
            spacing: Style.space(6)

            Repeater {
              model: rclone.mounts
              MountRow {
                required property var modelData
                required property int index
                width: parent.width
                mount: modelData
                rowIndex: index
              }
            }
          }

          Column {
            visible: rclone.transfers.length > 0
            width: parent.width
            spacing: Style.space(6)

            PanelSeparator { foreground: root.foreground }

            PanelSectionHeader {
              text: "ÖVERFÖRINGAR"
              foreground: root.foreground
              fontFamily: root.fontFamily
            }

            Repeater {
              model: rclone.transfers
              TransferRow {
                required property var modelData
                width: parent.width
                transfer: modelData
              }
            }
          }

          PanelSeparator { foreground: root.foreground }

          LoginRow { width: parent.width }
        }
      }
    }
  }

  component MountRow: CursorSurface {
    id: mountRow
    property var mount: null
    property int rowIndex: 0
    readonly property bool bad: mount && (mount.state === "auth" || mount.state === "error" || mount.state === "stopped")

    hasCursor: root.cursorActive && root.cursorIndex === rowIndex
    foreground: root.foreground
    implicitHeight: mountContent.implicitHeight + Style.spacing.rowPaddingX

    MouseArea {
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onEntered: { root.cursorActive = true; root.cursorIndex = mountRow.rowIndex }
      onClicked: rclone.openFolder(mountRow.mount)
    }

    RowLayout {
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      anchors.leftMargin: Style.space(10)
      anchors.rightMargin: Style.space(6)
      spacing: Style.space(8)

      Text {
        textFormat: Text.PlainText
        text: Model.stateGlyph(mountRow.mount ? mountRow.mount.state : "")
        color: mountRow.bad ? root.urgent : root.foreground
        font.family: root.fontFamily
        font.pixelSize: Style.font.icon
        Layout.alignment: Qt.AlignVCenter
      }

      ColumnLayout {
        id: mountContent
        Layout.fillWidth: true
        spacing: Style.space(1)

        Text {
          textFormat: Text.PlainText
          Layout.fillWidth: true
          text: mountRow.mount ? mountRow.mount.name : ""
          color: root.foreground
          font.family: root.fontFamily
          font.pixelSize: Style.font.body
          elide: Text.ElideRight
        }

        Text {
          textFormat: Text.PlainText
          Layout.fillWidth: true
          text: Model.mountMeta(mountRow.mount)
          color: mountRow.bad ? root.urgent : root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          elide: Text.ElideRight
        }
      }

      PanelActionButton {
        iconText: Model.GLYPH_FOLDER
        tooltipText: "Öppna mapp (o)"
        foreground: root.foreground
        fontFamily: root.fontFamily
        onClicked: rclone.openFolder(mountRow.mount)
      }

      PanelActionButton {
        iconText: Model.GLYPH_RESTART
        tooltipText: "Starta om (r)"
        foreground: root.foreground
        fontFamily: root.fontFamily
        onClicked: rclone.restart(mountRow.mount)
      }

      PanelActionButton {
        iconText: Model.GLYPH_LOG
        tooltipText: "Visa logg (l)"
        foreground: root.foreground
        fontFamily: root.fontFamily
        onClicked: rclone.showLog(mountRow.mount)
      }
    }
  }

  component TransferRow: RowLayout {
    property var transfer: null
    spacing: Style.space(8)

    Text {
      textFormat: Text.PlainText
      text: transfer && transfer.direction === "up" ? Model.GLYPH_UP : Model.GLYPH_DOWN
      color: transfer && transfer.direction === "up" ? root.foreground : root.dim
      font.family: root.fontFamily
      font.pixelSize: Style.font.icon
      Layout.leftMargin: Style.space(10)
    }

    Text {
      textFormat: Text.PlainText
      Layout.fillWidth: true
      text: transfer ? transfer.name : ""
      color: root.foreground
      font.family: root.fontFamily
      font.pixelSize: Style.font.bodySmall
      elide: Text.ElideMiddle
    }

    Text {
      textFormat: Text.PlainText
      text: transfer ? transfer.percentage + "%" : ""
      color: root.dim
      font.family: root.fontFamily
      font.pixelSize: Style.font.bodySmall
      Layout.rightMargin: Style.space(10)
    }
  }

  component LoginRow: CursorSurface {
    id: loginRow
    hasCursor: root.cursorActive && root.loginSelected
    foreground: root.foreground
    implicitHeight: loginContent.implicitHeight + Style.spacing.rowPaddingX

    MouseArea {
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onEntered: { root.cursorActive = true; root.cursorIndex = rclone.mounts.length }
      onClicked: rclone.reauth()
    }

    RowLayout {
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      anchors.leftMargin: Style.space(10)
      anchors.rightMargin: Style.space(10)
      spacing: Style.space(8)

      Text {
        textFormat: Text.PlainText
        text: Model.GLYPH_LOGIN
        color: rclone.overall === "auth" ? root.urgent : root.foreground
        font.family: root.fontFamily
        font.pixelSize: Style.font.icon
      }

      ColumnLayout {
        id: loginContent
        Layout.fillWidth: true
        spacing: Style.space(1)

        Text {
          textFormat: Text.PlainText
          Layout.fillWidth: true
          text: "Logga in igen (i)"
          color: root.foreground
          font.family: root.fontFamily
          font.pixelSize: Style.font.body
        }

        Text {
          textFormat: Text.PlainText
          Layout.fillWidth: true
          text: "Ny M365-inloggning för alla monteringar"
          color: root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          elide: Text.ElideRight
        }
      }
    }
  }
}
