# frozen_string_literal: true

class CreateZoteroBridgeUsageLogs < ActiveRecord::Migration[7.2]
  def change
    create_table :zotero_bridge_usage_logs do |t|
      t.integer :user_id, null: false
      t.date :used_on, null: false
      t.integer :request_count, default: 0, null: false
      t.timestamps
    end

    add_index :zotero_bridge_usage_logs, %i[user_id used_on], unique: true
    add_index :zotero_bridge_usage_logs, :used_on
  end
end
