pragma Singleton

import Quickshell
import Quickshell.Io
import Quickshell.Wayland

Singleton {
    id: root

    property alias enabled: props.enabled
    readonly property alias enabledSince: props.enabledSince

    onEnabledChanged: {
        if (enabled)
            props.enabledSince = new Date();
    }

    PersistentProperties {
        id: props

        property bool enabled
        property date enabledSince

        reloadableId: "idleInhibitor"
    }

    IdleInhibitor {
        enabled: props.enabled
        window: PanelWindow {
            implicitWidth: 0
            implicitHeight: 0
            color: "transparent"
            mask: Region {}
        }
    }

    // [macos] the switch says "Block sleep" too: hold a logind sleep lock while it's on.
    // `cat` on our stdin pipe, not `sleep infinity`: Quickshell leaves children running when it is
    // killed or crashes, so the lock outlived the shell; cat ends at EOF once the shell is gone.
    // handle-lid-switch: logind's lid suspend ignores sleep locks (LidSwitchIgnoreInhibited), so take the lid
    // over too — the laptop keeps running, unlocked, with the lid closed (hypr-qol.lua turns the panel off)
    Process {
        running: props.enabled
        stdinEnabled: true
        command: ["systemd-inhibit", "--what=idle:sleep:handle-lid-switch", "--who=Caelestia", "--why=Block sleep and screen locking switch (lid closed too)", "--mode=block", "cat"]
    }

    IpcHandler {
        function isEnabled(): bool {
            return props.enabled;
        }

        function toggle(): void {
            props.enabled = !props.enabled;
        }

        function enable(): void {
            props.enabled = true;
        }

        function disable(): void {
            props.enabled = false;
        }

        target: "idleInhibitor"
    }
}
