# frozen_string_literal: true

module DiscourseZoteroBridge
  class BabeldocProxyController < ::ApplicationController
    requires_plugin PLUGIN_NAME
    requires_login

    skip_before_action :verify_authenticity_token
    skip_before_action :check_xhr

    PROXY_TIMEOUT = 300
    MAX_UPLOAD_SIZE = 100.megabytes
    MAX_JSON_BODY = 1.megabyte

    def connectivity_check
      proxy_get("/connectivity_check")
    end

    def check_key
      proxy_get("/zotero/check-key", params: { apiKey: params[:apiKey] })
    end

    def pdf_upload_url
      proxy_get("/zotero/pdf-upload-url", rewrite_urls: true)
    end

    def upload
      stream_upload("/zotero/upload/#{params[:object_key]}")
    end

    def translate
      body = parse_json_body
      return if body.nil?

      quota_result = BabeldocLog.increment_and_check!(current_user)
      unless quota_result[:allowed]
        return(
          render json: {
                   error: I18n.t("zotero_bridge.errors.babeldoc_quota_exceeded"),
                   used_today: quota_result[:used],
                   daily_quota: quota_result[:quota],
                 },
                 status: 429
        )
      end

      proxy_post("/zotero/backend-babel-pdf", body: body, quota_rollback: true)
    end

    def process_status
      proxy_get("/zotero/pdf/#{params[:pdf_id]}/process")
    end

    def temp_url
      proxy_get("/zotero/pdf/#{params[:pdf_id]}/temp-url", rewrite_urls: true)
    end

    def download
      path_suffix = params[:path] || ""
      stream_download("/zotero/download/#{params[:pdf_id]}/#{path_suffix}")
    end

    def record_list
      proxy_get("/zotero/pdf/record-list", params: { page: params[:page], pageSize: params[:pageSize] })
    end

    def pdf_count
      proxy_get("/zotero/pdf-count")
    end

    private

    def babeldoc_base_url
      SiteSetting.zotero_bridge_babeldoc_base_url.chomp("/")
    end

    def babeldoc_headers
      headers = { "Content-Type" => "application/json" }
      api_key = SiteSetting.zotero_bridge_babeldoc_api_key
      headers["Authorization"] = "Bearer #{api_key}" if api_key.present?
      headers
    end

    def rewrite_babeldoc_urls(body_string)
      base = babeldoc_base_url
      proxy_base = "#{Discourse.base_url}/zotero-bridge/v1/babeldoc"
      body_string
        .gsub("#{base}/zotero/upload/", "#{proxy_base}/upload/")
        .gsub("#{base}/zotero/download/", "#{proxy_base}/download/")
    end

    def parse_json_body
      if request.content_length.to_i > MAX_JSON_BODY
        render json: { error: I18n.t("zotero_bridge.errors.body_too_large") }, status: 413
        return nil
      end

      raw = request.body.read(MAX_JSON_BODY + 1)
      if raw.nil? || raw.bytesize > MAX_JSON_BODY
        render json: { error: I18n.t("zotero_bridge.errors.body_too_large") }, status: 413
        return nil
      end

      body = JSON.parse(raw)
      unless body.is_a?(Hash)
        render json: { error: I18n.t("zotero_bridge.errors.invalid_json") }, status: 400
        return nil
      end

      body
    rescue JSON::ParserError
      render json: { error: I18n.t("zotero_bridge.errors.invalid_json") }, status: 400
      nil
    end

    def proxy_get(path, params: {}, rewrite_urls: false)
      uri = URI.parse("#{babeldoc_base_url}#{path}")
      uri.query = URI.encode_www_form(params.compact) if params.compact.any?
      outbound_headers = babeldoc_headers

      hijack do
        begin
          req = Net::HTTP::Get.new(uri, outbound_headers)
          response =
            Net::HTTP.start(
              uri.host,
              uri.port,
              use_ssl: uri.scheme == "https",
              read_timeout: PROXY_TIMEOUT,
              open_timeout: 15,
            ) { |http| http.request(req) }

          status = response.code.to_i
          body = response.body
          body = rewrite_babeldoc_urls(body) if rewrite_urls && status >= 200 && status < 300

          render plain: body, content_type: "application/json", status: status
        rescue Net::OpenTimeout, Net::ReadTimeout
          render json: { error: I18n.t("zotero_bridge.errors.babeldoc_timeout") }, status: 504
        rescue StandardError => e
          Rails.logger.error("ZoteroBridge babeldoc proxy error: #{e.message}")
          render json: { error: I18n.t("zotero_bridge.errors.babeldoc_proxy_error") }, status: 502
        end
      end
    end

    def proxy_post(path, body:, quota_rollback: false)
      uri = URI.parse("#{babeldoc_base_url}#{path}")
      outbound_headers = babeldoc_headers
      user = current_user

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
              read_timeout: PROXY_TIMEOUT,
              open_timeout: 15,
            ) { |http| http.request(req) }

          status = response.code.to_i

          if status >= 200 && status < 300
            parsed = JSON.parse(response.body) rescue nil
            if quota_rollback && parsed && parsed["code"] != 0
              BabeldocLog.rollback_increment!(user)
            end
            render plain: response.body, content_type: "application/json", status: status
          else
            BabeldocLog.rollback_increment!(user) if quota_rollback
            render json: {
                     error: I18n.t("zotero_bridge.errors.babeldoc_service_error"),
                     upstream_status: status,
                     details: safe_error_body(response.body),
                   },
                   status: 502
          end
        rescue Net::OpenTimeout, Net::ReadTimeout
          BabeldocLog.rollback_increment!(user) if quota_rollback
          render json: { error: I18n.t("zotero_bridge.errors.babeldoc_timeout") }, status: 504
        rescue StandardError => e
          BabeldocLog.rollback_increment!(user) if quota_rollback
          Rails.logger.error("ZoteroBridge babeldoc proxy error: #{e.message}")
          render json: { error: I18n.t("zotero_bridge.errors.babeldoc_proxy_error") }, status: 502
        end
      end
    end

    def stream_upload(path)
      if request.content_length.to_i > MAX_UPLOAD_SIZE
        return render json: { error: I18n.t("zotero_bridge.errors.body_too_large") }, status: 413
      end

      uri = URI.parse("#{babeldoc_base_url}#{path}")
      raw_body = request.body.read
      api_key = SiteSetting.zotero_bridge_babeldoc_api_key

      hijack do
        begin
          req = Net::HTTP::Put.new(uri)
          req["Content-Type"] = "application/pdf"
          req["Authorization"] = "Bearer #{api_key}" if api_key.present?
          req.body = raw_body

          response =
            Net::HTTP.start(
              uri.host,
              uri.port,
              use_ssl: uri.scheme == "https",
              read_timeout: PROXY_TIMEOUT,
              open_timeout: 15,
            ) { |http| http.request(req) }

          status = response.code.to_i
          if response.body.present?
            render plain: response.body, content_type: "application/json", status: status
          else
            head status
          end
        rescue Net::OpenTimeout, Net::ReadTimeout
          render json: { error: I18n.t("zotero_bridge.errors.babeldoc_timeout") }, status: 504
        rescue StandardError => e
          Rails.logger.error("ZoteroBridge babeldoc upload error: #{e.message}")
          render json: { error: I18n.t("zotero_bridge.errors.babeldoc_proxy_error") }, status: 502
        end
      end
    end

    def stream_download(path)
      uri = URI.parse("#{babeldoc_base_url}#{path}")

      hijacker = request.env["rack.hijack"]
      unless hijacker
        redirect_to uri.to_s, allow_other_host: true
        return
      end

      io = hijacker.call

      Thread.new do
        begin
          Net::HTTP.start(
            uri.host,
            uri.port,
            use_ssl: uri.scheme == "https",
            open_timeout: 15,
            read_timeout: PROXY_TIMEOUT,
          ) do |http|
            req = Net::HTTP::Get.new(uri)
            req["User-Agent"] = "Discourse-ZoteroBridge"

            http.request(req) do |response|
              status = response.code.to_i
              unless status == 200
                write_json_error(io, status, I18n.t("zotero_bridge.errors.babeldoc_proxy_error"))
                next
              end

              io.write "HTTP/1.1 200 OK\r\n"
              %w[Content-Type Content-Disposition Content-Length].each do |h|
                io.write "#{h}: #{response[h]}\r\n" if response[h]
              end
              io.write "Connection: close\r\n"
              io.write "\r\n"
              io.flush

              response.read_body { |chunk| io.write(chunk) }
            end
          end
        rescue StandardError => e
          Rails.logger.error("ZoteroBridge babeldoc download error: #{e.message}")
        ensure
          io&.close rescue nil
        end
      end

      head 200
    end

    def write_json_error(io, status, message)
      body = { error: message }.to_json
      status_text = Rack::Utils::HTTP_STATUS_CODES[status] || "Error"
      io.write "HTTP/1.1 #{status} #{status_text}\r\n"
      io.write "Content-Type: application/json; charset=utf-8\r\n"
      io.write "Content-Length: #{body.bytesize}\r\n"
      io.write "Connection: close\r\n"
      io.write "\r\n"
      io.write body
      io.flush
    end

    def safe_error_body(body)
      parsed = JSON.parse(body)
      parsed["message"] || parsed["error"] || body.truncate(500)
    rescue StandardError
      body.to_s.truncate(500)
    end
  end
end
