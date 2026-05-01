import QtQuick
import Quickshell
import qs.Common
import qs.Widgets
import qs.Services
import qs.Modules.Plugins

PluginComponent {
    id: root

    // ---------- Settings ----------
    readonly property string zerotierBinary: pluginData.zerotierBinary || "zerotier-cli"
    readonly property bool useSudo: pluginData.useSudo ?? true
    readonly property int refreshIntervalMs: ((pluginData.refreshInterval ?? 5)) * 1000
    readonly property string knownNetworksFile: pluginData.knownNetworksFile && pluginData.knownNetworksFile.length > 0
        ? pluginData.knownNetworksFile
        : (Quickshell.env("HOME") + "/.config/zerotier/known-zt-networks")
    readonly property string extraNetworksFile: pluginData.extraNetworksFile || ""
    readonly property bool autoAdd: pluginData.autoAdd ?? true
    readonly property var configuredNetworks: pluginData.configuredNetworks || []

    // ---------- State ----------
    // networks: [{nwid, name, ips, joined, allowDefault, allowDNS, routeActive, via}]
    property var networks: []
    property bool routingActive: false
    property string routingName: ""
    property string routingVia: ""
    property int joinedCount: 0
    property bool loading: false
    property bool zerotierAvailable: true

    // In-flight action tracking — nwid -> true while a command is pending
    property var inFlight: ({})
    function setInFlight(nwid, on) {
        const m = Object.assign({}, inFlight);
        if (on) m[nwid] = true;
        else delete m[nwid];
        inFlight = m;
    }
    function isInFlight(nwid) { return !!inFlight[nwid]; }

    // Pill pulse — incremented on each action to trigger animation
    property int pulseCount: 0

    // ---------- Refresh ----------
    function refreshEnv() {
        return [
            "ZT_BIN=" + zerotierBinary,
            "USE_SUDO=" + (useSudo ? "1" : ""),
            "AUTO_ADD=" + (autoAdd ? "1" : ""),
            "KNOWN_FILE=" + knownNetworksFile,
            "EXTRA_FILE=" + extraNetworksFile
        ];
    }

    readonly property string refreshScript: "{\n"
        + "  ZT=\"${ZT_BIN:-zerotier-cli}\"\n"
        + "  [ -n \"$USE_SUDO\" ] && ZT=\"sudo -n $ZT\"\n"
        + "  LISTNET=$($ZT listnetworks 2>/dev/null) || exit 1\n"
        + "  IPROUTE=$(ip route 2>/dev/null)\n"
        + "  joined=$(echo \"$LISTNET\" | grep \"^200\" | grep \" OK \")\n"
        + "  echo \"$joined\" | while IFS= read -r line; do\n"
        + "    [ -z \"$line\" ] && continue\n"
        + "    nwid=$(echo \"$line\" | cut -d' ' -f3)\n"
        + "    name=$(echo \"$line\" | cut -d' ' -f4)\n"
        + "    dev=$(echo \"$line\" | cut -d' ' -f8)\n"
        + "    ips=$(echo \"$line\" | cut -d' ' -f9-)\n"
        + "    ad=\"0\"\n"
        + "    $ZT get \"$nwid\" allowDefault 2>/dev/null | grep -E -q \"true|1\" && ad=\"1\"\n"
        + "    dn=\"0\"\n"
        + "    $ZT get \"$nwid\" allowDNS 2>/dev/null | grep -E -q \"true|1\" && dn=\"1\"\n"
        + "    ra=\"0\"; via=\"\"\n"
        + "    if echo \"$IPROUTE\" | grep -E \" dev $dev \" | grep -E -q \"0\\.0\\.0\\.0/1|128\\.0\\.0\\.0/1\"; then\n"
        + "      ra=\"1\"\n"
        + "      via=$(echo \"$IPROUTE\" | grep -E \" dev $dev \" | grep -E \"0\\.0\\.0\\.0/1|128\\.0\\.0\\.0/1\" | head -1 | cut -d' ' -f3)\n"
        + "    fi\n"
        + "    printf 'J\\t%s\\t%s\\t%s\\t%s\\t%s\\t%s\\t%s\\n' \"$nwid\" \"$ips\" \"$ad\" \"$dn\" \"$ra\" \"$via\" \"$name\"\n"
        + "  done\n"
        + "  if [ -n \"$AUTO_ADD\" ] && [ -n \"$KNOWN_FILE\" ]; then\n"
        + "    mkdir -p \"$(dirname \"$KNOWN_FILE\")\" 2>/dev/null\n"
        + "    touch \"$KNOWN_FILE\" 2>/dev/null\n"
        + "    echo \"$joined\" | while IFS= read -r line; do\n"
        + "      [ -z \"$line\" ] && continue\n"
        + "      nwid=$(echo \"$line\" | cut -d' ' -f3)\n"
        + "      name=$(echo \"$line\" | cut -d' ' -f4)\n"
        + "      grep -q \"^${nwid} \" \"$KNOWN_FILE\" || echo \"${nwid} ${name}\" >> \"$KNOWN_FILE\"\n"
        + "    done\n"
        + "  fi\n"
        + "  jn=$(echo \"$joined\" | awk '{print $3}')\n"
        + "  {\n"
        + "    [ -n \"$KNOWN_FILE\" ] && [ -f \"$KNOWN_FILE\" ] && cat \"$KNOWN_FILE\"\n"
        + "    [ -n \"$EXTRA_FILE\" ] && [ -f \"$EXTRA_FILE\" ] && cat \"$EXTRA_FILE\"\n"
        + "  } | grep -v '^[[:space:]]*#' | grep -v '^[[:space:]]*$' | awk '!seen[$1]++' | while IFS= read -r line; do\n"
        + "    nwid=$(echo \"$line\" | cut -d' ' -f1)\n"
        + "    name=$(echo \"$line\" | cut -d' ' -f2-)\n"
        + "    if ! echo \"$jn\" | grep -q \"^${nwid}$\"; then\n"
        + "      printf 'K\\t%s\\t%s\\n' \"$nwid\" \"$name\"\n"
        + "    fi\n"
        + "  done\n"
        + "}\n"

    function refresh() {
        loading = true;
        const env = refreshEnv();
        Proc.runCommand(
            "zerotierManager.refresh",
            ["env"].concat(env).concat(["sh", "-c", refreshScript]),
            function(out, exitCode) {
                loading = false;
                if (exitCode !== 0) {
                    zerotierAvailable = false;
                    networks = [];
                    joinedCount = 0;
                    routingActive = false;
                    routingName = "";
                    routingVia = "";
                    return;
                }
                zerotierAvailable = true;
                parseRefresh(out);
            },
            100
        );
    }

    function parseRefresh(out) {
        const list = [];
        let routing = false;
        let routingNm = "";
        let routingV = "";
        let joined = 0;
        const lines = out.split("\n");
        for (let i = 0; i < lines.length; i++) {
            const line = lines[i];
            if (!line) continue;
            const parts = line.split("\t");
            if (parts[0] === "J" && parts.length >= 8) {
                const net = {
                    nwid: parts[1],
                    ips: parts[2],
                    allowDefault: parts[3] === "1",
                    allowDNS: parts[4] === "1",
                    routeActive: parts[5] === "1",
                    via: parts[6],
                    name: parts[7],
                    joined: true
                };
                list.push(net);
                joined++;
                if (net.routeActive) {
                    routing = true;
                    routingNm = net.name;
                    routingV = net.via;
                }
            } else if (parts[0] === "K" && parts.length >= 3) {
                list.push({
                    nwid: parts[1],
                    name: parts[2],
                    ips: "",
                    allowDefault: false,
                    allowDNS: false,
                    routeActive: false,
                    via: "",
                    joined: false
                });
            }
        }

        // Merge configured networks (from plugin_settings.json) — only those whose
        // nwid isn't already represented from listnetworks / known / extra files
        const seen = {};
        for (let k = 0; k < list.length; k++) seen[list[k].nwid] = true;
        const cfgList = configuredNetworks || [];
        for (let c = 0; c < cfgList.length; c++) {
            const cfg = cfgList[c];
            if (!cfg || !cfg.nwid) continue;
            const id = String(cfg.nwid).toLowerCase();
            if (seen[id]) continue;
            list.push({
                nwid: id,
                name: cfg.name || id,
                ips: "",
                allowDefault: false,
                allowDNS: false,
                routeActive: false,
                via: "",
                joined: false
            });
            seen[id] = true;
        }

        networks = list;
        joinedCount = joined;
        routingActive = routing;
        routingName = routingNm;
        routingVia = routingV;
    }

    // ---------- Actions ----------
    function executeAction(action, nwid, name) {
        let cmd = "";
        let toastMsg = "";

        if (action === "join") {
            cmd = "$ZT join \"" + nwid + "\"";
            toastMsg = "Joining " + (name || nwid);
        } else if (action === "leave") {
            cmd = "$ZT leave \"" + nwid + "\"";
            toastMsg = "Leaving " + name;
        } else if (action === "enableDefault") {
            cmd = "$ZT set \"" + nwid + "\" allowDefault=1";
            toastMsg = "Default route enabled for " + name;
        } else if (action === "disableDefault") {
            cmd = "$ZT set \"" + nwid + "\" allowDefault=0";
            toastMsg = "Default route disabled for " + name;
        } else if (action === "enableDNS") {
            cmd = "$ZT set \"" + nwid + "\" allowDNS=1";
            toastMsg = "DNS enabled for " + name;
        } else if (action === "disableDNS") {
            cmd = "$ZT set \"" + nwid + "\" allowDNS=0";
            toastMsg = "DNS disabled for " + name;
        } else if (action === "joinAndRoute") {
            cmd = "$ZT join \"" + nwid + "\" && sleep 2 && $ZT set \"" + nwid + "\" allowDefault=1";
            toastMsg = "Joining " + (name || nwid) + " with default route";
        } else {
            return;
        }

        const fullScript = "ZT=\"${ZT_BIN:-zerotier-cli}\"; [ -n \"$USE_SUDO\" ] && ZT=\"sudo -n $ZT\"; " + cmd;
        const env = refreshEnv();

        setInFlight(nwid, true);
        pulseCount++;
        inFlightTimer.restart();

        Proc.runCommand(
            "zerotierManager.action." + action + "." + nwid,
            ["env"].concat(env).concat(["sh", "-c", fullScript]),
            function(out, exitCode) {
                if (typeof ToastService !== "undefined") {
                    if (exitCode === 0) {
                        ToastService.showInfo(toastMsg);
                    } else {
                        ToastService.showError("ZeroTier: " + action + " failed for " + (name || nwid));
                    }
                }
                Qt.callLater(root.refresh);
                postActionTimer.restart();
            },
            50
        );
    }

    // ---------- Timers ----------
    Timer {
        id: refreshTimer
        interval: root.refreshIntervalMs
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: root.refresh()
    }

    Timer {
        id: postActionTimer
        interval: 1500
        repeat: false
        onTriggered: root.refresh()
    }

    // Safety net: clear all in-flight markers after 4s if something stalls
    Timer {
        id: inFlightTimer
        interval: 4000
        repeat: false
        onTriggered: root.inFlight = ({})
    }

    // ---------- Pill helpers ----------
    function pillBgColor() {
        if (!zerotierAvailable) return Theme.surfaceContainerHigh;
        if (routingActive) return Theme.primary;
        if (joinedCount > 0) return Theme.primaryContainer;
        return Theme.surfaceContainerHigh;
    }
    function pillFgColor() {
        if (routingActive) return Theme.background;
        if (joinedCount > 0) return Theme.primary;
        return Theme.surfaceText;
    }
    function pillIcon() {
        if (routingActive) return "router";
        if (joinedCount > 0) return "verified_user";
        return "shield";
    }
    function pillTooltip() {
        if (!zerotierAvailable) return "ZeroTier daemon unreachable";
        if (joinedCount === 0) return "ZeroTier: no networks connected";
        if (routingActive) return "ZeroTier ROUTING: " + routingName + (routingVia ? " via " + routingVia : "");
        const names = networks.filter(function(n) { return n.joined; }).map(function(n) { return n.name; });
        return "ZeroTier: " + names.join(", ");
    }

    // Per-row icon
    function rowIcon(net) {
        if (!net.joined) return "shield";
        if (net.routeActive) return "router";
        return "verified_user";
    }
    function rowIconColor(net) {
        if (!net.joined) return Theme.surfaceVariantText;
        if (net.routeActive) return Theme.primary;
        return Theme.primary;
    }

    // ---------- Bar pills ----------
    horizontalBarPill: Component {
        StyledRect {
            id: hPill
            implicitWidth: pillRow.implicitWidth + Theme.spacingM * 2
            implicitHeight: parent.widgetThickness
            radius: Theme.cornerRadius
            color: root.pillBgColor()
            scale: 1.0

            Behavior on color {
                ColorAnimation { duration: Theme.shortDuration ?? 200; easing.type: Easing.OutCubic }
            }

            // Pulse animation on action
            SequentialAnimation {
                id: hPulseAnim
                NumberAnimation { target: hPill; property: "scale"; from: 1.0; to: 1.10; duration: 110; easing.type: Easing.OutQuad }
                NumberAnimation { target: hPill; property: "scale"; from: 1.10; to: 1.0; duration: 220; easing.type: Easing.OutBounce }
            }
            Connections {
                target: root
                function onPulseCountChanged() { hPulseAnim.restart(); }
            }

            Row {
                id: pillRow
                anchors.centerIn: parent
                spacing: Theme.spacingXS

                DankIcon {
                    name: root.pillIcon()
                    size: Theme.fontSizeLarge
                    color: root.pillFgColor()
                    anchors.verticalCenter: parent.verticalCenter
                }

                StyledText {
                    visible: root.joinedCount > 0
                    text: root.joinedCount.toString()
                    color: root.pillFgColor()
                    font.pixelSize: Theme.fontSizeSmall
                    font.weight: Font.Medium
                    anchors.verticalCenter: parent.verticalCenter
                }
            }

            DankTooltip { text: root.pillTooltip() }
        }
    }

    verticalBarPill: Component {
        StyledRect {
            id: vPill
            implicitWidth: parent.widgetThickness
            implicitHeight: pillCol.implicitHeight + Theme.spacingM * 2
            radius: Theme.cornerRadius
            color: root.pillBgColor()
            scale: 1.0

            Behavior on color {
                ColorAnimation { duration: Theme.shortDuration ?? 200; easing.type: Easing.OutCubic }
            }

            SequentialAnimation {
                id: vPulseAnim
                NumberAnimation { target: vPill; property: "scale"; from: 1.0; to: 1.10; duration: 110; easing.type: Easing.OutQuad }
                NumberAnimation { target: vPill; property: "scale"; from: 1.10; to: 1.0; duration: 220; easing.type: Easing.OutBounce }
            }
            Connections {
                target: root
                function onPulseCountChanged() { vPulseAnim.restart(); }
            }

            Column {
                id: pillCol
                anchors.centerIn: parent
                spacing: Theme.spacingXS

                DankIcon {
                    name: root.pillIcon()
                    size: Theme.fontSizeLarge
                    color: root.pillFgColor()
                    anchors.horizontalCenter: parent.horizontalCenter
                }

                StyledText {
                    visible: root.joinedCount > 0
                    text: root.joinedCount.toString()
                    color: root.pillFgColor()
                    font.pixelSize: Theme.fontSizeSmall
                    font.weight: Font.Medium
                    anchors.horizontalCenter: parent.horizontalCenter
                }
            }

            DankTooltip { text: root.pillTooltip() }
        }
    }

    // ---------- Popout ----------
    popoutWidth: 520
    popoutHeight: 520

    popoutContent: Component {
        PopoutComponent {
            id: popout
            headerText: "ZeroTier"
            detailsText: root.routingActive
                ? "Routing via " + root.routingName + (root.routingVia ? " (" + root.routingVia + ")" : "")
                : (root.joinedCount === 0
                    ? (root.zerotierAvailable ? "No networks connected" : "Daemon unreachable")
                    : root.joinedCount + (root.joinedCount === 1 ? " network connected" : " networks connected"))
            showCloseButton: true

            headerActions: Component {
                Rectangle {
                    width: 32
                    height: 32
                    radius: 16
                    color: refreshArea.containsMouse
                        ? Theme.withAlpha(Theme.primary, 0.12)
                        : "transparent"

                    DankIcon {
                        anchors.centerIn: parent
                        name: "refresh"
                        size: Theme.iconSize - 4
                        color: refreshArea.containsMouse ? Theme.primary : Theme.surfaceText
                        opacity: root.loading ? 0.5 : 1.0

                        RotationAnimation on rotation {
                            running: root.loading
                            from: 0; to: 360
                            duration: 900
                            loops: Animation.Infinite
                        }
                    }

                    MouseArea {
                        id: refreshArea
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        enabled: !root.loading
                        onClicked: root.refresh()
                    }

                    DankTooltip { text: "Refresh" }
                }
            }

            Component.onCompleted: root.refresh()

            Column {
                width: parent.width
                spacing: Theme.spacingM

                StyledText {
                    visible: root.networks.length === 0
                    width: parent.width
                    text: root.zerotierAvailable
                        ? "No ZeroTier networks. Add one in plugin Settings → Configured networks, or run `zerotier-cli join <network-id>` from a shell."
                        : "ZeroTier daemon unreachable. Make sure zerotier-one is running and that '" + root.zerotierBinary + "' is on PATH (with passwordless sudo if 'Run with sudo' is enabled)."
                    color: Theme.surfaceVariantText
                    font.pixelSize: Theme.fontSizeSmall
                    wrapMode: Text.WordWrap
                    horizontalAlignment: Text.AlignHCenter
                }

                // Network list — scrollable
                Flickable {
                    width: parent.width
                    height: Math.min(networkColumn.implicitHeight, root.popoutHeight - 160)
                    contentWidth: width
                    contentHeight: networkColumn.implicitHeight
                    clip: true
                    flickableDirection: Flickable.VerticalFlick
                    boundsBehavior: Flickable.StopAtBounds

                    Column {
                        id: networkColumn
                        width: parent.width
                        spacing: Theme.spacingS

                        Repeater {
                            model: root.networks

                            StyledRect {
                                id: rowRect
                                width: networkColumn.width
                                implicitHeight: rowCol.implicitHeight + Theme.spacingM * 2
                                radius: Theme.cornerRadius
                                color: modelData.routeActive
                                    ? Theme.withAlpha(Theme.primary, 0.18)
                                    : (modelData.joined
                                        ? Theme.withAlpha(Theme.primaryContainer, Theme.popupTransparency)
                                        : Theme.withAlpha(Theme.surfaceContainerHigh, Theme.popupTransparency))

                                Behavior on color {
                                    ColorAnimation { duration: 600; easing.type: Easing.OutCubic }
                                }

                                Row {
                                    anchors.left: parent.left
                                    anchors.right: parent.right
                                    anchors.verticalCenter: parent.verticalCenter
                                    anchors.leftMargin: Theme.spacingM
                                    anchors.rightMargin: Theme.spacingM
                                    spacing: Theme.spacingM

                                    // Leading state icon
                                    DankIcon {
                                        anchors.verticalCenter: parent.verticalCenter
                                        name: root.isInFlight(modelData.nwid) ? "progress_activity" : root.rowIcon(modelData)
                                        size: Theme.fontSizeLarge + 4
                                        color: root.rowIconColor(modelData)

                                        RotationAnimation on rotation {
                                            running: root.isInFlight(modelData.nwid)
                                            from: 0; to: 360
                                            duration: 900
                                            loops: Animation.Infinite
                                        }
                                    }

                                    Column {
                                        id: rowCol
                                        width: parent.width - parent.spacing - (Theme.fontSizeLarge + 4) - Theme.spacingM
                                        spacing: Theme.spacingXS

                                        Row {
                                            width: parent.width
                                            spacing: Theme.spacingS

                                            StyledText {
                                                text: modelData.name || modelData.nwid
                                                font.pixelSize: Theme.fontSizeMedium
                                                font.weight: Font.Bold
                                                color: Theme.surfaceText
                                                anchors.verticalCenter: parent.verticalCenter
                                            }

                                            // ON / ROUTING / OFF badge
                                            StyledRect {
                                                visible: modelData.joined
                                                radius: Theme.cornerRadius
                                                color: modelData.routeActive ? Theme.primary : Theme.primaryContainer
                                                implicitWidth: badgeRow.implicitWidth + Theme.spacingS * 2
                                                implicitHeight: badgeRow.implicitHeight + 4
                                                anchors.verticalCenter: parent.verticalCenter

                                                Row {
                                                    id: badgeRow
                                                    anchors.centerIn: parent
                                                    spacing: 4
                                                    DankIcon {
                                                        visible: modelData.routeActive
                                                        anchors.verticalCenter: parent.verticalCenter
                                                        name: "alt_route"
                                                        size: Theme.fontSizeSmall
                                                        color: Theme.background
                                                    }
                                                    StyledText {
                                                        anchors.verticalCenter: parent.verticalCenter
                                                        text: modelData.routeActive ? "ROUTING" : "ON"
                                                        font.pixelSize: Theme.fontSizeSmall
                                                        font.weight: Font.Medium
                                                        color: modelData.routeActive ? Theme.background : Theme.primary
                                                    }
                                                }
                                            }

                                            StyledRect {
                                                visible: !modelData.joined
                                                radius: Theme.cornerRadius
                                                color: Theme.withAlpha(Theme.surfaceVariant, Theme.popupTransparency)
                                                implicitWidth: offBadgeText.implicitWidth + Theme.spacingS * 2
                                                implicitHeight: offBadgeText.implicitHeight + 4
                                                anchors.verticalCenter: parent.verticalCenter

                                                StyledText {
                                                    id: offBadgeText
                                                    anchors.centerIn: parent
                                                    text: "OFF"
                                                    font.pixelSize: Theme.fontSizeSmall
                                                    font.weight: Font.Medium
                                                    color: Theme.surfaceVariantText
                                                }
                                            }

                                            // DNS pill (only when joined and DNS is on)
                                            StyledRect {
                                                visible: modelData.joined && modelData.allowDNS
                                                radius: Theme.cornerRadius
                                                color: Theme.withAlpha(Theme.primary, 0.15)
                                                implicitWidth: dnsRow.implicitWidth + Theme.spacingS * 2
                                                implicitHeight: dnsRow.implicitHeight + 4
                                                anchors.verticalCenter: parent.verticalCenter

                                                Row {
                                                    id: dnsRow
                                                    anchors.centerIn: parent
                                                    spacing: 4
                                                    DankIcon {
                                                        anchors.verticalCenter: parent.verticalCenter
                                                        name: "dns"
                                                        size: Theme.fontSizeSmall
                                                        color: Theme.primary
                                                    }
                                                    StyledText {
                                                        anchors.verticalCenter: parent.verticalCenter
                                                        text: "DNS"
                                                        font.pixelSize: Theme.fontSizeSmall
                                                        font.weight: Font.Medium
                                                        color: Theme.primary
                                                    }
                                                }
                                            }
                                        }

                                        StyledText {
                                            visible: modelData.joined && modelData.ips && modelData.ips.length > 0
                                            width: parent.width
                                            text: modelData.ips
                                            font.pixelSize: Theme.fontSizeSmall
                                            font.family: "monospace"
                                            color: Theme.surfaceVariantText
                                            elide: Text.ElideRight
                                        }

                                        StyledText {
                                            visible: modelData.joined
                                            width: parent.width
                                            text: "default route: " + (modelData.allowDefault ? "on" : "off")
                                                + "  ·  DNS: " + (modelData.allowDNS ? "on" : "off")
                                                + (modelData.routeActive ? "  ·  via " + modelData.via : "")
                                            font.pixelSize: Theme.fontSizeSmall
                                            color: Theme.surfaceVariantText
                                        }

                                        StyledText {
                                            width: parent.width
                                            text: modelData.nwid
                                            font.pixelSize: Theme.fontSizeSmall
                                            font.family: "monospace"
                                            color: Theme.surfaceVariantText
                                            opacity: 0.6
                                        }

                                        Flow {
                                            width: parent.width
                                            spacing: Theme.spacingS

                                            DankButton {
                                                visible: modelData.joined
                                                enabled: !root.isInFlight(modelData.nwid)
                                                text: "Leave"
                                                onClicked: root.executeAction("leave", modelData.nwid, modelData.name)
                                            }
                                            DankButton {
                                                visible: modelData.joined
                                                enabled: !root.isInFlight(modelData.nwid)
                                                text: modelData.allowDefault ? "Default: on" : "Default: off"
                                                onClicked: root.executeAction(
                                                    modelData.allowDefault ? "disableDefault" : "enableDefault",
                                                    modelData.nwid, modelData.name
                                                )
                                            }
                                            DankButton {
                                                visible: modelData.joined
                                                enabled: !root.isInFlight(modelData.nwid)
                                                text: modelData.allowDNS ? "DNS: on" : "DNS: off"
                                                onClicked: root.executeAction(
                                                    modelData.allowDNS ? "disableDNS" : "enableDNS",
                                                    modelData.nwid, modelData.name
                                                )
                                            }
                                            DankButton {
                                                visible: !modelData.joined
                                                enabled: !root.isInFlight(modelData.nwid)
                                                text: "Join"
                                                onClicked: root.executeAction("join", modelData.nwid, modelData.name)
                                            }
                                            DankButton {
                                                visible: !modelData.joined
                                                enabled: !root.isInFlight(modelData.nwid)
                                                text: "Join + route"
                                                onClicked: root.executeAction("joinAndRoute", modelData.nwid, modelData.name)
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
