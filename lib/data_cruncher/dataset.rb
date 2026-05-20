# frozen_string_literal: true

module DataCruncher
  # A unified, in-memory tabular data structure shared by every module.
  #
  # Internally a Dataset is an ordered list of column names (+headers+) plus an
  # array of rows, where each row is a +Hash+ keyed by the (stringified) column
  # name. Keys are always stored as strings, so data read from CSV, TSV, JSON,
  # Excel and APIs all behaves identically downstream.
  #
  # @example
  #   ds = DataCruncher::Dataset.from_rows([
  #     { "name" => "Ada",  "role" => "Engineer" },
  #     { "name" => "Linus", "role" => "Engineer" }
  #   ])
  #   ds.headers       # => ["name", "role"]
  #   ds.size          # => 2
  #   ds.column("name") # => ["Ada", "Linus"]
  class Dataset
    include Enumerable

    # @return [Array<String>] ordered column names
    attr_reader :headers
    # @return [Array<Hash>] rows, each a Hash keyed by column name
    attr_reader :rows

    # @param headers [Array] column names (coerced to strings)
    # @param rows [Array<Hash>] rows keyed by column name
    def initialize(headers: [], rows: [])
      @headers = Array(headers).map(&:to_s)
      @rows = rows.map { |row| stringify_row(row) }
      @headers = @rows.flat_map(&:keys).uniq if @headers.empty? && !@rows.empty?
    end

    # Build a Dataset from an array of hashes, inferring column order from the
    # order keys first appear.
    #
    # @param rows [Array<Hash>]
    # @return [Dataset]
    def self.from_rows(rows)
      rows = Array(rows)
      headers = rows.each_with_object([]) do |row, acc|
        row.each_key { |k| acc << k.to_s unless acc.include?(k.to_s) }
      end
      new(headers: headers, rows: rows)
    end

    # Iterate over rows. Returns an Enumerator without a block.
    def each(&block)
      return enum_for(:each) unless block_given?

      @rows.each(&block)
    end

    # @return [Integer] number of rows
    def size
      @rows.size
    end
    alias length size

    # @return [Boolean] true when there are no rows
    def empty?
      @rows.empty?
    end

    # @return [Hash, nil] the row at +index+
    def [](index)
      @rows[index]
    end

    # Append a row (Hash). Unknown keys extend the header list.
    # @return [self]
    def <<(row)
      row = stringify_row(row)
      row.each_key { |k| @headers << k unless @headers.include?(k) }
      @rows << row
      self
    end
    alias add_row <<

    # @return [Array] every value in column +name+, in row order
    def column(name)
      key = name.to_s
      @rows.map { |row| row[key] }
    end

    # Add or overwrite a column. Provide an array of +values+ or a block that
    # receives +(row, index)+ and returns the cell value.
    # @return [self]
    def add_column(name, values = nil)
      key = name.to_s
      @headers << key unless @headers.include?(key)
      @rows.each_with_index do |row, i|
        row[key] = block_given? ? yield(row, i) : Array(values)[i]
      end
      self
    end

    # @return [Dataset] a new dataset containing only the named columns
    def select_columns(*names)
      keys = names.flatten.map(&:to_s)
      self.class.new(
        headers: keys,
        rows: @rows.map { |row| keys.to_h { |k| [k, row[k]] } }
      )
    end

    # @return [Array<Hash>] a shallow copy of the rows
    def to_a
      @rows.map(&:dup)
    end
    alias to_array to_a

    # @return [Hash] +{ headers:, rows: }+ representation
    def to_h
      { headers: @headers.dup, rows: to_a }
    end

    # @return [Dataset] a deep copy safe to mutate independently
    def deep_dup
      self.class.new(headers: @headers.dup, rows: @rows.map(&:dup))
    end

    def ==(other)
      other.is_a?(Dataset) && other.headers == headers && other.rows == rows
    end

    def inspect
      "#<DataCruncher::Dataset headers=#{@headers.inspect} rows=#{size}>"
    end

    private

    def stringify_row(row)
      row.each_with_object({}) { |(k, v), h| h[k.to_s] = v }
    end
  end
end
