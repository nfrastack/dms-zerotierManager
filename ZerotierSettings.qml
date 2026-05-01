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
        text: "Show ZeroTier network status in the bar; join/leave/route from the popout."
        font.pixelSize: Theme.fontSizeSmall
        color: Theme.surfaceVariantText
        wrapMode: Text.WordWrap
    }

    StringSetting {
        settingKey: "zerotierBinary"
        label: "zerotier-cli binary"
        description: "Path or name of the zerotier-cli binary. Bare name uses PATH; full path also works."
        defaultValue: "zerotier-cli"
        placeholder: "zerotier-cli"
    }

    ToggleSetting {
        settingKey: "useSudo"
        label: "Run with sudo -n"
        description: "Prepend 'sudo -n' to zerotier-cli calls. Requires passwordless sudo for zerotier-cli (NOPASSWD in sudoers); the '-n' flag means non-interactive — sudo will fail rather than prompt for a password."
        defaultValue: true
    }

    SliderSetting {
        settingKey: "refreshInterval"
        label: "Refresh interval"
        description: "How often to poll ZeroTier for status updates."
        defaultValue: 5
        minimum: 1
        maximum: 60
        unit: "s"
        leftIcon: "schedule"
    }

    StringSetting {
        settingKey: "knownNetworksFile"
        label: "Known networks file (managed)"
        description: "GUI-managed file of networks to remember when not joined. Format: '<nwid> <name>' per line. Lines starting with # are ignored. Leave blank to use ~/.config/zerotier/known-zt-networks"
        defaultValue: ""
        placeholder: "~/.config/zerotier/known-zt-networks"
    }

    StringSetting {
        settingKey: "extraNetworksFile"
        label: "Extra networks file (read-only)"
        description: "Optional second file merged into the network list. Same format as the known-networks file. Plugin never writes to this file. Duplicates with the known file are deduped by network ID."
        defaultValue: ""
        placeholder: ""
    }

    ToggleSetting {
        settingKey: "autoAdd"
        label: "Auto-add joined networks"
        description: "When you join a network outside the plugin, automatically add it to the known-networks file (the managed one) so it shows up here even after you leave it."
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
