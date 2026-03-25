# frozen_string_literal: true

class CreateZoteroBridgeBabeldocLogs < ActiveRecord::Migration[7.2]
  def change
    create_table :zotero_bridge_babeldoc_logs do |t|
      t.references :user, null: false, foreign_key: true
      t.date :used_on, null: false
      t.integer :request_count, default: 0, null: false
      t.integer :extra_quota_granted, default: 0, null: false
      t.integer :extra_requests_count, default: 0, null: false
      t.timestamps
    end

    add_index :zotero_bridge_babeldoc_logs, %i[user_id used_on], unique: true
    add_index :zotero_bridge_babeldoc_logs, :used_on
  end
end
