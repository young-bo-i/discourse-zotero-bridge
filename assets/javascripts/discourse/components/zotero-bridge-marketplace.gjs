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

const TL_KEYS = ["tl0", "tl1", "tl2", "tl3", "tl4"];
const MAX_VISIBLE_REQUIREMENTS = 3;

class PluginCard extends Component {
  @tracked requestingExtra = false;
  @tracked showGuide = false;
  @tracked showAllRequirements = false;
  @tracked localUsage = null;

  get plugin() {
    return this.args.plugin;
  }

  get isTranslate() {
    return this.plugin.id === "translate";
  }

  get cardIcon() {
    return this.isTranslate ? "globe" : "book-open-reader";
  }

  get usage() {
    return this.localUsage ?? this.plugin.usage;
  }

  get progressPercent() {
    if (!this.plugin.has_quota || !this.usage.daily_quota) {
      return 0;
    }
    return Math.min(
      100,
      Math.round((this.usage.used_today / this.usage.daily_quota) * 100)
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
    return this.plugin.has_quota && this.usage.remaining === 0;
  }

  get showExtraButton() {
    return this.quotaExhausted && this.usage.can_request_extra;
  }

  get quotaTiers() {
    const tiers = this.plugin.quota_tiers;
    if (!tiers) {
      return [];
    }
    return tiers.map((tier) => ({
      trust_level: tier.trust_level,
      daily_quota: tier.daily_quota,
      name: i18n(`zotero_bridge.quota_guide.tl_names.${TL_KEYS[tier.trust_level]}`),
      isCurrent: tier.trust_level === this.args.trustLevel,
    }));
  }

  get nextLevel() {
    const current = this.args.trustLevel;
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
    const reqs = this.plugin.next_level_requirements || [];
    return reqs.map((req) => {
      const hasProgress = req.current !== null && req.current !== undefined;
      let percent = 0;
      let met = false;
      if (hasProgress && req.value > 0) {
        percent = Math.min(100, Math.round((req.current / req.value) * 100));
        met = req.current >= req.value;
      }
      return { ...req, hasProgress, percent, met };
    });
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
  async requestExtraQuota() {
    this.requestingExtra = true;
    try {
      const result = await ajax("/zotero-bridge/request_extra_quota", {
        type: "POST",
      });
      if (result.success) {
        this.localUsage = {
          ...this.usage,
          daily_quota:
            this.usage.used_today +
            result.extra_granted +
            (this.usage.remaining || 0),
          remaining: (this.usage.remaining || 0) + result.extra_granted,
          extra_requests_used: result.extra_requests_used,
          extra_requests_max: result.extra_requests_max,
          can_request_extra: result.can_request_extra,
        };
      }
    } catch (e) {
      popupAjaxError(e);
    } finally {
      this.requestingExtra = false;
    }
  }

  <template>
    <div class="marketplace-card">
      <div class="marketplace-card__header">
        <div class="marketplace-card__icon">
          {{icon this.cardIcon}}
        </div>
        <div class="marketplace-card__title-area">
          <h3 class="marketplace-card__name">
            {{i18n (concat "zotero_bridge.marketplace.plugins." this.plugin.id ".name")}}
          </h3>
          <div class="marketplace-card__meta">
            {{i18n
              "zotero_bridge.marketplace.platform"
              platform=this.plugin.platform
            }}
          </div>
        </div>
      </div>

      <p class="marketplace-card__description">
        {{i18n (concat "zotero_bridge.marketplace.plugins." this.plugin.id ".description")}}
      </p>

      <div class="marketplace-card__usage">
        {{#if this.plugin.has_quota}}
          <div class="marketplace-card__usage-header">
            <span>{{i18n "zotero_bridge.marketplace.usage_today"}}</span>
            <span class="marketplace-card__usage-numbers">
              {{this.usage.used_today}}
              /
              {{this.usage.daily_quota}}
            </span>
          </div>
          <div class="marketplace-card__progress-bar">
            <div
              class="marketplace-card__progress-fill {{this.progressClass}}"
              style="width: {{this.progressPercent}}%"
            ></div>
          </div>
          <div class="marketplace-card__usage-detail">
            <span>{{i18n "zotero_bridge.remaining"}}</span>
            <span class="marketplace-card__remaining">{{this.usage.remaining}}</span>
          </div>
          <div class="marketplace-card__usage-hint">
            {{icon "clock"}}
            {{i18n "zotero_bridge.reset_hint"}}
          </div>
        {{else}}
          <div class="marketplace-card__usage-header">
            <span>{{i18n "zotero_bridge.marketplace.usage_today"}}</span>
            <span class="marketplace-card__usage-numbers">
              {{i18n
                "zotero_bridge.marketplace.queries_count"
                count=this.usage.used_today
              }}
            </span>
          </div>
          <div class="marketplace-card__usage-hint">
            {{i18n "zotero_bridge.marketplace.no_quota_limit"}}
          </div>
        {{/if}}
      </div>

      {{#if this.plugin.has_quota}}
        {{#if this.quotaExhausted}}
          <div class="marketplace-card__extra-quota">
            {{#if this.showExtraButton}}
              <div class="marketplace-card__extra-hint">
                {{i18n
                  "zotero_bridge.extra_quota_hint"
                  used=this.usage.extra_requests_used
                  max=this.usage.extra_requests_max
                }}
              </div>
              <DButton
                @action={{this.requestExtraQuota}}
                @label="zotero_bridge.request_extra_quota"
                @disabled={{this.requestingExtra}}
                class="btn-primary marketplace-card__extra-btn"
              />
            {{else}}
              <div class="marketplace-card__extra-exhausted">
                {{i18n "zotero_bridge.extra_quota_exhausted"}}
              </div>
            {{/if}}
          </div>
        {{/if}}

        <div class="marketplace-card__guide-section">
          <button
            type="button"
            class="marketplace-card__guide-toggle btn-transparent"
            {{on "click" this.toggleGuide}}
          >
            {{icon "circle-question"}}
            <span>{{i18n "zotero_bridge.quota_guide.toggle"}}</span>
          </button>

          {{#if this.showGuide}}
            <div class="marketplace-card__guide">
              <div class="marketplace-card__guide-title">
                {{i18n "zotero_bridge.quota_guide.title"}}
              </div>

              <ul class="marketplace-card__guide-tiers">
                {{#each this.quotaTiers as |tier|}}
                  <li
                    class={{concatClass
                      "marketplace-card__guide-tier"
                      (if tier.isCurrent "--current")
                    }}
                  >
                    <span class="marketplace-card__guide-tier-label">
                      <span class="marketplace-card__guide-tier-badge">TL{{tier.trust_level}}</span>
                      {{tier.name}}
                      {{#if tier.isCurrent}}
                        <span class="marketplace-card__guide-current-tag">
                          {{i18n "zotero_bridge.quota_guide.current_label"}}
                        </span>
                      {{/if}}
                    </span>
                    <span class="marketplace-card__guide-tier-quota">
                      {{i18n "zotero_bridge.quota_guide.per_day" count=tier.daily_quota}}
                    </span>
                  </li>
                {{/each}}
              </ul>

              <div class="marketplace-card__guide-tips">
                {{#if this.nextLevel}}
                  <div class="marketplace-card__guide-tips-title">
                    {{i18n
                      "zotero_bridge.quota_guide.next_level"
                      level_name=this.nextLevelName
                    }}
                  </div>
                  <ul class="marketplace-card__guide-requirements">
                    {{#each this.visibleRequirements as |req|}}
                      <li
                        class={{concatClass
                          "marketplace-card__guide-requirement"
                          (if req.met "--met")
                        }}
                      >
                        <div class="marketplace-card__guide-requirement-header">
                          <span class="marketplace-card__guide-requirement-label">
                            {{i18n
                              (concat
                                "zotero_bridge.quota_guide.requirement_labels."
                                req.key
                              )
                            }}
                          </span>
                          {{#if req.hasProgress}}
                            <span class="marketplace-card__guide-requirement-nums">
                              {{req.current}} / {{req.value}}
                            </span>
                          {{else}}
                            <strong class="marketplace-card__guide-requirement-value">
                              {{req.value}}
                            </strong>
                          {{/if}}
                        </div>
                        {{#if req.hasProgress}}
                          <div class="marketplace-card__guide-requirement-bar">
                            <div
                              class={{concatClass
                                "marketplace-card__guide-requirement-fill"
                                (if req.met "--met")
                              }}
                              style="width: {{req.percent}}%"
                            ></div>
                          </div>
                        {{/if}}
                      </li>
                    {{/each}}
                  </ul>
                  {{#if this.hasMoreRequirements}}
                    {{#unless this.showAllRequirements}}
                      <button
                        type="button"
                        class="marketplace-card__guide-show-more btn-transparent"
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
                  <p class="marketplace-card__guide-max">
                    {{i18n "zotero_bridge.quota_guide.already_max"}}
                  </p>
                {{/if}}
              </div>
            </div>
          {{/if}}
        </div>
      {{/if}}

      <div class="marketplace-card__links">
        {{#if this.plugin.github_url}}
          <a
            href={{this.plugin.github_url}}
            target="_blank"
            rel="noopener noreferrer"
            class="marketplace-card__link"
          >
            {{icon "fab-github"}}
            <span>{{i18n "zotero_bridge.marketplace.source_code"}}</span>
            {{icon "arrow-up-right-from-square"}}
          </a>
        {{/if}}
        {{#if this.plugin.download_url}}
          <a
            href={{this.plugin.download_url}}
            download
            data-auto-route="true"
            class="marketplace-card__link marketplace-card__link--download"
          >
            {{icon "download"}}
            <span>{{i18n "zotero_bridge.marketplace.download_plugin"}}</span>
          </a>
        {{/if}}
        {{#unless this.plugin.github_url}}
          {{#unless this.plugin.download_url}}
            <div class="marketplace-card__coming-soon">
              {{i18n "zotero_bridge.marketplace.coming_soon"}}
            </div>
          {{/unless}}
        {{/unless}}
      </div>
    </div>
  </template>
}

export default class ZoteroBridgeMarketplace extends Component {
  get plugins() {
    return this.args.model?.plugins || [];
  }

  get username() {
    return this.args.model?.username;
  }

  get trustLevel() {
    return this.args.model?.trust_level;
  }

  <template>
    <div class="zotero-bridge-marketplace">
      <div class="zotero-bridge-marketplace__header">
        <img
          src="/plugins/discourse-zotero-bridge/images/logo.png"
          alt=""
          class="zotero-bridge-marketplace__logo"
        />
        <div class="zotero-bridge-marketplace__header-text">
          <h1>{{i18n "zotero_bridge.marketplace.title"}}</h1>
          <p>{{i18n "zotero_bridge.marketplace.description"}}</p>
        </div>
      </div>

      <div class="zotero-bridge-marketplace__user-info">
        <span>{{this.username}}</span>
        <span class="zotero-bridge-marketplace__tl-badge">
          {{i18n "zotero_bridge.trust_level_badge" level=this.trustLevel}}
        </span>
      </div>

      <div class="zotero-bridge-marketplace__grid">
        {{#each this.plugins as |plugin|}}
          <PluginCard @plugin={{plugin}} @trustLevel={{this.trustLevel}} />
        {{/each}}
      </div>
    </div>
  </template>
}
