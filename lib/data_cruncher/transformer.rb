# frozen_string_literal: true

module DataCruncher
  # Filter, sort, group, aggregate, pivot and merge {Dataset}s.
  #
  # Row/column operations ({#filter}, {#where}, {#sort_by}, {#select},
  # {#reject}, {#limit}) return a new Transformer so they can be chained; call
  # {#dataset} to extract the result. Aggregating operations ({#group_by},
  # {#aggregate}, {#pivot}, {#merge}) return a {Dataset} directly.
  #
  # @example Chainable row/column ops
  #   top = DataCruncher::Transformer.new(sales)
  #     .where("region" => "West")
  #     .sort_by("amount", direction: :desc)
  #     .limit(10)
  #     .dataset
  #
  # @example Grouped aggregation
  #   summary = DataCruncher::Transformer.new(sales)
  #     .aggregate(group_by: "region", sum: "amount", avg: "amount", count: true)
  class Transformer
    attr_reader :dataset

    def initialize(dataset)
      @dataset = dataset
    end

    # Keep rows for which the block returns truthy.
    # @return [Transformer]
    def filter(&block)
      chain(@dataset.rows.select(&block))
    end
    alias select_rows filter

    # Drop rows for which the block returns truthy.
    # @return [Transformer]
    def reject(&block)
      chain(@dataset.rows.reject(&block))
    end

    # Keep rows matching a set of equality (or Proc) conditions.
    #
    # @example
    #   where("region" => "West", "amount" => ->(v) { v.to_f > 100 })
    # @return [Transformer]
    def where(conditions)
      conditions = conditions.transform_keys(&:to_s)
      filter do |row|
        conditions.all? { |k, v| v.respond_to?(:call) ? v.call(row[k]) : row[k] == v }
      end
    end

    # Sort by a column. Numeric-looking values sort numerically; everything else
    # sorts as text (numbers before text), so mixed columns never raise.
    # @return [Transformer]
    def sort_by(column, direction: :asc)
      key = column.to_s
      sorted = @dataset.rows.sort_by { |row| sortable(row[key]) }
      sorted.reverse! if direction.to_sym == :desc
      chain(sorted)
    end

    # Project a subset of columns into a new dataset.
    # @return [Transformer]
    def select(*columns)
      self.class.new(@dataset.select_columns(*columns))
    end

    # Keep only the first +n+ rows.
    # @return [Transformer]
    def limit(num)
      chain(@dataset.rows.first(num))
    end

    # Group rows by one or more columns.
    # @return [Hash{Object=>Dataset}] key (or array of keys) => Dataset
    def group_by(*columns)
      keys = columns.flatten.map(&:to_s)
      grouped = @dataset.rows.group_by do |row|
        values = keys.map { |k| row[k] }
        values.size == 1 ? values.first : values
      end
      grouped.transform_values { |rows| Dataset.new(headers: @dataset.headers, rows: rows) }
    end

    # Aggregate, optionally grouped by one or more columns.
    #
    # @example
    #   aggregate(group_by: "region", sum: "amount", avg: "amount", count: true)
    #   aggregate(sum: %w[amount qty])   # whole-dataset totals
    # @return [Dataset] one row per group with +count+, +sum_*+, +avg_*+,
    #   +min_*+ and +max_*+ columns as requested
    def aggregate(group_by: nil, count: false, sum: nil, avg: nil, min: nil, max: nil)
      group_keys = group_by ? Array(group_by).map(&:to_s) : []
      groups =
        if group_keys.empty?
          { [] => @dataset.rows }
        else
          @dataset.rows.group_by { |row| group_keys.map { |k| row[k] } }
        end

      rows = groups.map do |key, group_rows|
        record = {}
        group_keys.each_with_index { |k, i| record[k] = key[i] }
        record["count"] = group_rows.size if count
        apply_agg(record, "sum", sum, group_rows, &:sum)
        apply_agg(record, "avg", avg, group_rows) { |nums| nums.empty? ? nil : (nums.sum.to_f / nums.size) }
        apply_agg(record, "min", min, group_rows, &:min)
        apply_agg(record, "max", max, group_rows, &:max)
        record
      end

      Dataset.from_rows(rows)
    end

    # Build a pivot table.
    #
    # @example
    #   pivot(rows: "region", columns: "product", values: "amount", aggregate: :sum)
    # @return [Dataset]
    def pivot(rows:, columns:, values:, aggregate: :sum)
      row_key = rows.to_s
      col_key = columns.to_s
      val_key = values.to_s
      column_values = @dataset.column(col_key).compact.uniq.sort_by(&:to_s)

      result_rows = @dataset.rows.group_by { |r| r[row_key] }.map do |rk, group|
        record = { row_key => rk }
        column_values.each do |cv|
          nums = group.select { |r| r[col_key] == cv }.map { |r| to_number(r[val_key]) }.compact
          record[cv.to_s] = aggregate_values(nums, aggregate)
        end
        record
      end

      Dataset.new(headers: [row_key, *column_values.map(&:to_s)], rows: result_rows)
    end

    # Join with another dataset on a shared key.
    #
    # @param other [Dataset]
    # @param on [String, Symbol] the join key, present in both datasets
    # @param how [Symbol] :inner, :left, :right or :outer
    # @return [Dataset]
    def merge(other, on:, how: :inner)
      key = on.to_s
      right_index = other.rows.group_by { |r| r[key] }
      merged = []

      @dataset.rows.each do |left|
        matches = right_index[left[key]] || []
        if matches.empty?
          merged << left.dup if %i[left outer].include?(how)
        else
          matches.each { |right| merged << left.merge(right) }
        end
      end

      if %i[right outer].include?(how)
        left_keys = @dataset.rows.map { |r| r[key] }
        other.rows.each { |right| merged << right.dup unless left_keys.include?(right[key]) }
      end

      Dataset.from_rows(merged)
    end

    private

    def chain(rows)
      self.class.new(Dataset.new(headers: @dataset.headers, rows: rows))
    end

    def apply_agg(record, label, spec, group_rows)
      return unless spec

      Array(spec).map(&:to_s).each do |col|
        nums = group_rows.map { |r| to_number(r[col]) }.compact
        record["#{label}_#{col}"] = yield(nums)
      end
    end

    def aggregate_values(nums, operation)
      return (operation.to_sym == :count ? 0 : nil) if nums.empty?

      case operation.to_sym
      when :sum then nums.sum
      when :avg then nums.sum.to_f / nums.size
      when :min then nums.min
      when :max then nums.max
      when :count then nums.size
      else raise ArgumentError, "Unknown pivot aggregate: #{operation}"
      end
    end

    def to_number(value)
      return nil if value.nil? || (value.is_a?(String) && value.strip.empty?)
      return value if value.is_a?(Numeric)

      Float(value.to_s)
    rescue ArgumentError
      nil
    end

    # Sort key that keeps numbers and text in separate, internally-ordered bands.
    def sortable(value)
      num = to_number(value)
      num.nil? ? [1, value.to_s] : [0, num]
    end
  end
end
