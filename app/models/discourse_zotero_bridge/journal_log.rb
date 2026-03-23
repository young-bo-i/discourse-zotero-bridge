# frozen_string_literal: true

module DiscourseZoteroBridge
  class JournalLog < ActiveRecord::Base
    self.table_name = "zotero_bridge_journal_logs"

    belongs_to :user

    validates :user_id, presence: true
    validates :used_on, presence: true
    validates :request_count, numericality: { greater_than_or_equal_to: 0 }

    def self.today_for(user)
      find_or_create_by(user_id: user.id, used_on: Date.current)
    rescue ActiveRecord::RecordNotUnique
      retry
    end

    def self.increment!(user)
      today_for(user)
      where(user_id: user.id, used_on: Date.current).update_all(
        ["request_count = request_count + 1, updated_at = ?", Time.current],
      )
    end
  end
end
