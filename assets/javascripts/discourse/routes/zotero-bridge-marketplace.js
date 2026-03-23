import Route from "@ember/routing/route";
import { ajax } from "discourse/lib/ajax";

export default class ZoteroBridgeMarketplaceRoute extends Route {
  async model() {
    return ajax("/zotero-bridge/marketplace");
  }
}
