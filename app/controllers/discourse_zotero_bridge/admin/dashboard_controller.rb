# frozen_string_literal: true

module DiscourseZoteroBridge
  module Admin
    class DashboardController < ::Admin::AdminController
      requires_plugin DiscourseZoteroBridge::PLUGIN_NAME

      def show
        start_date = parse_date(params[:start_date]) || 30.days.ago.to_date
        end_date = parse_date(params[:end_date]) || Date.current
        logs = UsageLog.where(used_on: start_date..end_date)

        render json: {
          summary: build_summary(logs, start_date, end_date),
          daily_trend: build_daily_trend(logs, start_date, end_date),
          trust_level_breakdown: build_tl_breakdown(logs),
        }
      end

      def users
        start_date = parse_date(params[:start_date]) || 30.days.ago.to_date
        end_date = parse_date(params[:end_date]) || Date.current
        page = [params[:page].to_i, 1].max
        per_page = [[params[:per_page].to_i, 1].max, 100].min
        per_page = 20 if params[:per_page].blank?
        order = %w[total_requests last_active_on username trust_level extra_requests].include?(params[:order]) ? params[:order] : "total_requests"
        direction = params[:direction] == "asc" ? "ASC" : "DESC"

        base_query = UsageLog.where(used_on: start_date..end_date)

        user_stats =
          base_query
            .joins(:user)
            .group("users.id", "users.username", "users.trust_level", "users.uploaded_avatar_id")
            .select(
              "users.id AS user_id",
              "users.username",
              "users.trust_level",
              "users.uploaded_avatar_id",
              "SUM(zotero_bridge_usage_logs.request_count) AS total_requests",
              "SUM(zotero_bridge_usage_logs.extra_requests_count) AS extra_requests",
              "MAX(zotero_bridge_usage_logs.used_on) AS last_active_on",
            )

        order_column =
          case order
          when "username"
            "users.username"
          when "trust_level"
            "users.trust_level"
          when "extra_requests"
            "extra_requests"
          when "last_active_on"
            "last_active_on"
          else
            "total_requests"
          end

        user_stats = user_stats.order(Arel.sql("#{order_column} #{direction}"))

        total_count = base_query.select(:user_id).distinct.count
        offset = (page - 1) * per_page
        user_rows = user_stats.offset(offset).limit(per_page)

        render json: {
          users:
            user_rows.map do |row|
              {
                id: row.user_id,
                username: row.username,
                trust_level: row.trust_level,
                avatar_template: User.avatar_template(row.username, row.uploaded_avatar_id),
                total_requests: row.total_requests.to_i,
                extra_requests: row.extra_requests.to_i,
                last_active_on: row.last_active_on,
              }
            end,
          total_count: total_count,
          page: page,
          per_page: per_page,
        }
      end

      private

      def parse_date(value)
        return nil if value.blank?
        Date.parse(value)
      rescue Date::Error
        nil
      end

      def build_summary(logs, start_date, end_date)
        today = Date.current
        seven_days_ago = 7.days.ago.to_date

        today_logs = UsageLog.where(used_on: today)
        week_start = [seven_days_ago, start_date].max
        week_logs = UsageLog.where(used_on: week_start..today)

        {
          total_requests: logs.sum(:request_count),
          active_users: logs.select(:user_id).distinct.count,
          today_requests: today_logs.sum(:request_count),
          today_active_users: today_logs.select(:user_id).distinct.count,
          seven_day_requests: week_logs.sum(:request_count),
          period_start: start_date,
          period_end: end_date,
        }
      end

      def build_daily_trend(logs, start_date, end_date)
        daily_data =
          logs
            .group(:used_on)
            .select(
              "used_on",
              "SUM(request_count) AS total_requests",
              "COUNT(DISTINCT user_id) AS active_users",
            )
            .index_by(&:used_on)

        (start_date..end_date).map do |date|
          row = daily_data[date]
          {
            date: date.to_s,
            total_requests: row&.total_requests.to_i,
            active_users: row&.active_users.to_i,
          }
        end
      end

      def build_tl_breakdown(logs)
        logs
          .joins(:user)
          .group("users.trust_level")
          .select("users.trust_level", "SUM(zotero_bridge_usage_logs.request_count) AS total_requests", "COUNT(DISTINCT zotero_bridge_usage_logs.user_id) AS user_count")
          .order("users.trust_level")
          .map do |row|
            {
              trust_level: row.trust_level,
              total_requests: row.total_requests.to_i,
              user_count: row.user_count.to_i,
            }
          end
      end
    end
  end
end
