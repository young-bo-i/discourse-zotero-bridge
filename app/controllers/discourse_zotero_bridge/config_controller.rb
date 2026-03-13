# frozen_string_literal: true

module DiscourseZoteroBridge
  class ConfigController < ::ApplicationController
    requires_plugin PLUGIN_NAME
    requires_login

    skip_before_action :check_xhr, only: [:download_latest]
    skip_before_action :preload_json, only: [:download_latest]

    GITHUB_REPO = "young-bo-i/zotero-enterscholar"
    GITHUB_API_RELEASES = "https://api.github.com/repos/#{GITHUB_REPO}/releases/latest"
    DOWNLOAD_CACHE_KEY = "zotero_bridge_latest_xpi"
    DOWNLOAD_CACHE_TTL = 10.minutes
    DOWNLOAD_LOCK_KEY = "zotero_bridge_fetch_lock"

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
        cached = fetch_latest_xpi_url_with_lock
      end

      unless cached
        return render json: { error: I18n.t("zotero_bridge.errors.download_unavailable") }, status: 404
      end

      proxy_download(cached[:url], cached[:filename])
    end

    private

    def fetch_latest_xpi_url_with_lock
      DistributedMutex.synchronize(DOWNLOAD_LOCK_KEY, validity: 15) do
        cached = Discourse.cache.read(DOWNLOAD_CACHE_KEY)
        return cached if cached

        result = fetch_latest_xpi_url
        Discourse.cache.write(DOWNLOAD_CACHE_KEY, result, expires_in: DOWNLOAD_CACHE_TTL) if result
        result
      end
    rescue DistributedMutex::Timeout
      Discourse.cache.read(DOWNLOAD_CACHE_KEY)
    end

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

    MAX_REDIRECTS = 5
    MAX_DOWNLOAD_SIZE = 50.megabytes

    def proxy_download(url, filename)
      current_url = url
      redirects = 0

      loop do
        uri = URI.parse(current_url)
        response =
          Net::HTTP.start(
            uri.host,
            uri.port,
            use_ssl: uri.scheme == "https",
            open_timeout: 15,
            read_timeout: 60,
          ) do |http|
            req = Net::HTTP::Get.new(uri)
            req["User-Agent"] = "Discourse-ZoteroBridge"
            http.request(req)
          end

        if response.is_a?(Net::HTTPRedirection) && response["location"]
          redirects += 1
          if redirects > MAX_REDIRECTS
            return(
              render json: { error: I18n.t("zotero_bridge.errors.download_unavailable") }, status: 502
            )
          end
          current_url = URI.join(uri, response["location"]).to_s
          next
        end

        unless response.code.to_i == 200
          return(
            render json: { error: I18n.t("zotero_bridge.errors.download_unavailable") }, status: 502
          )
        end

        if response.body.bytesize > MAX_DOWNLOAD_SIZE
          return(
            render json: { error: I18n.t("zotero_bridge.errors.download_unavailable") }, status: 502
          )
        end

        send_data response.body,
                  filename: filename,
                  type: "application/x-xpinstall",
                  disposition: "attachment"
        return
      end
    end
  end
end
