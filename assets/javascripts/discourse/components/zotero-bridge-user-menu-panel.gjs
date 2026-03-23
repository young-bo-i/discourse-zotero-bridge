import Component from "@glimmer/component";
import { tracked } from "@glimmer/tracking";
import { action } from "@ember/object";
import { service } from "@ember/service";
import DButton from "discourse/components/d-button";
import icon from "discourse/helpers/d-icon";
import { ajax } from "discourse/lib/ajax";
import { popupAjaxError } from "discourse/lib/ajax-error";
import { i18n } from "discourse-i18n";

export default class ZoteroBridgeUserMenuPanel extends Component {
  @service router;

  @tracked usageData = null;
  @tracked jnlData = null;
  @tracked loading = false;
  @tracked error = null;

  constructor() {
    super(...arguments);
    this.loadData();
  }

  get translateProgressPercent() {
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

  get translateProgressClass() {
    const pct = this.translateProgressPercent;
    if (pct >= 90) {
      return "critical";
    }
    if (pct >= 70) {
      return "warning";
    }
    return "normal";
  }

  @action
  async loadData() {
    this.loading = true;
    this.error = null;
    try {
      const [usage, jnl] = await Promise.all([
        ajax("/zotero-bridge/usage"),
        ajax("/zotero-bridge/jnl/usage"),
      ]);
      this.usageData = usage;
      this.jnlData = jnl;
    } catch (e) {
      this.error = true;
      popupAjaxError(e);
    } finally {
      this.loading = false;
    }
  }

  @action
  goToMarketplace() {
    this.router.transitionTo("zoteroBridgeMarketplace");
  }

  <template>
    <div class="zotero-bridge-panel">
      <div class="zotero-bridge-panel__header">
        <img
          src="/plugins/discourse-zotero-bridge/images/logo.png"
          alt=""
          class="zotero-bridge-panel__logo"
        />
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
            @action={{this.loadData}}
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
          <span class="zotero-bridge-panel__value zotero-bridge-panel__tl-badge">
            {{i18n
              "zotero_bridge.trust_level_badge"
              level=this.usageData.trust_level
            }}
          </span>
        </div>

        <div class="zotero-bridge-panel__gateway-section">
          <div class="zotero-bridge-panel__gateway">
            <div class="zotero-bridge-panel__gateway-header">
              {{icon "globe"}}
              <span>{{i18n "zotero_bridge.panel.translate_label"}}</span>
              <span class="zotero-bridge-panel__gateway-numbers">
                {{this.usageData.used_today}}
                /
                {{this.usageData.daily_quota}}
              </span>
            </div>
            <div class="zotero-bridge-panel__progress-bar">
              <div
                class="zotero-bridge-panel__progress-fill
                  {{this.translateProgressClass}}"
                style="width: {{this.translateProgressPercent}}%"
              ></div>
            </div>
          </div>

          <div class="zotero-bridge-panel__gateway">
            <div class="zotero-bridge-panel__gateway-header">
              {{icon "book-open-reader"}}
              <span>{{i18n "zotero_bridge.panel.journal_label"}}</span>
              <span class="zotero-bridge-panel__gateway-numbers">
                {{i18n
                  "zotero_bridge.panel.journal_count"
                  count=this.jnlData.used_today
                }}
              </span>
            </div>
          </div>
        </div>

        <div class="zotero-bridge-panel__reset-hint">
          {{icon "clock"}}
          {{i18n "zotero_bridge.reset_hint"}}
        </div>
      {{/if}}

      <div class="zotero-bridge-panel__marketplace-link">
        <DButton
          @action={{this.goToMarketplace}}
          @icon="store"
          @label="zotero_bridge.panel.view_all_plugins"
          class="btn-default btn-small zotero-bridge-panel__marketplace-btn"
        />
      </div>
    </div>
  </template>
}
