# frozen_string_literal: true

RSpec.describe DiscourseZoteroBridge::ConfigController do
  fab!(:user) { Fabricate(:user, trust_level: 2) }

  before do
    SiteSetting.discourse_zotero_bridge_enabled = true
    SiteSetting.zotero_bridge_llm_endpoint = "https://api.openai.com/v1/chat/completions"
    SiteSetting.zotero_bridge_llm_api_key = "sk-test-key-123"
    SiteSetting.zotero_bridge_llm_model_name = "gpt-4o"
    SiteSetting.zotero_bridge_daily_quota_tl2 = 100
  end

  describe "GET /zotero-bridge/config" do
    it "requires authentication" do
      get "/zotero-bridge/config"
      expect(response.status).to eq(403)
    end

    it "returns LLM config and increments usage" do
      sign_in(user)
      get "/zotero-bridge/config"

      expect(response.status).to eq(200)
      json = response.parsed_body
      expect(json["endpoint"]).to eq("https://api.openai.com/v1/chat/completions")
      expect(json["api_key"]).to eq("sk-test-key-123")
      expect(json["model_name"]).to eq("gpt-4o")
      expect(json["used_today"]).to eq(1)
      expect(json["daily_quota"]).to eq(100)
      expect(json["remaining"]).to eq(99)
    end

    it "returns 429 when quota is exceeded" do
      sign_in(user)
      DiscourseZoteroBridge::UsageLog.create!(
        user_id: user.id,
        used_on: Date.current,
        request_count: 100,
      )

      get "/zotero-bridge/config"

      expect(response.status).to eq(429)
      json = response.parsed_body
      expect(json["error"]).to be_present
    end

    it "returns 404 when plugin is disabled" do
      SiteSetting.discourse_zotero_bridge_enabled = false
      sign_in(user)

      get "/zotero-bridge/config"
      expect(response.status).to eq(404)
    end
  end

  describe "GET /zotero-bridge/usage" do
    it "requires authentication" do
      get "/zotero-bridge/usage"
      expect(response.status).to eq(403)
    end

    it "returns usage summary without incrementing count" do
      sign_in(user)
      DiscourseZoteroBridge::UsageLog.create!(
        user_id: user.id,
        used_on: Date.current,
        request_count: 42,
      )

      get "/zotero-bridge/usage"

      expect(response.status).to eq(200)
      json = response.parsed_body
      expect(json["trust_level"]).to eq(2)
      expect(json["daily_quota"]).to eq(100)
      expect(json["used_today"]).to eq(42)
      expect(json["remaining"]).to eq(58)
      expect(json["username"]).to eq(user.username)
    end
  end
end
