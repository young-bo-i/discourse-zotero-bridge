# frozen_string_literal: true

RSpec.describe DiscourseZoteroBridge::ProxyController do
  fab!(:user) { Fabricate(:user, trust_level: 2) }

  let(:llm_success_body) do
    {
      id: "chatcmpl-test",
      object: "chat.completion",
      choices: [{ index: 0, message: { role: "assistant", content: "Hello!" }, finish_reason: "stop" }],
      usage: { prompt_tokens: 10, completion_tokens: 5, total_tokens: 15 },
    }.to_json
  end

  before do
    SiteSetting.discourse_zotero_bridge_enabled = true
    SiteSetting.zotero_bridge_llm_base_url = "https://api.openai.com"
    SiteSetting.zotero_bridge_llm_api_format = "openai"
    SiteSetting.zotero_bridge_llm_api_key = "sk-test-key"
    SiteSetting.zotero_bridge_llm_model_name = "gpt-4o"
    SiteSetting.zotero_bridge_daily_quota_tl2 = 100
  end

  describe "POST /zotero-bridge/v1/chat/completions" do
    it "requires authentication" do
      post "/zotero-bridge/v1/chat/completions",
           params: { messages: [{ role: "user", content: "hi" }] }.to_json,
           headers: { "CONTENT_TYPE" => "application/json" }

      expect(response.status).to eq(403)
    end

    it "returns 400 for invalid JSON" do
      sign_in(user)

      post "/zotero-bridge/v1/chat/completions",
           params: "not json",
           headers: { "CONTENT_TYPE" => "application/json" }

      expect(response.status).to eq(400)
    end

    it "returns 400 when messages is missing" do
      sign_in(user)

      post "/zotero-bridge/v1/chat/completions",
           params: { foo: "bar" }.to_json,
           headers: { "CONTENT_TYPE" => "application/json" }

      expect(response.status).to eq(400)
    end

    it "returns 429 when quota is exceeded" do
      sign_in(user)
      DiscourseZoteroBridge::UsageLog.create!(
        user_id: user.id,
        used_on: Date.current,
        request_count: 100,
      )

      post "/zotero-bridge/v1/chat/completions",
           params: { messages: [{ role: "user", content: "hi" }] }.to_json,
           headers: { "CONTENT_TYPE" => "application/json" }

      expect(response.status).to eq(429)
      expect(response.parsed_body["error"]).to be_present
    end

    it "proxies non-streaming requests and increments quota" do
      sign_in(user)

      stub_request(:post, "https://api.openai.com/v1/chat/completions").to_return(
        status: 200,
        body: llm_success_body,
        headers: { "Content-Type" => "application/json" },
      )

      post "/zotero-bridge/v1/chat/completions",
           params: { messages: [{ role: "user", content: "hi" }], stream: false }.to_json,
           headers: { "CONTENT_TYPE" => "application/json" }

      expect(response.status).to eq(200)
      json = response.parsed_body
      expect(json["choices"][0]["message"]["content"]).to eq("Hello!")

      log = DiscourseZoteroBridge::UsageLog.find_by(user_id: user.id, used_on: Date.current)
      expect(log.request_count).to eq(1)
    end

    it "uses default model when not specified in request" do
      sign_in(user)

      stub =
        stub_request(:post, "https://api.openai.com/v1/chat/completions")
          .with { |req| JSON.parse(req.body)["model"] == "gpt-4o" }
          .to_return(status: 200, body: llm_success_body, headers: { "Content-Type" => "application/json" })

      post "/zotero-bridge/v1/chat/completions",
           params: { messages: [{ role: "user", content: "hi" }], stream: false }.to_json,
           headers: { "CONTENT_TYPE" => "application/json" }

      expect(stub).to have_been_requested
    end

    it "sends correct Authorization header for OpenAI format" do
      sign_in(user)

      stub =
        stub_request(:post, "https://api.openai.com/v1/chat/completions")
          .with(headers: { "Authorization" => "Bearer sk-test-key" })
          .to_return(status: 200, body: llm_success_body, headers: { "Content-Type" => "application/json" })

      post "/zotero-bridge/v1/chat/completions",
           params: { messages: [{ role: "user", content: "hi" }], stream: false }.to_json,
           headers: { "CONTENT_TYPE" => "application/json" }

      expect(stub).to have_been_requested
    end

    it "returns 502 when LLM returns an error" do
      sign_in(user)

      stub_request(:post, "https://api.openai.com/v1/chat/completions").to_return(
        status: 500,
        body: { error: { message: "Internal server error" } }.to_json,
        headers: { "Content-Type" => "application/json" },
      )

      post "/zotero-bridge/v1/chat/completions",
           params: { messages: [{ role: "user", content: "hi" }], stream: false }.to_json,
           headers: { "CONTENT_TYPE" => "application/json" }

      expect(response.status).to eq(502)
      expect(response.parsed_body["error"]).to eq("LLM service error")
    end

    it "returns 404 when plugin is disabled" do
      SiteSetting.discourse_zotero_bridge_enabled = false
      sign_in(user)

      post "/zotero-bridge/v1/chat/completions",
           params: { messages: [{ role: "user", content: "hi" }] }.to_json,
           headers: { "CONTENT_TYPE" => "application/json" }

      expect(response.status).to eq(404)
    end
  end
end
