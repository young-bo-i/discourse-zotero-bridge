import { ajax } from "discourse/lib/ajax";
import DiscourseRoute from "discourse/routes/discourse";

export default class DiscourseZoteroBridgeDashboardRoute extends DiscourseRoute {
  model() {
    return ajax("/admin/plugins/discourse-zotero-bridge/dashboard.json");
  }
}
