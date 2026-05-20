# frozen_string_literal: true

require "date"
require "json"

module DataCruncher
  # Define declarative validation rules and run them against a {Dataset}, getting
  # back a detailed {Report} with row/column references for every failure.
  #
  # @example
  #   validator = DataCruncher::Validator.new do
  #     required  :name, :email
  #     type      :age, :integer
  #     range     :age, min: 18, max: 99
  #     format    :email, :email            # built-in, or pass a Regexp
  #     inclusion :status, in: %w[active inactive]
  #     length    :name, min: 2, max: 60
  #     cross :salary_band do |row|          # cross-field / row-level rule
  #       "salary below band minimum" if row["salary"].to_f < row["band_min"].to_f
  #     end
  #   end
  #
  #   report = validator.validate(dataset)
  #   report.valid?      # => false
  #   report.error_count # => 3
  #   puts report        # human-readable summary
  class Validator
    # Named, ready-to-use regular expressions for {#format}.
    BUILTIN_FORMATS = {
      email: /\A[^@\s]+@[^@\s]+\.[^@\s]+\z/,
      url: %r{\Ahttps?://[^\s]+\z},
      phone: /\A\+?[\d\s().-]{7,}\z/,
      zip: /\A\d{5}(-\d{4})?\z/
    }.freeze

    # A single validation failure.
    Error = Struct.new(:row, :column, :rule, :message, :value, keyword_init: true) do
      def to_s
        location = column ? "row #{row}, column '#{column}'" : "row #{row}"
        "[#{location}] #{message}"
      end
    end

    # The result of {Validator#validate}: the collected {Error}s plus helpers
    # for inspecting and exporting them.
    class Report
      attr_reader :errors, :row_count

      def initialize(errors, row_count)
        @errors = errors
        @row_count = row_count
      end

      def valid?
        @errors.empty?
      end

      def invalid?
        !valid?
      end

      def error_count
        @errors.size
      end

      def errors_for_row(index)
        @errors.select { |e| e.row == index }
      end

      def errors_for_column(column)
        @errors.select { |e| e.column == column.to_s }
      end

      def group_by_row
        @errors.group_by(&:row)
      end

      def group_by_column
        @errors.group_by(&:column)
      end

      def to_a
        @errors.map do |e|
          { row: e.row, column: e.column, rule: e.rule, message: e.message, value: e.value }
        end
      end

      def to_h
        { valid: valid?, row_count: row_count, error_count: error_count, errors: to_a }
      end

      def to_json(*args)
        to_h.to_json(*args)
      end

      def to_s
        return "All #{row_count} row(s) passed validation." if valid?

        lines = ["#{error_count} validation error(s) across #{row_count} row(s):"]
        @errors.each { |e| lines << "  - #{e}" }
        lines.join("\n")
      end
    end

    def initialize(&block)
      @rules = []
      instance_eval(&block) if block_given?
    end

    # ---- DSL ---------------------------------------------------------------

    # Each named column must be present and non-blank.
    def required(*columns)
      columns.each do |col|
        add(col, :required) { |v| "is required" if blank?(v) }
      end
    end

    # The column value must be coercible to +kind+
    # (:integer, :float/:numeric, :date, :boolean, :string).
    def type(column, kind)
      add(column, :type) do |v|
        next if blank?(v)

        "must be a #{kind}" unless valid_type?(v, kind)
      end
    end

    # The numeric column value must fall within +min+/+max+ (inclusive).
    def range(column, min: nil, max: nil)
      add(column, :range) do |v|
        next if blank?(v)

        num = numeric(v)
        if num.nil? then "must be numeric"
        elsif min && num < min then "must be >= #{min}"
        elsif max && num > max then "must be <= #{max}"
        end
      end
    end

    # The column value must match +pattern+ (a Regexp or a {BUILTIN_FORMATS} key).
    def format(column, pattern)
      regex = pattern.is_a?(Symbol) ? BUILTIN_FORMATS.fetch(pattern) : pattern
      add(column, :format) do |v|
        next if blank?(v)

        "has invalid format" unless v.to_s.match?(regex)
      end
    end

    # The column value must be one of an allowed set: +inclusion :status, in: [...]+.
    def inclusion(column, **opts)
      allowed = opts.fetch(:in)
      add(column, :inclusion) do |v|
        next if blank?(v)

        "must be one of: #{allowed.join(", ")}" unless allowed.include?(v)
      end
    end

    # The string length must fall within +min+/+max+.
    def length(column, min: nil, max: nil)
      add(column, :length) do |v|
        next if blank?(v)

        len = v.to_s.length
        if min && len < min then "must be at least #{min} character(s)"
        elsif max && len > max then "must be at most #{max} character(s)"
        end
      end
    end

    # A cross-field / row-level rule. The block receives the whole row and
    # returns an error message (String) when invalid, or nil/false when valid.
    def cross(name, &block)
      @rules << { column: nil, rule: name, kind: :row, check: block }
    end
    alias custom cross

    # ---- Execution ---------------------------------------------------------

    # Run all rules against +dataset+ and return a {Report}.
    def validate(dataset)
      errors = []
      dataset.each_with_index do |row, index|
        @rules.each do |rule|
          message = run_rule(rule, row)
          next unless message

          errors << Error.new(
            row: index,
            column: rule[:column],
            rule: rule[:rule],
            message: message,
            value: rule[:column] ? row[rule[:column]] : nil
          )
        end
      end
      Report.new(errors, dataset.size)
    end

    private

    def run_rule(rule, row)
      if rule[:kind] == :row
        rule[:check].call(row)
      else
        rule[:check].call(row[rule[:column]])
      end
    end

    def add(column, rule_name, &check)
      @rules << { column: column.to_s, rule: rule_name, kind: :column, check: check }
    end

    def blank?(value)
      value.nil? || (value.is_a?(String) && value.strip.empty?)
    end

    def numeric(value)
      return value if value.is_a?(Numeric)

      Float(value.to_s.strip)
    rescue ArgumentError
      nil
    end

    def valid_type?(value, kind)
      case kind.to_sym
      when :integer then integer?(value)
      when :float, :numeric then !numeric(value).nil?
      when :date then date?(value)
      when :boolean then %w[true false 1 0 yes no t f y n].include?(value.to_s.strip.downcase)
      when :string then value.is_a?(String)
      else true
      end
    end

    def integer?(value)
      Integer(value.to_s.strip)
      true
    rescue ArgumentError
      false
    end

    def date?(value)
      Date.parse(value.to_s)
      true
    rescue ArgumentError
      false
    end
  end
end
