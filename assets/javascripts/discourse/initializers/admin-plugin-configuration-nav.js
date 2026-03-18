import { withPluginApi } from "discourse/lib/plugin-api";

const PLUGIN_ID = "discourse-zotero-bridge";

export default {
  name: "zotero-bridge-admin-plugin-configuration-nav",

  initialize(container) {
    const currentUser = container.lookup("service:current-user");
    if (!currentUser || !currentUser.admin) {
      return;
    }

    withPluginApi((api) => {
      api.setAdminPluginIcon(PLUGIN_ID, "chart-bar");
      api.addAdminPluginConfigurationNav(PLUGIN_ID, [
        {
          label: "zotero_bridge.admin.dashboard",
          route: "adminPlugins.show.discourse-zotero-bridge-dashboard",
          description: "zotero_bridge.admin.dashboard_description",
        },
      ]);
    });
  },
};
