# frozen_string_literal: true

RSpec.describe DataCruncher::API do
  let(:endpoint) { "https://api.example.com/users" }

  describe ".fetch" do
    it "parses a top-level JSON array into a Dataset" do
      stub_request(:get, endpoint)
        .to_return(status: 200, body: [{ id: 1, name: "Ada" }].to_json,
                   headers: { "Content-Type" => "application/json" })

      data = described_class.fetch(endpoint)
      expect(data).to be_a(DataCruncher::Dataset)
      expect(data.first).to eq("id" => 1, "name" => "Ada")
    end

    it "extracts records from a nested root key" do
      body = { "data" => [{ "id" => 1 }, { "id" => 2 }], "page" => 1 }.to_json
      stub_request(:get, endpoint).to_return(status: 200, body: body)

      data = described_class.fetch(endpoint, root: "data")
      expect(data.size).to eq(2)
    end

    it "sends query parameters and custom headers" do
      stub = stub_request(:get, "#{endpoint}?role=admin")
             .with(headers: { "Authorization" => "Bearer t0ken" })
             .to_return(status: 200, body: "[]")

      described_class.fetch(endpoint, params: { role: "admin" },
                                      headers: { "Authorization" => "Bearer t0ken" })
      expect(stub).to have_been_requested
    end

    it "raises APIError on a non-success response" do
      stub_request(:get, endpoint).to_return(status: 500, body: "boom")
      expect { described_class.fetch(endpoint) }.to raise_error(DataCruncher::APIError, /500/)
    end

    it "raises APIError on invalid JSON" do
      stub_request(:get, endpoint).to_return(status: 200, body: "not-json")
      expect { described_class.fetch(endpoint) }.to raise_error(DataCruncher::APIError, /JSON/)
    end
  end

  describe "configured client" do
    it "builds URLs from a base_url and path" do
      stub = stub_request(:get, "https://api.example.com/v1/orders").to_return(status: 200, body: "[]")
      client = described_class.new(base_url: "https://api.example.com/v1")
      client.get("/orders")
      expect(stub).to have_been_requested
    end
  end

  describe ".merge" do
    it "enriches local data with remote records" do
      local = DataCruncher::Dataset.from_rows([{ "id" => 1, "name" => "Ada" }])
      remote = DataCruncher::Dataset.from_rows([{ "id" => 1, "plan" => "pro" }])
      merged = described_class.merge(local, remote, on: "id", how: :left)
      expect(merged.first).to include("name" => "Ada", "plan" => "pro")
    end
  end
end
