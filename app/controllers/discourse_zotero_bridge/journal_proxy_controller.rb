# frozen_string_literal: true

module DiscourseZoteroBridge
  class JournalProxyController < ::ApplicationController
    requires_plugin PLUGIN_NAME
    requires_login

    skip_before_action :verify_authenticity_token

    JNL_TIMEOUT = 30
    MAX_BODY_SIZE = 100.kilobytes

    def query
      body = parse_request_body
      return if body.nil?

      body["full"] = "1"

      JournalLog.increment!(current_user)

      endpoint_uri = URI.parse(full_endpoint_url)

      proxy_request(endpoint_uri, body)
    end

    private

    def parse_request_body
      if request.content_length.to_i > MAX_BODY_SIZE
        render json: { error: I18n.t("zotero_bridge.errors.body_too_large") }, status: 413
        return nil
      end

      raw = request.body.read(MAX_BODY_SIZE + 1)
      if raw.nil? || raw.bytesize > MAX_BODY_SIZE
        render json: { error: I18n.t("zotero_bridge.errors.body_too_large") }, status: 413
        return nil
      end

      body = JSON.parse(raw)

      unless body.is_a?(Hash) && body["name"].is_a?(String) && body["name"].present?
        render json: { error: I18n.t("zotero_bridge.errors.jnl_invalid_name") }, status: 400
        return nil
      end

      body
    rescue JSON::ParserError
      render json: { error: I18n.t("zotero_bridge.errors.invalid_json") }, status: 400
      nil
    end

    def full_endpoint_url
      base = SiteSetting.zotero_bridge_jnl_base_url.chomp("/")
      "#{base}/v1/jnl/byName"
    end

    def jnl_headers
      {
        "Content-Type" => "application/json",
        "Authorization" => "Bearer #{SiteSetting.zotero_bridge_jnl_api_key}",
      }
    end

    def proxy_request(uri, body)
      outbound_headers = jnl_headers
      hijack do
        begin
          payload = body.to_json
          req = Net::HTTP::Post.new(uri, outbound_headers)
          req.body = payload

          response =
            Net::HTTP.start(
              uri.host,
              uri.port,
              use_ssl: uri.scheme == "https",
              read_timeout: JNL_TIMEOUT,
              open_timeout: 15,
            ) { |http| http.request(req) }

          if response.code.to_i >= 200 && response.code.to_i < 300
            render json: response.body, status: response.code.to_i
          else
            render json: {
                     error: I18n.t("zotero_bridge.errors.jnl_service_error"),
                     status: response.code.to_i,
                     details: safe_error_body(response.body),
                   },
                   status: 502
          end
        rescue Net::OpenTimeout, Net::ReadTimeout
          render json: { error: I18n.t("zotero_bridge.errors.jnl_timeout") }, status: 504
        rescue StandardError => e
          Rails.logger.error("ZoteroBridge journal proxy error: #{e.message}")
          render json: { error: I18n.t("zotero_bridge.errors.jnl_proxy_error") }, status: 502
        end
      end
    end

    def safe_error_body(body)
      parsed = JSON.parse(body)
      parsed["message"] || parsed["error"] || body.truncate(500)
    rescue StandardError
      body.to_s.truncate(500)
    end
  end
end
