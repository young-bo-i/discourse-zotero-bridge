# frozen_string_literal: true

module DiscourseZoteroBridge
  class ProxyController < ::ApplicationController
    requires_plugin PLUGIN_NAME
    requires_login

    skip_before_action :verify_authenticity_token

    CRLF = "\r\n"
    LLM_TIMEOUT = 120
    MAX_CONCURRENT_STREAMS = 20
    MAX_BODY_SIZE = 1.megabyte

    API_FORMAT_PATHS = { "openai" => "/v1/chat/completions", "anthropic" => "/v1/messages" }.freeze

    STREAM_COUNTER_KEY = "zotero_bridge:active_streams"
    STREAM_SLOT_TTL = LLM_TIMEOUT + 30

    ACQUIRE_SLOT_SCRIPT = <<~LUA
      local current = redis.call('incr', KEYS[1])
      if current > tonumber(ARGV[1]) then
        redis.call('decr', KEYS[1])
        return 0
      end
      redis.call('expire', KEYS[1], tonumber(ARGV[2]))
      return 1
    LUA

    RELEASE_SLOT_SCRIPT = <<~LUA
      local val = redis.call('decr', KEYS[1])
      if val <= 0 then
        redis.call('del', KEYS[1])
      end
      return val
    LUA

    def self.acquire_stream_slot
      Discourse.redis.eval(
        ACQUIRE_SLOT_SCRIPT,
        keys: [STREAM_COUNTER_KEY],
        argv: [MAX_CONCURRENT_STREAMS, STREAM_SLOT_TTL],
      ) == 1
    end

    def self.release_stream_slot
      Discourse.redis.eval(RELEASE_SLOT_SCRIPT, keys: [STREAM_COUNTER_KEY])
    end

    def self.active_stream_count
      Discourse.redis.get(STREAM_COUNTER_KEY).to_i
    end

    def chat_completions
      body = parse_request_body
      return if body.nil?

      quota_result = UsageLog.increment_and_check!(current_user)
      unless quota_result[:allowed]
        return(
          render json: {
                   error: I18n.t("zotero_bridge.errors.quota_exceeded"),
                   used_today: quota_result[:used],
                   daily_quota: quota_result[:quota],
                 },
                 status: 429
        )
      end

      body["model"] ||= SiteSetting.zotero_bridge_llm_model_name
      streaming = body.delete("stream") == true
      endpoint_uri = URI.parse(full_endpoint_url)

      if streaming
        stream_proxy(endpoint_uri, body)
      else
        non_stream_proxy(endpoint_uri, body)
      end
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

      if !body.is_a?(Hash) || !body["messages"].is_a?(Array)
        render json: { error: I18n.t("zotero_bridge.errors.invalid_messages") }, status: 400
        return nil
      end

      body
    rescue JSON::ParserError
      render json: { error: I18n.t("zotero_bridge.errors.invalid_json") }, status: 400
      nil
    end

    def full_endpoint_url
      base = SiteSetting.zotero_bridge_llm_base_url.chomp("/")
      format = SiteSetting.zotero_bridge_llm_api_format
      path =
        if format == "custom"
          SiteSetting.zotero_bridge_llm_custom_path
        else
          API_FORMAT_PATHS.fetch(format, "")
        end
      "#{base}#{path}"
    end

    def llm_headers
      headers = { "Content-Type" => "application/json" }
      api_key = SiteSetting.zotero_bridge_llm_api_key

      case SiteSetting.zotero_bridge_llm_api_format
      when "anthropic"
        headers["x-api-key"] = api_key
        headers["anthropic-version"] = "2023-06-01"
      else
        headers["Authorization"] = "Bearer #{api_key}"
      end

      headers
    end

    def non_stream_proxy(uri, body)
      outbound_headers = llm_headers
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
              read_timeout: LLM_TIMEOUT,
              open_timeout: 30,
            ) { |http| http.request(req) }

          if response.code.to_i >= 200 && response.code.to_i < 300
            render json: response.body, status: response.code.to_i
          else
            render json: {
                     error: I18n.t("zotero_bridge.errors.llm_service_error"),
                     status: response.code.to_i,
                     details: safe_error_body(response.body),
                   },
                   status: 502
          end
        rescue Net::OpenTimeout, Net::ReadTimeout
          render json: { error: I18n.t("zotero_bridge.errors.llm_timeout") }, status: 504
        rescue StandardError => e
          Rails.logger.error("ZoteroBridge proxy error: #{e.message}")
          render json: { error: I18n.t("zotero_bridge.errors.proxy_error") }, status: 502
        end
      end
    end

    def stream_proxy(uri, body)
      unless self.class.acquire_stream_slot
        return(
          render json: { error: I18n.t("zotero_bridge.errors.service_busy") }, status: 503
        )
      end

      hijacker = request.env["rack.hijack"]
      unless hijacker
        self.class.release_stream_slot
        return render json: { error: I18n.t("zotero_bridge.errors.streaming_not_supported") }, status: 500
      end

      io = hijacker.call
      cors_origin = request.env["HTTP_ORIGIN"]
      outbound_headers = llm_headers
      timeout_msg = I18n.t("zotero_bridge.errors.llm_timeout")
      proxy_err_msg = I18n.t("zotero_bridge.errors.proxy_error")

      thread =
        Thread.new do
          begin
            payload = body.merge("stream" => true).to_json
            req = Net::HTTP::Post.new(uri, outbound_headers)
            req.body = payload

            Net::HTTP.start(
              uri.host,
              uri.port,
              use_ssl: uri.scheme == "https",
              read_timeout: LLM_TIMEOUT,
              open_timeout: 30,
            ) do |http|
              http.request(req) do |response|
                if response.code.to_i >= 200 && response.code.to_i < 300
                  write_stream_headers(io, cors_origin)
                  response.read_body { |chunk| write_raw_chunk(io, chunk) }
                  finish_chunks(io)
                else
                  error_body = response.body
                  write_error_response(io, 502, safe_error_body(error_body))
                end
              end
            end
          rescue Net::OpenTimeout, Net::ReadTimeout
            write_error_response(io, 504, timeout_msg)
          rescue Errno::EPIPE, IOError
            # client disconnected
          rescue StandardError => e
            Rails.logger.error("ZoteroBridge stream error: #{e.class} - #{e.message}")
            write_error_response(io, 502, proxy_err_msg) rescue nil
          ensure
            self.class.release_stream_slot
            io&.close rescue nil
          end
        end
      thread.name = "zotero-bridge-stream"

      head 200
    end

    def write_stream_headers(io, cors_origin = nil)
      io.write "HTTP/1.1 200 OK"
      io.write CRLF
      io.write "Content-Type: text/event-stream; charset=utf-8"
      io.write CRLF
      io.write "Transfer-Encoding: chunked"
      io.write CRLF
      io.write "Cache-Control: no-cache, no-store, must-revalidate"
      io.write CRLF
      io.write "Connection: close"
      io.write CRLF
      io.write "X-Accel-Buffering: no"
      io.write CRLF
      io.write "X-Content-Type-Options: nosniff"
      io.write CRLF
      if cors_origin.present? && valid_cors_origin?(cors_origin)
        io.write "Access-Control-Allow-Origin: #{cors_origin}"
        io.write CRLF
        io.write "Access-Control-Allow-Credentials: true"
        io.write CRLF
      end
      io.write CRLF
      io.flush
    end

    def valid_cors_origin?(origin)
      allowed = URI.parse(Discourse.base_url)
      requested = URI.parse(origin)
      allowed.scheme == requested.scheme && allowed.host == requested.host && allowed.port == requested.port
    rescue URI::InvalidURIError
      false
    end

    def write_raw_chunk(io, data)
      data.force_encoding("UTF-8")
      io.write data.bytesize.to_s(16)
      io.write CRLF
      io.write data
      io.write CRLF
      io.flush
    end

    def finish_chunks(io)
      io.write "0"
      io.write CRLF
      io.write CRLF
      io.flush
    end

    def write_error_response(io, status, message)
      body = { error: message }.to_json
      status_text = Rack::Utils::HTTP_STATUS_CODES[status] || "Error"
      io.write "HTTP/1.1 #{status} #{status_text}"
      io.write CRLF
      io.write "Content-Type: application/json; charset=utf-8"
      io.write CRLF
      io.write "Content-Length: #{body.bytesize}"
      io.write CRLF
      io.write "Connection: close"
      io.write CRLF
      io.write CRLF
      io.write body
      io.flush
    end

    def safe_error_body(body)
      parsed = JSON.parse(body)
      parsed["error"]&.is_a?(Hash) ? parsed["error"]["message"] : parsed["error"] || body.truncate(500)
    rescue StandardError
      body.to_s.truncate(500)
    end
  end
end
