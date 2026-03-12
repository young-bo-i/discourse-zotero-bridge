# frozen_string_literal: true

DiscourseZoteroBridge::Engine.routes.draw do
  get "/config" => "config#show"
  get "/usage" => "config#usage"
end

Discourse::Application.routes.draw { mount ::DiscourseZoteroBridge::Engine, at: "zotero-bridge" }
