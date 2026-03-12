import { withPluginApi } from "discourse/lib/plugin-api";
import ZoteroBridgeHeaderIcon from "../components/zotero-bridge-header-icon";

export default {
  name: "zotero-bridge-header",

  initialize(container) {
    const siteSettings = container.lookup("service:site-settings");
    if (!siteSettings.discourse_zotero_bridge_enabled) {
      return;
    }

    withPluginApi((api) => {
      api.headerIcons.add("zotero-bridge", ZoteroBridgeHeaderIcon, {
        before: "search",
      });
    });
  },
};
