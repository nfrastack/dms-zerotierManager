import QtQuick
import qs.Common
import qs.Widgets
import qs.Modules.Plugins

PluginSettings {
    pluginId: "zerotierManager"

    StyledText {
        width: parent.width
        text: "ZeroTier Manager Settings"
        font.pixelSize: Theme.fontSizeLarge
        font.weight: Font.Bold
        color: Theme.surfaceText
    }

    StyledText {
        width: parent.width
        text: "Show ZeroTier network status in the bar - join/leave/route from the popout."
        font.pixelSize: Theme.fontSizeSmall
        color: Theme.surfaceVariantText
        wrapMode: Text.WordWrap
    }

    StringSetting {
        settingKey: "zerotierBinary"
        label: "zerotier-cli binary"
        description: "Path or name of the zerotier-cli binary. Bare name uses PATH - full path also works."
        defaultValue: "zerotier-cli"
        placeholder: "zerotier-cli"
    }

    ToggleSetting {
        settingKey: "useSudo"
        label: "Run with sudo -n"
        description: "Prepend 'sudo -n' to zerotier-cli calls. Requires passwordless sudo for zerotier-cli (NOPASSWD in sudoers). Leave off if your user can already talk to the daemon (zerotier-one group membership or a readable auth token)."
        defaultValue: false
    }

    SliderSetting {
        settingKey: "refreshInterval"
        label: "Refresh interval"
        description: "How often to poll ZeroTier in the background. Uses one 'zerotier-cli -j listnetworks' call plus 'ip route' per tick."
        defaultValue: 15
        minimum: 5
        maximum: 60
        unit: "s"
        leftIcon: "schedule"
    }

    SliderSetting {
        settingKey: "popoutRefreshInterval"
        label: "Popout refresh interval"
        description: "Faster poll cadence while the popout is open. Stops when the popout closes."
        defaultValue: 3
        minimum: 1
        maximum: 15
        unit: "s"
        leftIcon: "refresh"
    }

    StringSetting {
        settingKey: "extraNetworksFile"
        label: "Extra networks file (read-only)"
        description: "Optional file merged into the network list. Same format as below. Plugin never writes to this file. Duplicates are deduped by network ID."
        defaultValue: ""
        placeholder: ""
    }

    ToggleSetting {
        settingKey: "storeInSettings"
        label: "Store remembered networks in plugin settings"
        description: "When on, networks you join are remembered in 'Configured networks' below and no files are created. When off, they are appended to the legacy known-networks file (~/.config/zerotier/known-zt-networks) instead."
        defaultValue: true
    }

    ToggleSetting {
        settingKey: "autoAdd"
        label: "Auto-add joined networks"
        description: "When you join a network outside the plugin, automatically remember it (in plugin settings, or in the legacy file if storage above is off) so it shows up here even after you leave it."
        defaultValue: true
    }

    NetworkList {
        settingKey: "configuredNetworks"
        label: "Configured networks"
        description: "Networks added here appear in the popout as OFF until you click Join. Stored inline in plugin_settings.json. For network entries you'd rather not store here, use the 'Extra networks file' field above instead."
        defaultValue: []
        fields: [
            { id: "nwid", label: "Network ID", placeholder: "16 hex chars", width: 180, required: true },
            { id: "name", label: "Display name", placeholder: "(optional)", width: 200 }
        ]
    }
}
