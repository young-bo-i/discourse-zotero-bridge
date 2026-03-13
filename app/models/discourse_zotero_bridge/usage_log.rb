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
    rescue ActiveRecord::RecordNotUnique
      retry
    end

    VALID_TRUST_LEVELS = (0..4).freeze

    def self.daily_quota_for(user)
      tl = user.trust_level
      raise ArgumentError, "Invalid trust level: #{tl}" unless VALID_TRUST_LEVELS.include?(tl)

      SiteSetting.public_send("zotero_bridge_daily_quota_tl#{tl}")
    end

    def self.increment_and_check!(user)
      quota = daily_quota_for(user)
      today_for(user)

      updated =
        where(user_id: user.id, used_on: Date.current).where(
          "request_count < ?",
          quota,
        ).update_all(["request_count = request_count + 1, updated_at = ?", Time.current])

      current_count = where(user_id: user.id, used_on: Date.current).pick(:request_count) || 0

      if updated > 0
        { allowed: true, used: current_count, quota: quota }
      else
        { allowed: false, used: current_count, quota: quota }
      end
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
