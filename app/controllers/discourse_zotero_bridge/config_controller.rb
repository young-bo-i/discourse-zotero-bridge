# frozen_string_literal: true

module DiscourseZoteroBridge
  class ConfigController < ::ApplicationController
    requires_plugin PLUGIN_NAME
    requires_login

    GITHUB_REPO = "young-bo-i/zotero-enterscholar"
    GITHUB_API_RELEASES = "https://api.github.com/repos/#{GITHUB_REPO}/releases/latest"
    DOWNLOAD_CACHE_KEY = "zotero_bridge_latest_xpi"
    DOWNLOAD_CACHE_TTL = 10.minutes

    def usage
      summary = UsageLog.usage_summary(current_user)

      render json: {
               trust_level: summary[:trust_level],
               daily_quota: summary[:daily_quota],
               used_today: summary[:used_today],
               remaining: summary[:remaining],
               username: current_user.username,
             }
    end

    def download_latest
      cached = Discourse.cache.read(DOWNLOAD_CACHE_KEY)

      unless cached
        cached = fetch_latest_xpi_url
        if cached
          Discourse.cache.write(DOWNLOAD_CACHE_KEY, cached, expires_in: DOWNLOAD_CACHE_TTL)
        end
      end

      unless cached
        return render json: { error: I18n.t("zotero_bridge.errors.download_unavailable") }, status: 404
      end

      proxy_download(cached[:url], cached[:filename])
    end

    private

    def fetch_latest_xpi_url
      uri = URI.parse(GITHUB_API_RELEASES)
      response =
        Net::HTTP.start(uri.host, uri.port, use_ssl: true, open_timeout: 10, read_timeout: 10) do |http|
          req = Net::HTTP::Get.new(uri)
          req["Accept"] = "application/vnd.github+json"
          req["User-Agent"] = "Discourse-ZoteroBridge"
          http.request(req)
        end

      return nil unless response.code.to_i == 200

      release = JSON.parse(response.body)
      asset = release["assets"]&.find { |a| a["name"]&.end_with?(".xpi") }
      return nil unless asset

      { url: asset["browser_download_url"], filename: asset["name"] }
    rescue StandardError => e
      Rails.logger.warn("ZoteroBridge: failed to fetch latest release: #{e.message}")
      nil
    end

    def proxy_download(url, filename)
      uri = URI.parse(url)
      response =
        Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == "https", open_timeout: 15, read_timeout: 60) do |http|
          req = Net::HTTP::Get.new(uri)
          req["User-Agent"] = "Discourse-ZoteroBridge"
          http.request(req)
        end

      if response.is_a?(Net::HTTPRedirection) && response["location"]
        return proxy_download(response["location"], filename)
      end

      unless response.code.to_i == 200
        return render json: { error: I18n.t("zotero_bridge.errors.download_unavailable") }, status: 502
      end

      send_data response.body,
                filename: filename,
                type: "application/x-xpinstall",
                disposition: "attachment"
    end
  end
end
