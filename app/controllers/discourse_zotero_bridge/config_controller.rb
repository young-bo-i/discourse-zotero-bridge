# frozen_string_literal: true

module DiscourseZoteroBridge
  class ConfigController < ::ApplicationController
    requires_plugin PLUGIN_NAME
    requires_login

    def show
      result = UsageLog.increment_and_check!(current_user)

      unless result[:allowed]
        return(
          render json: {
                   error: I18n.t("zotero_bridge.errors.quota_exceeded"),
                   used_today: result[:used],
                   daily_quota: result[:quota],
                 },
                 status: 429
        )
      end

      render json: {
               endpoint: SiteSetting.zotero_bridge_llm_endpoint,
               api_key: SiteSetting.zotero_bridge_llm_api_key,
               model_name: SiteSetting.zotero_bridge_llm_model_name,
               daily_quota: result[:quota],
               used_today: result[:used],
               remaining: result[:quota] - result[:used],
             }
    end

    def usage
      summary = UsageLog.usage_summary(current_user)

      render json: {
               trust_level: summary[:trust_level],
               daily_quota: summary[:daily_quota],
               used_today: summary[:used_today],
               remaining: summary[:remaining],
               username: current_user.username,
             }
    end
  end
end
