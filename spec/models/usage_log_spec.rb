# frozen_string_literal: true

RSpec.describe DiscourseZoteroBridge::UsageLog do
  fab!(:user) { Fabricate(:user, trust_level: 2) }

  before { SiteSetting.discourse_zotero_bridge_enabled = true }

  describe ".today_for" do
    it "creates a new record for today if none exists" do
      log = described_class.today_for(user)

      expect(log).to be_persisted
      expect(log.user_id).to eq(user.id)
      expect(log.used_on).to eq(Date.current)
      expect(log.request_count).to eq(0)
    end

    it "returns the existing record for today" do
      existing = described_class.create!(user_id: user.id, used_on: Date.current, request_count: 5)
      log = described_class.today_for(user)

      expect(log.id).to eq(existing.id)
      expect(log.request_count).to eq(5)
    end
  end

  describe ".daily_quota_for" do
    it "returns the correct quota based on trust level" do
      SiteSetting.zotero_bridge_daily_quota_tl2 = 100
      expect(described_class.daily_quota_for(user)).to eq(100)
    end
  end

  describe ".increment_and_check!" do
    before { SiteSetting.zotero_bridge_daily_quota_tl2 = 3 }

    it "increments and allows when under quota" do
      result = described_class.increment_and_check!(user)

      expect(result[:allowed]).to eq(true)
      expect(result[:used]).to eq(1)
      expect(result[:quota]).to eq(3)
    end

    it "denies when quota is reached" do
      described_class.create!(user_id: user.id, used_on: Date.current, request_count: 3)
      result = described_class.increment_and_check!(user)

      expect(result[:allowed]).to eq(false)
      expect(result[:used]).to eq(3)
    end
  end

  describe ".usage_summary" do
    it "returns a complete summary" do
      SiteSetting.zotero_bridge_daily_quota_tl2 = 100
      described_class.create!(user_id: user.id, used_on: Date.current, request_count: 25)

      summary = described_class.usage_summary(user)

      expect(summary[:trust_level]).to eq(2)
      expect(summary[:daily_quota]).to eq(100)
      expect(summary[:used_today]).to eq(25)
      expect(summary[:remaining]).to eq(75)
    end
  end
end
