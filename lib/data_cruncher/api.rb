# frozen_string_literal: true

require "net/http"
require "uri"
require "json"

module DataCruncher
  # Fetch data from any REST API endpoint, parse the JSON response into a
  # {Dataset}, and merge it with local data.
  #
  # Use the class methods for one-off calls, or instantiate with a +base_url+
  # and shared +headers+ (for example an auth token) to make several requests.
  #
  # @example One-off fetch
  #   users = DataCruncher::API.fetch("https://api.example.com/users", root: "data")
  #
  # @example Configured client
  #   client = DataCruncher::API.new(
  #     base_url: "https://api.example.com",
  #     headers: { "Authorization" => "Bearer #{token}" }
  #   )
  #   orders = client.get("/orders", params: { since: "2026-01-01" })
  #
  # @example Enrich local data with a remote lookup
  #   enriched = DataCruncher::API.merge(local_customers, remote_profiles, on: "id", how: :left)
  class API
    DEFAULT_HEADERS = { "Accept" => "application/json" }.freeze

    attr_reader :base_url, :headers

    def initialize(base_url: nil, headers: {})
      @base_url = base_url
      @headers = DEFAULT_HEADERS.merge(headers)
    end

    # Perform a GET against the configured +base_url+ and return a {Dataset}.
    def get(path = "", params: {}, root: nil)
      self.class.fetch(build_url(path), headers: @headers, params: params, root: root)
    end

    class << self
      # Fetch a URL and return a {Dataset}.
      #
      # @param url [String]
      # @param headers [Hash] extra request headers
      # @param params [Hash] query-string parameters
      # @param root [String, Array, nil] key path to the array of records
      # @return [Dataset]
      def fetch(url, headers: {}, params: {}, root: nil, timeout: 30)
        body = request(url, headers: headers, params: params, timeout: timeout)
        parse(body, root: root)
      end

      # Parse a raw JSON string (or already-parsed structure) into a {Dataset}.
      def parse(body, root: nil)
        data = body.is_a?(String) ? JSON.parse(body) : body
        Dataset.from_rows(Reader.extract_rows(data, root))
      rescue JSON::ParserError => e
        raise APIError, "Could not parse API response as JSON: #{e.message}"
      end

      # Merge +remote+ data into +local+ on a shared key (delegates to {Transformer#merge}).
      def merge(local, remote, on:, how: :left)
        Transformer.new(local).merge(remote, on: on, how: how)
      end

      private

      def request(url, headers:, params:, timeout:)
        uri = URI.parse(url)
        uri.query = URI.encode_www_form(params) unless params.nil? || params.empty?

        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl = (uri.scheme == "https")
        http.open_timeout = timeout
        http.read_timeout = timeout

        req = Net::HTTP::Get.new(uri)
        DEFAULT_HEADERS.merge(headers).each { |k, v| req[k] = v }

        response = http.request(req)
        raise APIError, "Request to #{url} failed: #{response.code} #{response.message}" unless response.is_a?(Net::HTTPSuccess)

        response.body
      rescue SocketError, Timeout::Error, Errno::ECONNREFUSED => e
        raise APIError, "Network error contacting #{url}: #{e.message}"
      end
    end

    private

    def build_url(path)
      path = path.to_s
      return path if path.start_with?("http")

      [base_url&.chomp("/"), path.sub(%r{\A/}, "")].compact.join("/")
    end
  end
end
