import Component from "@glimmer/component";
import { tracked } from "@glimmer/tracking";
import { action } from "@ember/object";
import { service } from "@ember/service";
import DButton from "discourse/components/d-button";
import icon from "discourse/helpers/d-icon";
import { ajax } from "discourse/lib/ajax";
import { popupAjaxError } from "discourse/lib/ajax-error";
import { i18n } from "discourse-i18n";

const GITHUB_URL = "https://github.com/young-bo-i/zotero-enterscholar";
const DOWNLOAD_URL = "/zotero-bridge/download/latest";

export default class ZoteroBridgeUserMenuPanel extends Component {
  @service currentUser;

  @tracked usageData = null;
  @tracked loading = false;
  @tracked error = null;
  @tracked requestingExtra = false;

  constructor() {
    super(...arguments);
    this.loadUsage();
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

  get quotaExhausted() {
    return this.usageData && this.usageData.remaining === 0;
  }

  get showExtraButton() {
    return this.quotaExhausted && this.usageData?.can_request_extra;
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

  @action
  async requestExtraQuota() {
    this.requestingExtra = true;
    try {
      const result = await ajax("/zotero-bridge/request_extra_quota", {
        type: "POST",
      });
      if (result.success) {
        await this.loadUsage();
      }
    } catch (e) {
      popupAjaxError(e);
    } finally {
      this.requestingExtra = false;
    }
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
          <span
            class="zotero-bridge-panel__value zotero-bridge-panel__tl-badge"
          >{{i18n
              "zotero_bridge.trust_level_badge"
              level=this.usageData.trust_level
            }}</span>
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

        {{#if this.quotaExhausted}}
          <div class="zotero-bridge-panel__extra-quota">
            {{#if this.showExtraButton}}
              <div class="zotero-bridge-panel__extra-hint">
                {{i18n
                  "zotero_bridge.extra_quota_hint"
                  used=this.usageData.extra_requests_used
                  max=this.usageData.extra_requests_max
                }}
              </div>
              <DButton
                @action={{this.requestExtraQuota}}
                @label="zotero_bridge.request_extra_quota"
                @disabled={{this.requestingExtra}}
                class="btn-primary zotero-bridge-panel__extra-btn"
              />
            {{else}}
              <div class="zotero-bridge-panel__extra-exhausted">
                {{i18n "zotero_bridge.extra_quota_exhausted"}}
              </div>
            {{/if}}
          </div>
        {{/if}}
      {{/if}}

      <div class="zotero-bridge-panel__links">
        <div class="zotero-bridge-panel__links-header">
          {{icon "plug"}}
          <span>{{i18n "zotero_bridge.zotero_plugin"}}</span>
        </div>
        <a
          href={{GITHUB_URL}}
          target="_blank"
          rel="noopener noreferrer"
          class="zotero-bridge-panel__link"
        >
          {{icon "fab-github"}}
          <span>{{i18n "zotero_bridge.github_project"}}</span>
        </a>
        <a
          href={{DOWNLOAD_URL}}
          download
          data-auto-route="true"
          class="zotero-bridge-panel__link"
        >
          {{icon "download"}}
          <span>{{i18n "zotero_bridge.plugin_download"}}</span>
        </a>
      </div>
    </div>
  </template>
}
