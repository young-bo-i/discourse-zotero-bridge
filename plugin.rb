# frozen_string_literal: true

# name: discourse-zotero-bridge
# about: Provides LLM configuration to Zotero browser extension via authenticated API
# version: 0.1.0
# authors: Discourse
# url: https://github.com/discourse/discourse-zotero-bridge
# meta_topic_id: 0

enabled_site_setting :discourse_zotero_bridge_enabled

register_asset "stylesheets/zotero-bridge-panel.scss"

register_svg_icon "chart-bar"

module ::DiscourseZoteroBridge
  PLUGIN_NAME = "discourse-zotero-bridge"
end

require_relative "lib/discourse_zotero_bridge/engine"

after_initialize do
  add_user_api_key_scope(
    :zotero_bridge,
    methods: :get,
    actions: %w[discourse_zotero_bridge/config#show discourse_zotero_bridge/config#usage],
  )
end
