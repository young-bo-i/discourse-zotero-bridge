# frozen_string_literal: true

module DiscourseZoteroBridge
  module Admin
    class DashboardController < ::Admin::AdminController
      requires_plugin DiscourseZoteroBridge::PLUGIN_NAME

      VALID_USER_ORDER_COLUMNS = %w[total_requests last_active_on username trust_level].freeze
      VALID_LLM_ORDER_COLUMNS = (VALID_USER_ORDER_COLUMNS + %w[extra_requests]).freeze

      ORDER_COLUMN_MAP = {
        "username" => "users.username",
        "trust_level" => "users.trust_level",
        "extra_requests" => "extra_requests",
        "last_active_on" => "last_active_on",
        "total_requests" => "total_requests",
      }.freeze

      def show
        start_date, end_date = date_range
        render json: dashboard_data(UsageLog, start_date, end_date)
      end

      def users
        start_date, end_date = date_range
        extra_selects = [
          "SUM(#{UsageLog.table_name}.extra_requests_count) AS extra_requests",
        ]
        render json:
                 users_data(
                   UsageLog,
                   start_date,
                   end_date,
                   valid_orders: VALID_LLM_ORDER_COLUMNS,
                   extra_selects: extra_selects,
                   extra_fields: %i[extra_requests],
                 )
      end

      def journal_show
        start_date, end_date = date_range
        render json: dashboard_data(JournalLog, start_date, end_date)
      end

      def journal_users
        start_date, end_date = date_range
        render json:
                 users_data(
                   JournalLog,
                   start_date,
                   end_date,
                   valid_orders: VALID_USER_ORDER_COLUMNS,
                 )
      end

      def babeldoc_show
        start_date, end_date = date_range
        render json: dashboard_data(BabeldocLog, start_date, end_date)
      end

      def babeldoc_users
        start_date, end_date = date_range
        extra_selects = [
          "SUM(#{BabeldocLog.table_name}.extra_requests_count) AS extra_requests",
        ]
        render json:
                 users_data(
                   BabeldocLog,
                   start_date,
                   end_date,
                   valid_orders: VALID_LLM_ORDER_COLUMNS,
                   extra_selects: extra_selects,
                   extra_fields: %i[extra_requests],
                 )
      end

      private

      def parse_date(value)
        return nil if value.blank?
        Date.parse(value)
      rescue Date::Error
        nil
      end

      def date_range
        start_date = parse_date(params[:start_date]) || 30.days.ago.to_date
        end_date = parse_date(params[:end_date]) || Date.current
        [start_date, end_date]
      end

      def dashboard_data(model_class, start_date, end_date)
        logs = model_class.where(used_on: start_date..end_date)
        {
          summary: build_summary(logs, start_date, end_date),
          daily_trend: build_daily_trend(logs, start_date, end_date),
          trust_level_breakdown: build_tl_breakdown(logs, model_class.table_name),
        }
      end

      def build_summary(logs, start_date, end_date)
        week_start = [7.days.ago.to_date, start_date].max
        sanitized_week_clause =
          ActiveRecord::Base.sanitize_sql_array(
            [
              "SUM(CASE WHEN used_on >= ? THEN request_count ELSE 0 END) AS seven_day_requests",
              week_start,
            ],
          )

        row =
          logs
            .select(
              "SUM(request_count) AS total_requests",
              "COUNT(DISTINCT user_id) AS active_users",
              "SUM(CASE WHEN used_on = CURRENT_DATE THEN request_count ELSE 0 END) AS today_requests",
              "COUNT(DISTINCT CASE WHEN used_on = CURRENT_DATE THEN user_id END) AS today_active_users",
              Arel.sql(sanitized_week_clause),
            )
            .take

        {
          total_requests: row.total_requests.to_i,
          active_users: row.active_users.to_i,
          today_requests: row.today_requests.to_i,
          today_active_users: row.today_active_users.to_i,
          seven_day_requests: row.seven_day_requests.to_i,
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

      def build_tl_breakdown(logs, table_name)
        logs
          .joins(:user)
          .group("users.trust_level")
          .select(
            "users.trust_level",
            "SUM(#{table_name}.request_count) AS total_requests",
            "COUNT(DISTINCT #{table_name}.user_id) AS user_count",
          )
          .order("users.trust_level")
          .map do |row|
            {
              trust_level: row.trust_level,
              total_requests: row.total_requests.to_i,
              user_count: row.user_count.to_i,
            }
          end
      end

      def users_data(
        model_class,
        start_date,
        end_date,
        valid_orders:,
        extra_selects: [],
        extra_fields: []
      )
        page = [params[:page].to_i, 1].max
        per_page = params[:per_page].blank? ? 20 : [[params[:per_page].to_i, 1].max, 100].min
        order =
          valid_orders.include?(params[:order]) ? params[:order] : "total_requests"
        direction = params[:direction] == "asc" ? "ASC" : "DESC"

        table_name = model_class.table_name
        base_query = model_class.where(used_on: start_date..end_date)

        select_columns = [
          "users.id AS user_id",
          "users.username",
          "users.trust_level",
          "users.uploaded_avatar_id",
          "SUM(#{table_name}.request_count) AS total_requests",
          "MAX(#{table_name}.used_on) AS last_active_on",
        ] + extra_selects

        user_stats =
          base_query
            .joins(:user)
            .group(
              "users.id",
              "users.username",
              "users.trust_level",
              "users.uploaded_avatar_id",
            )
            .select(*select_columns)
            .order(
              Arel.sql(
                "#{ORDER_COLUMN_MAP.fetch(order, "total_requests")} #{direction}",
              ),
            )

        total_count = base_query.select(:user_id).distinct.count
        user_rows = user_stats.offset((page - 1) * per_page).limit(per_page)

        {
          users:
            user_rows.map do |row|
              result = {
                id: row.user_id,
                username: row.username,
                trust_level: row.trust_level,
                avatar_template:
                  User.avatar_template(row.username, row.uploaded_avatar_id),
                total_requests: row.total_requests.to_i,
                last_active_on: row.last_active_on,
              }
              extra_fields.each { |f| result[f] = row.public_send(f).to_i }
              result
            end,
          total_count: total_count,
          page: page,
          per_page: per_page,
        }
      end
    end
  end
end
