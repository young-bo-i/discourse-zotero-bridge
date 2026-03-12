# frozen_string_literal: true

module DiscourseZoteroBridge
  class ProxyController < ::ApplicationController
    requires_plugin PLUGIN_NAME
    requires_login

    skip_before_action :verify_authenticity_token

    CRLF = "\r\n"
    LLM_TIMEOUT = 120
    MAX_CONCURRENT_STREAMS = 20

    API_FORMAT_PATHS = { "openai" => "/v1/chat/completions", "anthropic" => "/v1/messages" }.freeze

    @active_streams = 0
    @stream_mutex = Mutex.new

    def self.acquire_stream_slot
      @stream_mutex.synchronize do
        return false if @active_streams >= MAX_CONCURRENT_STREAMS
        @active_streams += 1
        true
      end
    end

    def self.release_stream_slot
      @stream_mutex.synchronize { @active_streams -= 1 }
    end

    def self.active_stream_count
      @stream_mutex.synchronize { @active_streams }
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
      body = JSON.parse(request.body.read)

      if !body.is_a?(Hash) || !body["messages"].is_a?(Array)
        render json: { error: "Invalid request: messages array is required" }, status: 400
        return nil
      end

      body
    rescue JSON::ParserError
      render json: { error: "Invalid JSON body" }, status: 400
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
                     error: "LLM service error",
                     status: response.code.to_i,
                     details: safe_error_body(response.body),
                   },
                   status: 502
          end
        rescue Net::OpenTimeout, Net::ReadTimeout
          render json: { error: "LLM service timeout" }, status: 504
        rescue StandardError => e
          Rails.logger.error("ZoteroBridge proxy error: #{e.message}")
          render json: { error: "Proxy error" }, status: 502
        end
      end
    end

    def stream_proxy(uri, body)
      unless self.class.acquire_stream_slot
        return(
          render json: { error: I18n.t("zotero_bridge.errors.service_busy") }, status: 503
        )
      end

      io = request.env["rack.hijack"].call
      cors_origin = request.env["HTTP_ORIGIN"]
      outbound_headers = llm_headers

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
                response.read_body do |chunk|
                  write_raw_chunk(io, chunk)
                end
                finish_chunks(io)
              else
                error_body = response.body
                write_error_response(io, 502, safe_error_body(error_body))
              end
            end
          end
        rescue Net::OpenTimeout, Net::ReadTimeout
          write_error_response(io, 504, "LLM service timeout")
        rescue Errno::EPIPE, IOError
          # client disconnected
        rescue StandardError => e
          Rails.logger.error("ZoteroBridge stream error: #{e.message}")
          begin
            write_error_response(io, 502, "Proxy error")
          rescue StandardError
          end
        ensure
          self.class.release_stream_slot
          begin
            io.close
          rescue StandardError
          end
        end
      end

      render plain: "", status: 418
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
      if cors_origin.present?
        io.write "Access-Control-Allow-Origin: #{cors_origin}"
        io.write CRLF
        io.write "Access-Control-Allow-Credentials: true"
        io.write CRLF
      end
      io.write CRLF
      io.flush
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
