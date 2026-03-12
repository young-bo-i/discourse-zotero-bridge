import Component from "@glimmer/component";
import { tracked } from "@glimmer/tracking";
import { action } from "@ember/object";
import { service } from "@ember/service";
import DButton from "discourse/components/d-button";
import icon from "discourse/helpers/d-icon";
import { ajax } from "discourse/lib/ajax";
import { popupAjaxError } from "discourse/lib/ajax-error";
import { i18n } from "discourse-i18n";
import DMenu from "float-kit/components/d-menu";

export default class ZoteroBridgeHeaderIcon extends Component {
  @service currentUser;
  @service siteSettings;

  @tracked usageData = null;
  @tracked loading = false;
  @tracked error = null;

  get shouldDisplay() {
    return (
      this.currentUser && this.siteSettings.discourse_zotero_bridge_enabled
    );
  }

  get progressPercent() {
    if (!this.usageData || this.usageData.daily_quota === 0) {
      return 0;
    }
    return Math.min(
      100,
      Math.round(
        (this.usageData.used_today / this.usageData.daily_quota) * 100
      )
    );
  }

  get progressClass() {
    const pct = this.progressPercent;
    if (pct >= 90) {
      return "critical";
    }
    if (pct >= 70) {
      return "warning";
    }
    return "normal";
  }

  @action
  async loadUsage() {
    this.loading = true;
    this.error = null;
    try {
      this.usageData = await ajax("/zotero-bridge/usage");
    } catch (e) {
      this.error = true;
      popupAjaxError(e);
    } finally {
      this.loading = false;
    }
  }

  <template>
    {{#if this.shouldDisplay}}
      <li class="header-dropdown-toggle zotero-bridge-header-icon">
        <DMenu
          @icon="chart-bar"
          @title={{i18n "zotero_bridge.header_title"}}
          @identifier="zotero-bridge-usage"
          @onShow={{this.loadUsage}}
        >
          <:content>
            <div class="zotero-bridge-panel">
              <div class="zotero-bridge-panel__header">
                {{icon "chart-bar"}}
                <span>{{i18n "zotero_bridge.panel_title"}}</span>
              </div>

              {{#if this.loading}}
                <div class="zotero-bridge-panel__loading">
                  <div class="spinner small"></div>
                </div>
              {{else if this.error}}
                <div class="zotero-bridge-panel__error">
                  {{i18n "zotero_bridge.load_error"}}
                  <DButton
                    @action={{this.loadUsage}}
                    @label="zotero_bridge.retry"
                    class="btn-small btn-default"
                  />
                </div>
              {{else if this.usageData}}
                <div class="zotero-bridge-panel__user">
                  <span class="zotero-bridge-panel__label">{{i18n
                      "zotero_bridge.username"
                    }}</span>
                  <span
                    class="zotero-bridge-panel__value"
                  >{{this.usageData.username}}</span>
                </div>

                <div class="zotero-bridge-panel__trust">
                  <span class="zotero-bridge-panel__label">{{i18n
                      "zotero_bridge.trust_level"
                    }}</span>
                  <span class="zotero-bridge-panel__value zotero-bridge-panel__tl-badge">TL{{this.usageData.trust_level}}</span>
                </div>

                <div class="zotero-bridge-panel__progress-section">
                  <div class="zotero-bridge-panel__quota-text">
                    <span>{{i18n "zotero_bridge.used_today"}}</span>
                    <span class="zotero-bridge-panel__numbers">
                      {{this.usageData.used_today}}
                      /
                      {{this.usageData.daily_quota}}
                    </span>
                  </div>
                  <div class="zotero-bridge-panel__progress-bar">
                    <div
                      class="zotero-bridge-panel__progress-fill
                        {{this.progressClass}}"
                      style="width: {{this.progressPercent}}%"
                    ></div>
                  </div>
                </div>

                <div class="zotero-bridge-panel__remaining">
                  <span class="zotero-bridge-panel__label">{{i18n
                      "zotero_bridge.remaining"
                    }}</span>
                  <span
                    class="zotero-bridge-panel__value zotero-bridge-panel__remaining-count"
                  >{{this.usageData.remaining}}</span>
                </div>

                <div class="zotero-bridge-panel__reset-hint">
                  {{icon "clock"}}
                  {{i18n "zotero_bridge.reset_hint"}}
                </div>
              {{/if}}
            </div>
          </:content>
        </DMenu>
      </li>
    {{/if}}
  </template>
}
