# frozen_string_literal: true

DiscourseZoteroBridge::Engine.routes.draw do
  get "/usage" => "config#usage"
  post "/request_extra_quota" => "config#request_extra_quota"
  get "/download/latest" => "config#download_latest"
  post "/v1/chat/completions" => "proxy#chat_completions"
end

Discourse::Application.routes.draw { mount ::DiscourseZoteroBridge::Engine, at: "zotero-bridge" }
