import Component from "@glimmer/component";
import { tracked } from "@glimmer/tracking";
import { concat } from "@ember/helper";
import { on } from "@ember/modifier";
import { action } from "@ember/object";
import DButton from "discourse/components/d-button";
import concatClass from "discourse/helpers/concat-class";
import icon from "discourse/helpers/d-icon";
import { ajax } from "discourse/lib/ajax";
import { popupAjaxError } from "discourse/lib/ajax-error";
import { i18n } from "discourse-i18n";

const GITHUB_URL = "https://github.com/young-bo-i/zotero-enterscholar";
const DOWNLOAD_URL = "/zotero-bridge/download/latest";
const TL_KEYS = ["tl0", "tl1", "tl2", "tl3", "tl4"];
const TRUST_LEVEL_BLOG_URL =
  "https://blog.discourse.org/2018/06/understanding-discourse-trust-levels/";
const MAX_VISIBLE_REQUIREMENTS = 3;

export default class ZoteroBridgeUserMenuPanel extends Component {
  @tracked usageData = null;
  @tracked loading = false;
  @tracked error = null;
  @tracked requestingExtra = false;
  @tracked showGuide = false;
  @tracked showAllRequirements = false;

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

  get quotaTiers() {
    const tiers = this.usageData?.quota_tiers;
    if (!tiers) {
      return [];
    }
    return tiers.map((tier) => ({
      trust_level: tier.trust_level,
      daily_quota: tier.daily_quota,
      name: i18n(`zotero_bridge.quota_guide.tl_names.${TL_KEYS[tier.trust_level]}`),
      isCurrent: tier.trust_level === this.usageData.trust_level,
    }));
  }

  get nextLevel() {
    const current = this.usageData?.trust_level;
    if (current === undefined || current >= 4) {
      return null;
    }
    return current + 1;
  }

  get nextLevelName() {
    const next = this.nextLevel;
    if (next === null) {
      return null;
    }
    return i18n(`zotero_bridge.quota_guide.tl_names.${TL_KEYS[next]}`);
  }

  get nextLevelRequirements() {
    return this.usageData?.next_level_requirements || [];
  }

  get visibleRequirements() {
    if (this.showAllRequirements) {
      return this.nextLevelRequirements;
    }
    return this.nextLevelRequirements.slice(0, MAX_VISIBLE_REQUIREMENTS);
  }

  get hasMoreRequirements() {
    return this.nextLevelRequirements.length > MAX_VISIBLE_REQUIREMENTS;
  }

  get hiddenRequirementsCount() {
    return this.nextLevelRequirements.length - MAX_VISIBLE_REQUIREMENTS;
  }

  @action
  toggleGuide() {
    this.showGuide = !this.showGuide;
  }

  @action
  toggleAllRequirements() {
    this.showAllRequirements = !this.showAllRequirements;
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
          <span class="zotero-bridge-panel__trust-right">
            <span
              class="zotero-bridge-panel__value zotero-bridge-panel__tl-badge"
            >{{i18n
                "zotero_bridge.trust_level_badge"
                level=this.usageData.trust_level
              }}</span>
            <button
              type="button"
              class="zotero-bridge-panel__guide-toggle btn-transparent"
              title={{i18n "zotero_bridge.quota_guide.toggle"}}
              {{on "click" this.toggleGuide}}
            >
              {{icon "circle-question"}}
            </button>
          </span>
        </div>

        {{#if this.showGuide}}
          <div class="zotero-bridge-panel__guide">
            <div class="zotero-bridge-panel__guide-title">
              {{i18n "zotero_bridge.quota_guide.title"}}
            </div>

            <ul class="zotero-bridge-panel__guide-tiers">
              {{#each this.quotaTiers as |tier|}}
                <li
                  class={{concatClass
                    "zotero-bridge-panel__guide-tier"
                    (if tier.isCurrent "--current")
                  }}
                >
                  <span class="zotero-bridge-panel__guide-tier-label">
                    <span
                      class="zotero-bridge-panel__guide-tier-badge"
                    >TL{{tier.trust_level}}</span>
                    {{tier.name}}
                    {{#if tier.isCurrent}}
                      <span
                        class="zotero-bridge-panel__guide-current-tag"
                      >{{i18n "zotero_bridge.quota_guide.current_label"}}</span>
                    {{/if}}
                  </span>
                  <span class="zotero-bridge-panel__guide-tier-quota">
                    {{i18n
                      "zotero_bridge.quota_guide.per_day"
                      count=tier.daily_quota
                    }}
                  </span>
                </li>
              {{/each}}
            </ul>

            <div class="zotero-bridge-panel__guide-tips">
              {{#if this.nextLevel}}
                <div class="zotero-bridge-panel__guide-tips-title">
                  {{i18n
                    "zotero_bridge.quota_guide.next_level"
                    level_name=this.nextLevelName
                  }}
                </div>
                <ul class="zotero-bridge-panel__guide-requirements">
                  {{#each this.visibleRequirements as |req|}}
                    <li class="zotero-bridge-panel__guide-requirement">
                      <span class="zotero-bridge-panel__guide-requirement-label">
                        {{i18n
                          (concat
                            "zotero_bridge.quota_guide.requirement_labels."
                            req.key
                          )
                        }}
                      </span>
                      <strong
                        class="zotero-bridge-panel__guide-requirement-value"
                      >{{req.value}}</strong>
                    </li>
                  {{/each}}
                </ul>
                {{#if this.hasMoreRequirements}}
                  {{#unless this.showAllRequirements}}
                    <button
                      type="button"
                      class="zotero-bridge-panel__guide-show-more btn-transparent"
                      {{on "click" this.toggleAllRequirements}}
                    >
                      {{i18n
                        "zotero_bridge.quota_guide.show_more"
                        count=this.hiddenRequirementsCount
                      }}
                    </button>
                  {{/unless}}
                {{/if}}
              {{else}}
                <p class="zotero-bridge-panel__guide-tips-text --max">
                  {{i18n "zotero_bridge.quota_guide.already_max"}}
                </p>
              {{/if}}
            </div>

            <a
              href={{TRUST_LEVEL_BLOG_URL}}
              target="_blank"
              rel="noopener noreferrer"
              class="zotero-bridge-panel__guide-learn-more"
            >
              {{icon "book-open-reader"}}
              {{i18n "zotero_bridge.quota_guide.learn_more"}}
              {{icon "arrow-up-right-from-square"}}
            </a>
          </div>
        {{/if}}

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
