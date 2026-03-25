# frozen_string_literal: true

module DiscourseZoteroBridge
  class BabeldocLog < ActiveRecord::Base
    self.table_name = "zotero_bridge_babeldoc_logs"

    belongs_to :user

    validates :user_id, presence: true
    validates :used_on, presence: true
    validates :request_count, numericality: { greater_than_or_equal_to: 0 }

    VALID_TRUST_LEVELS = (0..4).freeze
    SETTING_PREFIX = "zotero_bridge_babeldoc"

    ENSURE_ROW_SQL = <<~SQL
      INSERT INTO zotero_bridge_babeldoc_logs
        (user_id, used_on, request_count, extra_quota_granted, extra_requests_count, created_at, updated_at)
      VALUES (:user_id, CURRENT_DATE, 0, 0, 0, :now, :now)
      ON CONFLICT (user_id, used_on) DO NOTHING
    SQL

    INCREMENT_SQL = <<~SQL
      UPDATE zotero_bridge_babeldoc_logs
      SET request_count = request_count + 1, updated_at = :now
      WHERE user_id = :user_id AND used_on = CURRENT_DATE
        AND request_count < (:base_quota + extra_quota_granted)
      RETURNING request_count,
                (:base_quota + extra_quota_granted) AS effective_quota
    SQL

    DECREMENT_SQL = <<~SQL
      UPDATE zotero_bridge_babeldoc_logs
      SET request_count = GREATEST(request_count - 1, 0), updated_at = :now
      WHERE user_id = :user_id AND used_on = CURRENT_DATE
    SQL

    QUOTA_STATE_SQL = <<~SQL
      SELECT request_count, (:base_quota + extra_quota_granted) AS effective_quota
      FROM zotero_bridge_babeldoc_logs
      WHERE user_id = :user_id AND used_on = CURRENT_DATE
    SQL

    def self.today_for(user)
      find_or_create_by(user_id: user.id, used_on: Date.current)
    rescue ActiveRecord::RecordNotUnique
      retry
    end

    def self.daily_quota_for(user)
      tl = user.trust_level
      raise ArgumentError, "Invalid trust level: #{tl}" unless VALID_TRUST_LEVELS.include?(tl)

      SiteSetting.public_send("#{SETTING_PREFIX}_daily_quota_tl#{tl}")
    end

    def self.increment_and_check!(user)
      base_quota = daily_quota_for(user)
      now = Time.current
      binds = { user_id: user.id, base_quota: base_quota, now: now }

      connection.exec_query(sanitize_sql_array([ENSURE_ROW_SQL, binds]))

      result =
        connection.select_one(sanitize_sql_array([INCREMENT_SQL, binds]))

      if result
        { allowed: true, used: result["request_count"].to_i, quota: result["effective_quota"].to_i }
      else
        state =
          connection.select_one(sanitize_sql_array([QUOTA_STATE_SQL, binds]))
        if state
          { allowed: false, used: state["request_count"].to_i, quota: state["effective_quota"].to_i }
        else
          { allowed: false, used: 0, quota: base_quota }
        end
      end
    end

    def self.rollback_increment!(user)
      now = Time.current
      binds = { user_id: user.id, now: now }
      connection.exec_query(sanitize_sql_array([DECREMENT_SQL, binds]))
    end

    def self.request_extra_quota!(user)
      log = today_for(user)
      max_requests = SiteSetting.public_send("#{SETTING_PREFIX}_max_extra_requests_per_day")
      extra_amount = SiteSetting.public_send("#{SETTING_PREFIX}_extra_quota_amount")

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
      max_extra = SiteSetting.public_send("#{SETTING_PREFIX}_max_extra_requests_per_day")

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
