import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

// Conjugation popup. conjugue.py does the work and returns JSON; this file
// only lays it out, one mode per tab, tenses in two columns (simple tenses
// on the left, their compound tense on the right), like a Bescherelle page.
Panel {
  id: root
  moduleName: "io.github.ldockwiller.becherel-fr"
  ipcTarget: "becherel-fr"
  manageIpc: false

  property var anchorItem: null
  property var hostWidget: null
  readonly property var barIdentity: hostWidget || root
  readonly property color contentForeground: bar ? bar.foreground : Color.foreground
  readonly property string contentFontFamily: bar ? bar.fontFamily : Style.font.family
  readonly property int panelWidth: Style.space(600)
  // KeyboardPanel's own screen-height cap isn't known before the first show,
  // so cap from the screen ourselves: room below the bar, minus margins.
  readonly property real screenHeight: Quickshell.screens.length > 0 ? Quickshell.screens[0].height : 0
  readonly property int panelMaxHeight: root.screenHeight > 0
    ? Math.min(Style.space(760), root.screenHeight - (root.bar && root.bar.barSize ? root.bar.barSize : Style.space(30)) - Style.gapsOut * 3)
    : Style.space(760)
  readonly property string helperPath: Qt.resolvedUrl("conjugue.py").toString().replace(/^file:\/\//, "")

  property string query: ""
  property string status: "idle"
  property var result: ({})
  property string modeName: "Indicatif"
  property string copiedText: ""

  // "Infinitif", "Participe" and "Gérondif" share one "Autres" tab.
  readonly property var otherModes: ["Infinitif", "Participe", "Gérondif"]
  readonly property var tabs: {
    var out = []
    var modes = root.result.modes || []
    for (var i = 0; i < modes.length; i++) {
      var name = root.otherModes.indexOf(modes[i].name) >= 0 ? "Autres" : modes[i].name
      if (out.indexOf(name) < 0) out.push(name)
    }
    return out
  }
  readonly property var visibleTenses: {
    var out = []
    var modes = root.result.modes || []
    for (var i = 0; i < modes.length; i++) {
      var isOther = root.otherModes.indexOf(modes[i].name) >= 0
      if (root.modeName === "Autres" ? !isOther : modes[i].name !== root.modeName) continue
      for (var j = 0; j < modes[i].tenses.length; j++) {
        var t = modes[i].tenses[j]
        out.push({ name: isOther ? modes[i].name + " " + t.name.toLowerCase() : t.name, lines: t.lines })
      }
    }
    return out
  }

  function open() {
    root.controller.show()
    refreshFocus()
  }

  function close() {
    if (lookupProc.running) lookupProc.running = false
    root.controller.hide()
  }

  function toggle() {
    if (root.opened) close()
    else open()
  }

  function switchPanel(direction) {
    if (root.bar && typeof root.bar.switchPanelFrom === "function")
      return root.bar.switchPanelFrom(root.barIdentity, direction)
    return false
  }

  function refreshFocus() {
    if (!root.opened) return
    Qt.callLater(function() {
      searchField.forceActiveFocus()
      if (searchField.text.length > 0) searchField.selectAll()
    })
  }

  function conjugate(verb) {
    if (!root.opened) open()
    searchField.text = String(verb || "").trim()
    runLookup(false)
  }

  function runLookup(pronominal) {
    var q = String(searchField.text || "").trim()
    if (q === "") return
    if (lookupProc.running) lookupProc.running = false
    root.query = q
    root.status = "loading"
    root.copiedText = ""
    lookupProc.command = ["python3", root.helperPath, q].concat(pronominal ? ["--pronominal"] : [])
    lookupProc.running = true
  }

  function togglePronominal() {
    if (!root.result.ok) return
    searchField.text = root.result.verb
    runLookup(!root.result.pronominal)
  }

  function clearResults() {
    if (lookupProc.running) lookupProc.running = false
    root.query = ""
    root.status = "idle"
    root.result = ({})
    root.copiedText = ""
  }

  // "aim[e]" -> "aim<b>e</b>" in the accent color.
  function styled(line) {
    var safe = String(line).replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;")
    return safe.replace(/\[([^\]]*)\]/g, "<font color=\"" + Color.accent + "\"><b>$1</b></font>")
  }

  function plain(line) {
    return String(line).replace(/[\[\]]/g, "")
  }

  function copyResults() {
    if (!root.result.ok) return
    var out = [root.result.title + " (" + root.result.group + ", auxiliaire " + root.result.auxiliary + ")"]
    var modes = root.result.modes
    for (var i = 0; i < modes.length; i++) {
      out.push("", modes[i].name.toUpperCase())
      for (var j = 0; j < modes[i].tenses.length; j++) {
        out.push("  " + modes[i].tenses[j].name)
        for (var k = 0; k < modes[i].tenses[j].lines.length; k++)
          out.push("    " + root.plain(modes[i].tenses[j].lines[k]))
      }
    }
    Quickshell.execDetached(["wl-copy", out.join("\n")])
    root.copiedText = "Copié"
    copiedTimer.restart()
  }

  Process {
    id: lookupProc
    stdout: StdioCollector { id: lookupOutput; waitForEnd: true }
    onExited: function(exitCode) {
      if (root.status !== "loading") return
      var parsed = null
      try { parsed = JSON.parse(lookupOutput.text) } catch (e) { parsed = null }
      if (exitCode !== 0 || !parsed) {
        root.result = ({ ok: false, message: "Le conjugueur a échoué.", suggestions: [] })
        root.status = "error"
        return
      }
      root.result = parsed
      root.status = parsed.ok ? "ok" : "error"
      if (parsed.ok && root.tabs.indexOf(root.modeName) < 0) root.modeName = root.tabs[0] || "Indicatif"
      if (parsed.ok) resultsFlick.contentY = 0
    }
  }

  Timer {
    id: copiedTimer
    interval: 1500
    onTriggered: root.copiedText = ""
  }

  onOpenedChanged: if (opened) refreshFocus()

  component Caption: Text {
    color: Qt.darker(root.contentForeground, 1.35)
    font.family: root.contentFontFamily
    font.pixelSize: Style.font.caption
    font.bold: true
    font.letterSpacing: 1.0
  }

  KeyboardPanel {
    id: panel
    anchorItem: root.anchorItem
    owner: root.barIdentity
    bar: root.bar
    open: root.opened
    centerOnBar: true
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(root.panelWidth)
    contentHeight: panel.fittedContentHeight(panelColumn.implicitHeight, root.panelMaxHeight)

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      blocked: searchField.activeFocus
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }

      Column {
        id: panelColumn
        width: parent.width
        spacing: Style.space(14)

        Item {
          width: parent.width
          implicitHeight: Math.max(heroIcon.implicitHeight, heroLabels.implicitHeight)

          Text {
            id: heroIcon
            text: String.fromCodePoint(0xF05DA)
            color: root.contentForeground
            font.family: root.contentFontFamily
            font.pixelSize: Style.font.display
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
          }

          Column {
            id: heroLabels
            anchors.left: heroIcon.right
            anchors.leftMargin: Style.space(14)
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            spacing: Style.space(2)

            Text {
              width: parent.width
              text: "Conjugaison"
              color: root.contentForeground
              font.family: root.contentFontFamily
              font.pixelSize: Style.font.title
              font.bold: true
            }

            Text {
              width: parent.width
              text: root.status === "loading" ? "RECHERCHE…" : "TOUS LES MODES · TOUS LES TEMPS"
              color: Qt.darker(root.contentForeground, 1.4)
              font.family: root.contentFontFamily
              font.pixelSize: Style.font.caption
              font.bold: true
              font.letterSpacing: 1.2
            }
          }
        }

        PanelSeparator { foreground: root.contentForeground }

        Item {
          width: parent.width
          implicitHeight: Style.space(46)

          Rectangle {
            anchors.fill: parent
            radius: Style.cornerRadius
            color: "transparent"
            border.width: Style.spacing.hairline
            border.color: searchField.activeFocus ? Color.accent : Qt.darker(root.contentForeground, 1.7)

            Row {
              anchors.fill: parent
              anchors.leftMargin: Style.space(12)
              anchors.rightMargin: Style.space(6)
              spacing: Style.space(8)

              Text {
                text: "󰍉"
                color: Qt.darker(root.contentForeground, 1.3)
                font.family: root.contentFontFamily
                font.pixelSize: Style.font.title
                anchors.verticalCenter: parent.verticalCenter
                width: Style.space(22)
                horizontalAlignment: Text.AlignHCenter
              }

              TextField {
                id: searchField
                width: parent.width - actions.width - Style.space(30)
                height: parent.height
                color: root.contentForeground
                font.family: root.contentFontFamily
                font.pixelSize: Style.font.body
                placeholderText: "Un verbe : aller, se lever, fîmes…"
                placeholderTextColor: Qt.darker(root.contentForeground, 2.0)
                background: null
                selectByMouse: true
                clip: true
                onAccepted: root.runLookup(false)
                onTextChanged: if (String(text || "").trim() === "") root.clearResults()
                Keys.onEscapePressed: function(event) {
                  if (searchField.text !== "") searchField.text = ""
                  else root.close()
                  event.accepted = true
                }
              }

              Row {
                id: actions
                anchors.verticalCenter: parent.verticalCenter
                spacing: Style.space(4)

                Button {
                  visible: searchField.text !== ""
                  text: "✕"
                  foreground: root.contentForeground
                  onClicked: {
                    searchField.text = ""
                    root.refreshFocus()
                  }
                }

                Button {
                  text: "→"
                  foreground: root.contentForeground
                  enabled: String(searchField.text || "").trim() !== "" && root.status !== "loading"
                  onClicked: root.runLookup(false)
                }
              }
            }
          }
        }

        Column {
          width: parent.width
          visible: root.status === "idle"
          spacing: Style.space(6)

          Text {
            width: parent.width
            text: "Tapez un verbe à l'infinitif (« aller », « se souvenir ») ou une forme conjuguée (« fîmes », « vais ») puis Entrée."
            color: Qt.darker(root.contentForeground, 1.3)
            font.family: root.contentFontFamily
            font.pixelSize: Style.font.body
            wrapMode: Text.WordWrap
          }

          Text {
            width: parent.width
            text: "7 000 verbes, hors ligne — données Verbiste (Pierre Sarrazin)."
            color: Qt.darker(root.contentForeground, 1.7)
            font.family: root.contentFontFamily
            font.pixelSize: Style.font.caption
            wrapMode: Text.WordWrap
          }
        }

        Column {
          width: parent.width
          visible: root.status === "error"
          spacing: Style.space(8)

          Text {
            width: parent.width
            text: root.result.message || ""
            color: root.contentForeground
            font.family: root.contentFontFamily
            font.pixelSize: Style.font.body
            font.bold: true
            wrapMode: Text.WordWrap
          }

          Caption {
            visible: (root.result.suggestions || []).length > 0
            text: root.result.error === "ambiguous" ? "VOULIEZ-VOUS CONJUGUER" : "VOULIEZ-VOUS DIRE"
          }

          Flow {
            width: parent.width
            spacing: Style.space(6)
            Repeater {
              model: root.result.suggestions || []
              Button {
                required property string modelData
                text: modelData
                bordered: true
                foreground: root.contentForeground
                onClicked: root.conjugate(modelData)
              }
            }
          }
        }

        Column {
          id: resultsColumn
          width: parent.width
          visible: root.status === "ok"
          spacing: Style.space(12)

          RowLayout {
            width: parent.width
            spacing: Style.space(6)

            Text {
              Layout.fillWidth: true
              text: root.result.title || ""
              color: root.contentForeground
              font.family: root.contentFontFamily
              font.pixelSize: Style.font.display
              font.bold: true
              elide: Text.ElideRight
            }

            Button {
              text: "Pronominal"
              bordered: true
              selected: root.result.pronominal === true
              foreground: root.contentForeground
              tooltipText: root.result.pronominal ? "Revenir à la forme simple" : "Conjuguer à la forme pronominale"
              onClicked: root.togglePronominal()
            }

            Button {
              text: root.copiedText === "" ? "Copier" : root.copiedText
              bordered: true
              foreground: root.contentForeground
              onClicked: root.copyResults()
            }
          }

          Flow {
            width: parent.width
            spacing: Style.space(6)

            Text {
              height: modelButton.height
              verticalAlignment: Text.AlignVCenter
              text: (root.result.group || "") + "  ·  auxiliaire " + (root.result.auxiliary || "")
                + (root.result.auxNote ? " (" + root.result.auxNote + ")" : "") + "  ·  modèle"
              color: Qt.darker(root.contentForeground, 1.3)
              font.family: root.contentFontFamily
              font.pixelSize: Style.font.bodySmall
            }

            Button {
              id: modelButton
              text: root.result.model || ""
              foreground: Color.accent
              fontSize: Style.font.bodySmall
              verticalPadding: Style.space(2)
              tooltipText: "Conjuguer le verbe modèle"
              enabled: root.result.model !== root.result.verb
              onClicked: root.conjugate(root.result.model)
            }
          }

          Text {
            width: parent.width
            visible: !!root.result.note
            text: root.result.note || ""
            color: Qt.darker(root.contentForeground, 1.5)
            font.family: root.contentFontFamily
            font.pixelSize: Style.font.bodySmall
            font.italic: true
            wrapMode: Text.WordWrap
          }

          ButtonGroup {
            spacing: Style.space(4)
            focusable: false
            options: root.tabs
            value: root.modeName
            foreground: root.contentForeground
            fontFamily: root.contentFontFamily
            fontSize: Style.font.bodySmall
            onChanged: function(value) { root.modeName = value }
          }

          Flickable {
            id: resultsFlick
            width: parent.width
            // Whatever room the screen leaves below the header, so the
            // popup never runs past the bottom edge; the tables scroll.
            readonly property real room: root.panelMaxHeight - panel.verticalContentInset - resultsColumn.y - y
            height: Math.max(Style.space(120), Math.min(contentHeight, room))
            contentHeight: tenseGrid.implicitHeight
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            rightMargin: contentHeight > height ? Style.space(10) : 0

            ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

            GridLayout {
              id: tenseGrid
              width: resultsFlick.width - resultsFlick.rightMargin
              columns: 2
              columnSpacing: Style.space(14)
              rowSpacing: Style.space(14)

              Repeater {
                model: root.visibleTenses

                Rectangle {
                  required property var modelData
                  Layout.fillWidth: true
                  Layout.preferredWidth: 1
                  Layout.alignment: Qt.AlignTop
                  implicitHeight: tenseColumn.implicitHeight + Style.space(20)
                  radius: Style.cornerRadius
                  color: Qt.rgba(root.contentForeground.r, root.contentForeground.g, root.contentForeground.b, 0.04)
                  border.width: Style.spacing.hairline
                  border.color: Qt.rgba(root.contentForeground.r, root.contentForeground.g, root.contentForeground.b, 0.12)

                  Column {
                    id: tenseColumn
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.top: parent.top
                    anchors.margins: Style.space(10)
                    spacing: Style.space(3)

                    Text {
                      text: modelData.name.toUpperCase()
                      color: Color.accent
                      font.family: root.contentFontFamily
                      font.pixelSize: Style.font.caption
                      font.bold: true
                      font.letterSpacing: 1.0
                      bottomPadding: Style.space(3)
                    }

                    Repeater {
                      model: modelData.lines
                      Text {
                        required property string modelData
                        width: tenseColumn.width
                        text: root.styled(modelData)
                        textFormat: Text.StyledText
                        color: Color.foreground
                        font.family: root.contentFontFamily
                        font.pixelSize: Style.font.body
                        wrapMode: Text.WordWrap
                      }
                    }
                  }
                }
              }
            }
          }
        }
      }
    }
  }
}
