# frozen_string_literal: true

class AddExtraQuotaToZoteroBridgeUsageLogs < ActiveRecord::Migration[7.2]
  def change
    add_column :zotero_bridge_usage_logs, :extra_quota_granted, :integer, default: 0, null: false
    add_column :zotero_bridge_usage_logs, :extra_requests_count, :integer, default: 0, null: false
  end
end
