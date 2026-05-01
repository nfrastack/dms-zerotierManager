import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.Common
import qs.Widgets

Column {
    id: root

    required property string settingKey
    required property string label
    property string description: ""
    property var fields: []
    property var defaultValue: []
    property var items: defaultValue

    width: parent.width
    spacing: Theme.spacingM

    property bool isLoading: false
    property int editingIndex: -1

    Component.onCompleted: {
        loadValue()
    }

    function loadValue() {
        const settings = findSettings()
        if (settings) {
            isLoading = true
            items = settings.loadValue(settingKey, defaultValue)
            isLoading = false
        }
    }

    onItemsChanged: {
        if (isLoading) return
        const settings = findSettings()
        if (settings) settings.saveValue(settingKey, items)
    }

    function findSettings() {
        let item = parent
        while (item) {
            if (item.saveValue !== undefined && item.loadValue !== undefined) return item
            item = item.parent
        }
        return null
    }

    function addItem(item) {
        items = items.concat([item])
    }
    function removeItem(index) {
        const newItems = items.slice()
        newItems.splice(index, 1)
        items = newItems
    }
    function replaceItem(index, item) {
        const newItems = items.slice()
        newItems.splice(index, 1, item)
        items = newItems
    }
    function beginEdit(index) {
        editingIndex = index
        const item = items[index]
        for (let i = 0; i < root.fields.length; i++) {
            inputRow.inputFields[i].text = item[root.fields[i].id] || ""
        }
        if (inputRow.inputFields.length > 0) inputRow.inputFields[0].forceActiveFocus()
    }
    function cancelEdit() {
        editingIndex = -1
        for (let i = 0; i < inputRow.inputFields.length; i++) inputRow.inputFields[i].text = ""
        if (inputRow.inputFields.length > 0) inputRow.inputFields[0].forceActiveFocus()
    }

    StyledText {
        text: root.label
        font.pixelSize: Theme.fontSizeMedium
        font.weight: Font.Medium
        color: Theme.surfaceText
    }

    StyledText {
        text: root.description
        font.pixelSize: Theme.fontSizeSmall
        color: Theme.surfaceVariantText
        width: parent.width
        wrapMode: Text.WordWrap
        visible: root.description !== ""
    }

    Flow {
        width: parent.width
        spacing: Theme.spacingS

        Repeater {
            model: root.fields
            StyledText {
                text: modelData.label
                font.pixelSize: Theme.fontSizeSmall
                font.weight: Font.Medium
                color: Theme.surfaceText
                width: modelData.width || 200
            }
        }
    }

    Flow {
        id: inputRow
        width: parent.width
        spacing: Theme.spacingS

        property var inputFields: []

        Repeater {
            id: inputRepeater
            model: root.fields
            DankTextField {
                width: modelData.width || 200
                placeholderText: modelData.placeholder || ""
                Component.onCompleted: { inputRow.inputFields.push(this) }
                Keys.onReturnPressed: { addButton.clicked() }
            }
        }

        DankButton {
            id: addButton
            width: root.editingIndex >= 0 ? 70 : 50
            height: 36
            text: root.editingIndex >= 0 ? "Update" : "Add"

            onClicked: {
                let newItem = {}
                let hasValue = false
                for (let i = 0; i < root.fields.length; i++) {
                    const field = root.fields[i]
                    const input = inputRow.inputFields[i]
                    const value = input.text.trim()
                    if (value !== "") hasValue = true
                    if (field.required && value === "") return
                    newItem[field.id] = value || (field.default || "")
                }
                if (hasValue) {
                    if (root.editingIndex >= 0) {
                        root.replaceItem(root.editingIndex, newItem)
                        root.editingIndex = -1
                    } else {
                        root.addItem(newItem)
                    }
                    for (let i = 0; i < inputRow.inputFields.length; i++) inputRow.inputFields[i].text = ""
                    if (inputRow.inputFields.length > 0) inputRow.inputFields[0].forceActiveFocus()
                }
            }
        }

        DankButton {
            id: cancelButton
            width: 60
            height: 36
            text: "Cancel"
            visible: root.editingIndex >= 0
            onClicked: { root.cancelEdit() }
        }
    }

    StyledText {
        text: "Configured networks"
        font.pixelSize: Theme.fontSizeMedium
        font.weight: Font.Medium
        color: Theme.surfaceText
        visible: root.items.length > 0
    }

    Column {
        width: parent.width
        spacing: Theme.spacingS

        Repeater {
            model: root.items

            StyledRect {
                width: parent.width
                height: 40
                radius: Theme.cornerRadius
                color: root.editingIndex === index
                       ? Theme.withAlpha(Theme.primaryContainer, Theme.popupTransparency)
                       : Theme.withAlpha(Theme.surfaceContainerHigh, Theme.popupTransparency)
                border.width: 0

                required property int index
                required property var modelData

                RowLayout {
                    id: itemRow
                    anchors.left: parent.left
                    anchors.leftMargin: Theme.spacingM
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: Theme.spacingM

                    property var itemData: parent.modelData

                    Repeater {
                        model: root.fields
                        Item {
                            required property int index
                            required property var modelData

                            Layout.preferredWidth: modelData ? (modelData.width || 200) : 200
                            Layout.alignment: Qt.AlignVCenter
                            implicitHeight: cellText.implicitHeight

                            StyledText {
                                id: cellText
                                width: parent.width
                                text: {
                                    const field = parent.modelData
                                    const item = itemRow.itemData
                                    if (!field || !field.id || !item) return ""
                                    const value = item[field.id]
                                    return value || ""
                                }
                                color: Theme.surfaceText
                                font.pixelSize: Theme.fontSizeMedium
                                font.family: parent.modelData && parent.modelData.id === "nwid" ? "monospace" : Theme.fontFamily
                                elide: Text.ElideRight
                                verticalAlignment: Text.AlignVCenter
                            }
                        }
                    }
                }

                Rectangle {
                    anchors.right: removeButton.left
                    anchors.rightMargin: Theme.spacingM
                    anchors.verticalCenter: parent.verticalCenter
                    width: 50
                    height: 28
                    color: Theme.secondary
                    radius: Theme.cornerRadius

                    StyledText {
                        anchors.centerIn: parent
                        text: "Edit"
                        color: Theme.buttonText
                        font.pixelSize: Theme.fontSizeSmall
                        font.weight: Font.Medium
                    }
                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: { root.beginEdit(index) }
                    }
                }

                Rectangle {
                    id: removeButton
                    anchors.right: parent.right
                    anchors.rightMargin: Theme.spacingM
                    anchors.verticalCenter: parent.verticalCenter
                    width: 60
                    height: 28
                    color: Theme.error
                    radius: Theme.cornerRadius

                    StyledText {
                        anchors.centerIn: parent
                        text: "Remove"
                        color: Theme.buttonText
                        font.pixelSize: Theme.fontSizeSmall
                        font.weight: Font.Medium
                    }
                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            if (root.editingIndex === index) root.cancelEdit()
                            root.removeItem(index)
                        }
                    }
                }
            }
        }

        StyledText {
            text: "No configured networks yet."
            font.pixelSize: Theme.fontSizeSmall
            color: Theme.surfaceVariantText
            visible: root.items.length === 0
        }
    }
}
