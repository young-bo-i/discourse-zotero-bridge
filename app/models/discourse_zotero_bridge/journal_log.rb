# frozen_string_literal: true

module DiscourseZoteroBridge
  class JournalLog < ActiveRecord::Base
    self.table_name = "zotero_bridge_journal_logs"

    belongs_to :user

    validates :user_id, presence: true
    validates :used_on, presence: true
    validates :request_count, numericality: { greater_than_or_equal_to: 0 }

    UPSERT_INCREMENT_SQL = <<~SQL
      INSERT INTO zotero_bridge_journal_logs
        (user_id, used_on, request_count, created_at, updated_at)
      VALUES (:user_id, CURRENT_DATE, 1, :now, :now)
      ON CONFLICT (user_id, used_on)
      DO UPDATE SET request_count = zotero_bridge_journal_logs.request_count + 1,
                    updated_at = :now
    SQL

    def self.today_for(user)
      find_or_create_by(user_id: user.id, used_on: Date.current)
    rescue ActiveRecord::RecordNotUnique
      retry
    end

    def self.increment!(user)
      connection.exec_query(
        sanitize_sql_array([UPSERT_INCREMENT_SQL, { user_id: user.id, now: Time.current }]),
      )
    end
  end
end
