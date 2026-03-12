# frozen_string_literal: true

module DiscourseZoteroBridge
  class UsageLog < ActiveRecord::Base
    self.table_name = "zotero_bridge_usage_logs"

    belongs_to :user

    validates :user_id, presence: true
    validates :used_on, presence: true
    validates :request_count, numericality: { greater_than_or_equal_to: 0 }

    def self.today_for(user)
      find_or_create_by(user_id: user.id, used_on: Date.current)
    end

    def self.daily_quota_for(user)
      setting_name = "zotero_bridge_daily_quota_tl#{user.trust_level}"
      SiteSetting.public_send(setting_name)
    end

    def self.increment_and_check!(user)
      log = today_for(user)
      quota = daily_quota_for(user)

      return { allowed: false, used: log.request_count, quota: quota } if log.request_count >= quota

      log.increment!(:request_count)
      { allowed: true, used: log.request_count, quota: quota }
    end

    def self.usage_summary(user)
      log = today_for(user)
      quota = daily_quota_for(user)

      {
        trust_level: user.trust_level,
        daily_quota: quota,
        used_today: log.request_count,
        remaining: [quota - log.request_count, 0].max,
      }
    end
  end
end
