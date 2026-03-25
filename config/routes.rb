# frozen_string_literal: true

DiscourseZoteroBridge::Engine.routes.draw do
  get "/usage" => "config#usage"
  get "/jnl/usage" => "config#jnl_usage"
  get "/babeldoc/usage" => "config#babeldoc_usage"
  get "/marketplace" => "config#marketplace"
  post "/request_extra_quota" => "config#request_extra_quota"
  post "/request_babeldoc_extra_quota" => "config#request_babeldoc_extra_quota"
  get "/download/latest" => "config#download_latest"
  get "/download/journal/latest" => "config#download_journal_latest"
  get "/download/babeldoc/latest" => "config#download_babeldoc_latest"
  post "/v1/chat/completions" => "proxy#chat_completions"
  post "/v1/jnl/query" => "journal_proxy#query"

  get "/v1/babeldoc/connectivity_check" => "babeldoc_proxy#connectivity_check"
  get "/v1/babeldoc/check-key" => "babeldoc_proxy#check_key"
  get "/v1/babeldoc/pdf-upload-url" => "babeldoc_proxy#pdf_upload_url"
  put "/v1/babeldoc/upload/:object_key" => "babeldoc_proxy#upload"
  post "/v1/babeldoc/translate" => "babeldoc_proxy#translate"
  get "/v1/babeldoc/pdf/record-list" => "babeldoc_proxy#record_list"
  get "/v1/babeldoc/pdf-count" => "babeldoc_proxy#pdf_count"
  get "/v1/babeldoc/pdf/:pdf_id/process" => "babeldoc_proxy#process_status"
  get "/v1/babeldoc/pdf/:pdf_id/temp-url" => "babeldoc_proxy#temp_url"
  get "/v1/babeldoc/download/:pdf_id/*path" => "babeldoc_proxy#download"
end

Discourse::Application.routes.draw do
  mount ::DiscourseZoteroBridge::Engine, at: "zotero-bridge"

  scope "/admin/plugins/discourse-zotero-bridge", constraints: AdminConstraint.new do
    get "/dashboard" => "discourse_zotero_bridge/admin/dashboard#show"
    get "/dashboard/users" => "discourse_zotero_bridge/admin/dashboard#users"
    get "/dashboard/journal" => "discourse_zotero_bridge/admin/dashboard#journal_show"
    get "/dashboard/journal/users" => "discourse_zotero_bridge/admin/dashboard#journal_users"
    get "/dashboard/babeldoc" => "discourse_zotero_bridge/admin/dashboard#babeldoc_show"
    get "/dashboard/babeldoc/users" => "discourse_zotero_bridge/admin/dashboard#babeldoc_users"
  end
end
