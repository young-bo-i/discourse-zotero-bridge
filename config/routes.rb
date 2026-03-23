# frozen_string_literal: true

DiscourseZoteroBridge::Engine.routes.draw do
  get "/usage" => "config#usage"
  post "/request_extra_quota" => "config#request_extra_quota"
  get "/download/latest" => "config#download_latest"
  post "/v1/chat/completions" => "proxy#chat_completions"
  post "/v1/jnl/query" => "journal_proxy#query"
end

Discourse::Application.routes.draw do
  mount ::DiscourseZoteroBridge::Engine, at: "zotero-bridge"

  scope "/admin/plugins/discourse-zotero-bridge", constraints: AdminConstraint.new do
    get "/dashboard" => "discourse_zotero_bridge/admin/dashboard#show"
    get "/dashboard/users" => "discourse_zotero_bridge/admin/dashboard#users"
    get "/dashboard/journal" => "discourse_zotero_bridge/admin/dashboard#journal_show"
    get "/dashboard/journal/users" => "discourse_zotero_bridge/admin/dashboard#journal_users"
  end
end
