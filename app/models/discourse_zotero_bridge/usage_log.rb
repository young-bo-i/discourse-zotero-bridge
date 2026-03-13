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

    def self.effective_quota_for(user)
      log = today_for(user)
      daily_quota_for(user) + log.extra_quota_granted
    end

    def self.increment_and_check!(user)
      quota = effective_quota_for(user)

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

    def self.request_extra_quota!(user)
      log = today_for(user)
      max_requests = SiteSetting.zotero_bridge_max_extra_requests_per_day
      extra_amount = SiteSetting.zotero_bridge_extra_quota_amount

      if log.extra_requests_count >= max_requests
        return { success: false, reason: :max_requests_reached }
      end

      log.with_lock do
        if log.extra_requests_count >= max_requests
          return { success: false, reason: :max_requests_reached }
        end

        log.update!(
          extra_quota_granted: log.extra_quota_granted + extra_amount,
          extra_requests_count: log.extra_requests_count + 1,
        )

        { success: true, extra_granted: extra_amount }
      end
    end

    def self.usage_summary(user)
      log = today_for(user)
      base_quota = daily_quota_for(user)
      total_quota = base_quota + log.extra_quota_granted
      max_extra = SiteSetting.zotero_bridge_max_extra_requests_per_day

      {
        trust_level: user.trust_level,
        daily_quota: total_quota,
        base_quota: base_quota,
        used_today: log.request_count,
        remaining: [total_quota - log.request_count, 0].max,
        extra_quota_granted: log.extra_quota_granted,
        extra_requests_used: log.extra_requests_count,
        extra_requests_max: max_extra,
        can_request_extra: log.extra_requests_count < max_extra,
      }
    end
  end
end
