# frozen_string_literal: true

DiscourseZoteroBridge::Engine.routes.draw do
  get "/usage" => "config#usage"
  post "/v1/chat/completions" => "proxy#chat_completions"
end

Discourse::Application.routes.draw { mount ::DiscourseZoteroBridge::Engine, at: "zotero-bridge" }
