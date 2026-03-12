import { withPluginApi } from "discourse/lib/plugin-api";
import ZoteroBridgeUserMenuPanel from "../components/zotero-bridge-user-menu-panel";

export default {
  name: "zotero-bridge-user-menu",

  initialize() {
    withPluginApi((api) => {
      api.registerUserMenuTab((UserMenuTab) => {
        return class extends UserMenuTab {
          id = "zotero-bridge";
          panelComponent = ZoteroBridgeUserMenuPanel;
          icon = "chart-bar";

          get shouldDisplay() {
            return this.siteSettings.discourse_zotero_bridge_enabled;
          }
        };
      });
    });
  },
};
