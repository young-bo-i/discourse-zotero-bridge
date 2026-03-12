# frozen_string_literal: true

RSpec.describe DiscourseZoteroBridge::ConfigController do
  fab!(:user) { Fabricate(:user, trust_level: 2) }

  before do
    SiteSetting.discourse_zotero_bridge_enabled = true
    SiteSetting.zotero_bridge_daily_quota_tl2 = 100
  end

  describe "GET /zotero-bridge/usage" do
    it "requires authentication" do
      get "/zotero-bridge/usage"
      expect(response.status).to eq(403)
    end

    it "returns usage summary" do
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

    it "returns 404 when plugin is disabled" do
      SiteSetting.discourse_zotero_bridge_enabled = false
      sign_in(user)

      get "/zotero-bridge/usage"
      expect(response.status).to eq(404)
    end
  end
end
