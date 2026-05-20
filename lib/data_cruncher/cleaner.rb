# frozen_string_literal: true

require "date"

module DataCruncher
  # Cleans a {DataCruncher::Dataset}: de-duplication, missing-value handling,
  # whitespace trimming, type coercion and format normalization (dates, emails,
  # phone numbers).
  #
  # The Cleaner is chainable — every method returns +self+ — and never mutates
  # the dataset you pass in; it works on a deep copy you retrieve with
  # {#result} (aliased {#dataset}).
  #
  # @example
  #   clean = DataCruncher::Cleaner.new(raw)
  #     .trim_whitespace
  #     .remove_duplicates
  #     .handle_missing(strategy: :fill, value: { "country" => "Unknown" })
  #     .normalize_emails(columns: "email")
  #     .normalize_phones(columns: "phone")
  #     .coerce_types("age" => :integer)
  #     .result
  class Cleaner
    # Date formats tried (in order) by {#normalize_dates} before falling back to
    # the lenient +Date.parse+. US month/day ordering is preferred.
    DEFAULT_DATE_FORMATS = [
      "%Y-%m-%d", "%Y/%m/%d", "%m/%d/%Y", "%m/%d/%y",
      "%d-%m-%Y", "%b %d, %Y", "%d %b %Y", "%B %d, %Y"
    ].freeze

    attr_reader :dataset
    alias result dataset

    def initialize(dataset)
      @dataset = dataset.deep_dup
    end

    # Strip leading/trailing whitespace from every string value.
    # @return [self]
    def trim_whitespace
      @dataset.rows.each do |row|
        row.each { |k, v| row[k] = v.strip if v.is_a?(String) }
      end
      self
    end

    # Remove duplicate rows. With +columns:+, only those columns define identity.
    # @return [self]
    def remove_duplicates(columns: nil)
      keys = columns ? Array(columns).map(&:to_s) : @dataset.headers
      seen = {}
      @dataset.rows.select! do |row|
        signature = keys.map { |k| row[k] }
        seen.key?(signature) ? false : (seen[signature] = true)
      end
      self
    end

    # Handle missing values (nil or blank string).
    #
    # @param strategy [Symbol] +:drop+ (remove rows), +:fill+ (replace with
    #   +value+, a scalar or a per-column Hash) or +:interpolate+ (linear
    #   interpolation for numeric columns)
    # @param value [Object, Hash] replacement value for +:fill+
    # @param columns [Array, nil] limit the operation to these columns
    # @return [self]
    def handle_missing(strategy: :drop, value: nil, columns: nil)
      cols = columns ? Array(columns).map(&:to_s) : @dataset.headers
      case strategy.to_sym
      when :drop then drop_missing(cols)
      when :fill then fill_missing(cols, value)
      when :interpolate then interpolate_missing(cols)
      else raise ArgumentError, "Unknown missing-value strategy: #{strategy}"
      end
      self
    end

    # Coerce columns to the given types.
    #
    # @example
    #   coerce_types("age" => :integer, "price" => :float, "active" => :boolean)
    # @param schema [Hash{String,Symbol=>Symbol}] column => type
    #   (:integer, :float, :string, :boolean, :date)
    # @return [self]
    def coerce_types(schema)
      schema = schema.transform_keys(&:to_s)
      @dataset.rows.each do |row|
        schema.each do |col, type|
          row[col] = coerce(row[col], type) if row.key?(col)
        end
      end
      self
    end

    # Parse and reformat date columns to a consistent string format.
    #
    # Each value is tried against +input_formats+ (defaulting to
    # {DEFAULT_DATE_FORMATS}) and finally the lenient +Date.parse+. Values that
    # cannot be parsed are left untouched.
    #
    # @param columns [Array, String]
    # @param format [String] output +strftime+ format
    # @param input_formats [Array<String>, nil] candidate parse formats
    # @return [self]
    def normalize_dates(columns:, format: "%Y-%m-%d", input_formats: nil)
      candidates = Array(input_formats).empty? ? DEFAULT_DATE_FORMATS : Array(input_formats)
      Array(columns).map(&:to_s).each do |col|
        update_column(col) do |v|
          next v if blank?(v)

          parsed = parse_date(v.to_s, candidates)
          parsed ? parsed.strftime(format) : v
        end
      end
      self
    end

    # Lower-case and trim email addresses.
    # @return [self]
    def normalize_emails(columns:)
      Array(columns).map(&:to_s).each do |col|
        update_column(col) { |v| blank?(v) ? v : v.to_s.strip.downcase }
      end
      self
    end

    # Normalize phone numbers. US/NANP numbers become +1 (XXX) XXX-XXXX;
    # otherwise the digits are returned in a simple E.164-style form.
    # @return [self]
    def normalize_phones(columns:, country: :us)
      Array(columns).map(&:to_s).each do |col|
        update_column(col) { |v| blank?(v) ? v : format_phone(v.to_s, country) }
      end
      self
    end

    private

    def update_column(col)
      @dataset.rows.each do |row|
        row[col] = yield(row[col]) if row.key?(col)
      end
    end

    def blank?(value)
      value.nil? || (value.is_a?(String) && value.strip.empty?)
    end

    def drop_missing(cols)
      @dataset.rows.reject! { |row| cols.any? { |c| blank?(row[c]) } }
    end

    def fill_missing(cols, value)
      @dataset.rows.each do |row|
        cols.each do |c|
          next unless blank?(row[c])

          row[c] = value.is_a?(Hash) ? (value[c] || value[c.to_sym]) : value
        end
      end
    end

    def interpolate_missing(cols)
      cols.each do |col|
        filled = interpolate(@dataset.column(col).map { |v| to_f_or_nil(v) })
        @dataset.rows.each_with_index do |row, i|
          row[col] = filled[i] if blank?(row[col]) && filled[i]
        end
      end
    end

    # Linearly interpolate +nil+ gaps that sit between two known numeric values.
    def interpolate(numeric)
      numeric.each_index do |i|
        next unless numeric[i].nil?

        prev_i = (0...i).to_a.reverse.find { |j| numeric[j] }
        next_i = ((i + 1)...numeric.size).find { |j| numeric[j] }
        next unless prev_i && next_i

        slope = (numeric[next_i] - numeric[prev_i]) / (next_i - prev_i)
        numeric[i] = numeric[prev_i] + (slope * (i - prev_i))
      end
      numeric
    end

    def parse_date(value, candidates)
      candidates.each do |fmt|
        return Date.strptime(value, fmt)
      rescue ArgumentError
        next
      end
      begin
        Date.parse(value)
      rescue ArgumentError
        nil
      end
    end

    def to_f_or_nil(value)
      return nil if blank?(value)

      Float(value)
    rescue ArgumentError, TypeError
      nil
    end

    def coerce(value, type)
      return value if value.nil?

      case type.to_sym
      when :integer then int_or(value)
      when :float then float_or(value)
      when :string then value.to_s
      when :boolean then to_boolean(value)
      when :date then date_or(value)
      else value
      end
    end

    def int_or(value)
      Integer(value.to_s.strip)
    rescue ArgumentError
      value
    end

    def float_or(value)
      Float(value.to_s.strip)
    rescue ArgumentError
      value
    end

    def date_or(value)
      Date.parse(value.to_s)
    rescue ArgumentError
      value
    end

    def to_boolean(value)
      case value.to_s.strip.downcase
      when "true", "1", "yes", "y", "t" then true
      when "false", "0", "no", "n", "f" then false
      else value
      end
    end

    def format_phone(value, country)
      digits = value.gsub(/\D/, "")
      if %i[us nanp].include?(country)
        digits = digits.sub(/\A1/, "") if digits.length == 11 && digits.start_with?("1")
        return value unless digits.length == 10

        "+1 (#{digits[0..2]}) #{digits[3..5]}-#{digits[6..9]}"
      else
        "+#{digits}"
      end
    end
  end
end
