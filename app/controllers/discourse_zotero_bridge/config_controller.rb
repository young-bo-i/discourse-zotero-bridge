# frozen_string_literal: true

module DiscourseZoteroBridge
  class ConfigController < ::ApplicationController
    requires_plugin PLUGIN_NAME
    requires_login

    skip_before_action :check_xhr, only: %i[download_latest download_journal_latest download_babeldoc_latest marketplace]
    skip_before_action :preload_json, only: %i[download_latest download_journal_latest download_babeldoc_latest]

    DOWNLOAD_CACHE_TTL = 10.minutes
    MAX_REDIRECTS = 5
    MAX_DOWNLOAD_SIZE = 50.megabytes

    TL_REQUIREMENTS = {
      1 => %w[tl1_requires_topics_entered tl1_requires_read_posts tl1_requires_time_spent_mins],
      2 => %w[
        tl2_requires_topics_entered
        tl2_requires_read_posts
        tl2_requires_time_spent_mins
        tl2_requires_days_visited
        tl2_requires_likes_received
        tl2_requires_likes_given
        tl2_requires_topic_reply_count
      ],
      3 => %w[
        tl3_requires_days_visited
        tl3_requires_topics_replied_to
        tl3_requires_topics_viewed
        tl3_requires_posts_read
        tl3_requires_likes_given
        tl3_requires_likes_received
      ],
    }.freeze

    def usage
      summary = UsageLog.usage_summary(current_user)

      render json: {
               trust_level: summary[:trust_level],
               daily_quota: summary[:daily_quota],
               base_quota: summary[:base_quota],
               used_today: summary[:used_today],
               remaining: summary[:remaining],
               extra_quota_granted: summary[:extra_quota_granted],
               extra_requests_used: summary[:extra_requests_used],
               extra_requests_max: summary[:extra_requests_max],
               can_request_extra: summary[:can_request_extra],
               username: current_user.username,
               quota_tiers:
                 (0..4).map do |tl|
                   {
                     trust_level: tl,
                     daily_quota: SiteSetting.public_send("zotero_bridge_daily_quota_tl#{tl}"),
                   }
                 end,
               next_level_requirements: build_next_level_requirements(current_user),
             }
    end

    def jnl_usage
      log = JournalLog.today_for(current_user)
      render json: { used_today: log.request_count, username: current_user.username }
    end

    def babeldoc_usage
      summary = BabeldocLog.usage_summary(current_user)

      render json: {
               trust_level: summary[:trust_level],
               daily_quota: summary[:daily_quota],
               base_quota: summary[:base_quota],
               used_today: summary[:used_today],
               remaining: summary[:remaining],
               extra_quota_granted: summary[:extra_quota_granted],
               extra_requests_used: summary[:extra_requests_used],
               extra_requests_max: summary[:extra_requests_max],
               can_request_extra: summary[:can_request_extra],
               username: current_user.username,
               quota_tiers:
                 (0..4).map do |tl|
                   {
                     trust_level: tl,
                     daily_quota:
                       SiteSetting.public_send("zotero_bridge_babeldoc_daily_quota_tl#{tl}"),
                   }
                 end,
               next_level_requirements: build_next_level_requirements(current_user),
             }
    end

    def marketplace
      unless request.xhr?
        render "default/empty"
        return
      end

      translate_summary = UsageLog.usage_summary(current_user)
      jnl_log = JournalLog.today_for(current_user)
      babeldoc_summary = BabeldocLog.usage_summary(current_user)
      translate_repo = SiteSetting.zotero_bridge_translate_github_repo
      jnl_repo = SiteSetting.zotero_bridge_jnl_github_repo
      babeldoc_repo = SiteSetting.zotero_bridge_babeldoc_github_repo

      plugins = [
        {
          id: "translate",
          platform: "zotero",
          github_url: translate_repo.present? ? "https://github.com/#{translate_repo}" : nil,
          download_url: translate_repo.present? ? "/zotero-bridge/download/latest" : nil,
          has_quota: true,
          usage: {
            used_today: translate_summary[:used_today],
            daily_quota: translate_summary[:daily_quota],
            remaining: translate_summary[:remaining],
            extra_quota_granted: translate_summary[:extra_quota_granted],
            extra_requests_used: translate_summary[:extra_requests_used],
            extra_requests_max: translate_summary[:extra_requests_max],
            can_request_extra: translate_summary[:can_request_extra],
          },
          quota_tiers:
            (0..4).map do |tl|
              {
                trust_level: tl,
                daily_quota: SiteSetting.public_send("zotero_bridge_daily_quota_tl#{tl}"),
              }
            end,
          next_level_requirements: build_next_level_requirements(current_user),
        },
        {
          id: "babeldoc",
          platform: "zotero",
          github_url: babeldoc_repo.present? ? "https://github.com/#{babeldoc_repo}" : nil,
          download_url: babeldoc_repo.present? ? "/zotero-bridge/download/babeldoc/latest" : nil,
          has_quota: true,
          usage: {
            used_today: babeldoc_summary[:used_today],
            daily_quota: babeldoc_summary[:daily_quota],
            remaining: babeldoc_summary[:remaining],
            extra_quota_granted: babeldoc_summary[:extra_quota_granted],
            extra_requests_used: babeldoc_summary[:extra_requests_used],
            extra_requests_max: babeldoc_summary[:extra_requests_max],
            can_request_extra: babeldoc_summary[:can_request_extra],
          },
          quota_tiers:
            (0..4).map do |tl|
              {
                trust_level: tl,
                daily_quota:
                  SiteSetting.public_send("zotero_bridge_babeldoc_daily_quota_tl#{tl}"),
              }
            end,
          next_level_requirements: build_next_level_requirements(current_user),
        },
        {
          id: "journal",
          platform: "zotero",
          github_url: jnl_repo.present? ? "https://github.com/#{jnl_repo}" : nil,
          download_url: jnl_repo.present? ? "/zotero-bridge/download/journal/latest" : nil,
          has_quota: false,
          usage: {
            used_today: jnl_log.request_count,
          },
        },
      ]

      render json: {
               username: current_user.username,
               trust_level: current_user.trust_level,
               plugins: plugins,
             }
    end

    def request_extra_quota
      result = UsageLog.request_extra_quota!(current_user)

      if result[:success]
        summary = UsageLog.usage_summary(current_user)
        render json: {
                 success: true,
                 extra_granted: result[:extra_granted],
                 daily_quota: summary[:daily_quota],
                 remaining: summary[:remaining],
                 extra_requests_used: summary[:extra_requests_used],
                 extra_requests_max: summary[:extra_requests_max],
                 can_request_extra: summary[:can_request_extra],
               }
      else
        render json: {
                 success: false,
                 error: I18n.t("zotero_bridge.errors.extra_quota_limit_reached"),
               },
               status: 429
      end
    end

    def download_latest
      repo = SiteSetting.zotero_bridge_translate_github_repo
      return repo_not_configured if repo.blank?

      serve_github_release(repo, "zotero_bridge_translate_xpi")
    end

    def download_journal_latest
      repo = SiteSetting.zotero_bridge_jnl_github_repo
      return repo_not_configured if repo.blank?

      serve_github_release(repo, "zotero_bridge_jnl_xpi")
    end

    def download_babeldoc_latest
      repo = SiteSetting.zotero_bridge_babeldoc_github_repo
      return repo_not_configured if repo.blank?

      serve_github_release(repo, "zotero_bridge_babeldoc_xpi")
    end

    def request_babeldoc_extra_quota
      result = BabeldocLog.request_extra_quota!(current_user)

      if result[:success]
        summary = BabeldocLog.usage_summary(current_user)
        render json: {
                 success: true,
                 extra_granted: result[:extra_granted],
                 daily_quota: summary[:daily_quota],
                 remaining: summary[:remaining],
                 extra_requests_used: summary[:extra_requests_used],
                 extra_requests_max: summary[:extra_requests_max],
                 can_request_extra: summary[:can_request_extra],
               }
      else
        render json: {
                 success: false,
                 error: I18n.t("zotero_bridge.errors.babeldoc_extra_quota_limit_reached"),
               },
               status: 429
      end
    end

    private

    def repo_not_configured
      render json: { error: I18n.t("zotero_bridge.errors.download_unavailable") }, status: 404
    end

    def serve_github_release(repo, cache_prefix)
      cache_key = "#{cache_prefix}_latest"
      lock_key = "#{cache_prefix}_fetch_lock"

      cached = Discourse.cache.read(cache_key)

      unless cached
        cached = fetch_release_with_lock(repo, cache_key, lock_key)
      end

      unless cached
        return render json: { error: I18n.t("zotero_bridge.errors.download_unavailable") }, status: 404
      end

      proxy_download(cached[:url], cached[:filename])
    end

    def fetch_release_with_lock(repo, cache_key, lock_key)
      DistributedMutex.synchronize(lock_key, validity: 15) do
        cached = Discourse.cache.read(cache_key)
        return cached if cached

        result = fetch_latest_xpi_url(repo)
        Discourse.cache.write(cache_key, result, expires_in: DOWNLOAD_CACHE_TTL) if result
        result
      end
    rescue DistributedMutex::Timeout
      Discourse.cache.read(cache_key)
    end

    def fetch_latest_xpi_url(repo)
      api_url = "https://api.github.com/repos/#{repo}/releases/latest"
      uri = URI.parse(api_url)
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
      Rails.logger.warn("ZoteroBridge: failed to fetch latest release for #{repo}: #{e.message}")
      nil
    end

    def build_next_level_requirements(user)
      next_tl = user.trust_level + 1
      keys = TL_REQUIREMENTS[next_tl]
      return nil if keys.nil?

      next_tl <= 2 ? build_tl12_requirements(user, keys) : build_tl3_requirements(user, keys)
    end

    def build_tl12_requirements(user, keys)
      stat = user.user_stat
      reply_count = nil

      keys.map do |key|
        current =
          case key
          when /time_spent_mins/
            stat.time_read / 60
          when /topic_reply_count/
            reply_count ||= stat.calc_topic_reply_count!
          when /topics_entered/
            stat.topics_entered
          when /read_posts/
            stat.posts_read_count
          when /days_visited/
            stat.days_visited
          when /likes_received/
            stat.likes_received
          when /likes_given/
            stat.likes_given
          end

        { key: key, value: SiteSetting.public_send(key), current: current }
      end
    end

    def build_tl3_requirements(user, keys)
      tl3 = TrustLevel3Requirements.new(user)
      tl3_data = {
        "tl3_requires_days_visited" => [tl3.min_days_visited, tl3.days_visited],
        "tl3_requires_topics_replied_to" => [tl3.min_topics_replied_to, tl3.num_topics_replied_to],
        "tl3_requires_topics_viewed" => [tl3.min_topics_viewed, tl3.topics_viewed],
        "tl3_requires_posts_read" => [tl3.min_posts_read, tl3.posts_read],
        "tl3_requires_likes_given" => [tl3.min_likes_given, tl3.num_likes_given],
        "tl3_requires_likes_received" => [tl3.min_likes_received, tl3.num_likes_received],
      }

      requirements = [
        { key: "tl3_time_period", value: SiteSetting.tl3_time_period, current: nil },
      ]

      keys.each do |key|
        target, current = tl3_data[key]
        requirements << { key: key, value: target, current: current }
      end

      requirements
    end

    def resolve_download_url(url)
      current_url = url
      redirects = 0

      loop do
        uri = URI.parse(current_url)
        response =
          Net::HTTP.start(
            uri.host,
            uri.port,
            use_ssl: uri.scheme == "https",
            open_timeout: 10,
            read_timeout: 10,
          ) do |http|
            req = Net::HTTP::Head.new(uri)
            req["User-Agent"] = "Discourse-ZoteroBridge"
            http.request(req)
          end

        if response.is_a?(Net::HTTPRedirection) && response["location"]
          redirects += 1
          return nil if redirects > MAX_REDIRECTS
          current_url = URI.join(uri, response["location"]).to_s
          next
        end

        return nil unless response.code.to_i == 200

        content_length = response["content-length"].to_i
        return nil if content_length > MAX_DOWNLOAD_SIZE

        return current_url
      end
    end

    def proxy_download(url, filename)
      final_url = resolve_download_url(url)
      unless final_url
        return(
          render json: { error: I18n.t("zotero_bridge.errors.download_unavailable") }, status: 502
        )
      end

      hijacker = request.env["rack.hijack"]
      unless hijacker
        redirect_to final_url, allow_other_host: true
        return
      end

      io = hijacker.call

      Thread.new do
        begin
          uri = URI.parse(final_url)
          Net::HTTP.start(
            uri.host,
            uri.port,
            use_ssl: uri.scheme == "https",
            open_timeout: 15,
            read_timeout: 60,
          ) do |http|
            req = Net::HTTP::Get.new(uri)
            req["User-Agent"] = "Discourse-ZoteroBridge"

            http.request(req) do |response|
              unless response.code.to_i == 200
                write_download_error(io)
                next
              end

              write_download_headers(io, filename, response["content-length"])
              bytes_sent = 0
              truncated = false
              response.read_body do |chunk|
                bytes_sent += chunk.bytesize
                if bytes_sent > MAX_DOWNLOAD_SIZE
                  truncated = true
                  break
                end
                io.write(chunk)
              end
              if truncated
                Rails.logger.warn("ZoteroBridge: download truncated at #{bytes_sent} bytes (limit #{MAX_DOWNLOAD_SIZE})")
              end
            end
          end
        rescue StandardError => e
          Rails.logger.error("ZoteroBridge download stream error: #{e.message}")
        ensure
          io&.close rescue nil
        end
      end

      head 200
    end

    def write_download_headers(io, filename, content_length)
      safe_name = filename.gsub(/[^\w.\-]/, "_")
      io.write "HTTP/1.1 200 OK\r\n"
      io.write "Content-Type: application/x-xpinstall\r\n"
      io.write "Content-Disposition: attachment; filename=\"#{safe_name}\"\r\n"
      io.write "Content-Length: #{content_length}\r\n" if content_length.present?
      io.write "Connection: close\r\n"
      io.write "\r\n"
      io.flush
    end

    def write_download_error(io)
      body = { error: I18n.t("zotero_bridge.errors.download_unavailable") }.to_json
      io.write "HTTP/1.1 502 Bad Gateway\r\n"
      io.write "Content-Type: application/json; charset=utf-8\r\n"
      io.write "Content-Length: #{body.bytesize}\r\n"
      io.write "Connection: close\r\n"
      io.write "\r\n"
      io.write body
      io.flush
    end
  end
end
