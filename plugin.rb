# frozen_string_literal: true

# name: discourse-zotero-bridge
# about: Proxies LLM requests for Zotero browser extension with per-user daily quota
# version: 0.2.0
# authors: Discourse
# url: https://github.com/discourse/discourse-zotero-bridge
# meta_topic_id: 0

enabled_site_setting :discourse_zotero_bridge_enabled

register_asset "stylesheets/zotero-bridge-panel.scss"

register_svg_icon "chart-bar"
register_svg_icon "fab-github"
register_svg_icon "download"
register_svg_icon "plug"

module ::DiscourseZoteroBridge
  PLUGIN_NAME = "discourse-zotero-bridge"
end

require_relative "lib/discourse_zotero_bridge/engine"

after_initialize do
  add_user_api_key_scope(
    :zotero_bridge,
    methods: %i[get post],
    actions: %w[discourse_zotero_bridge/config#usage discourse_zotero_bridge/proxy#chat_completions],
  )

  module ::Jobs
    class CleanUpZoteroBridgeUsageLogs < ::Jobs::Scheduled
      every 1.day

      def execute(args)
        return unless SiteSetting.discourse_zotero_bridge_enabled
        DiscourseZoteroBridge::UsageLog.where("used_on < ?", 90.days.ago).delete_all
      end
    end
  end
end
