export default {
  resource: "admin.adminPlugins.show",
  path: "/plugins",
  map() {
    this.route("discourse-zotero-bridge-dashboard", { path: "dashboard" });
  },
};
