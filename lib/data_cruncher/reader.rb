# frozen_string_literal: true

require "csv"
require "json"

module DataCruncher
  # Reads CSV, TSV, JSON and Excel (.xlsx) files into a {DataCruncher::Dataset}.
  #
  # The file format is auto-detected from the extension but can be overridden
  # with the +format:+ keyword.
  #
  # @example
  #   DataCruncher::Reader.read("sales.csv")
  #   DataCruncher::Reader.read("export.txt", format: :tsv)
  #   DataCruncher::Reader.read("users.json", root: "data")
  module Reader
    module_function

    # Maps a file extension to a format symbol.
    FORMATS = {
      ".csv" => :csv,
      ".tsv" => :tsv,
      ".txt" => :tsv,
      ".json" => :json,
      ".xlsx" => :excel,
      ".xlsm" => :excel
    }.freeze

    # Read +path+ into a {Dataset}.
    #
    # @param path [String]
    # @param format [Symbol, nil] override auto-detection (:csv, :tsv, :json, :excel)
    # @return [Dataset]
    def read(path, format: nil, **opts)
      raise FileNotFoundError, "No such file: #{path}" unless File.exist?(path)

      format ||= detect_format(path)
      case format.to_sym
      when :csv then read_csv(path, **opts)
      when :tsv then read_tsv(path, **opts)
      when :json then read_json(path, **opts)
      when :excel, :xlsx then read_excel(path, **opts)
      else
        raise UnsupportedFormatError, "Unsupported format: #{format}"
      end
    end

    # @return [Symbol] the format inferred from the file extension
    def detect_format(path)
      ext = File.extname(path).downcase
      FORMATS.fetch(ext) do
        raise UnsupportedFormatError, "Cannot detect format for #{path}"
      end
    end

    def read_csv(path, col_sep: ",", **)
      table = CSV.read(path, headers: true, col_sep: col_sep, skip_blanks: true)
      Dataset.new(headers: table.headers.compact.map(&:to_s), rows: table.map(&:to_h))
    rescue CSV::MalformedCSVError => e
      raise ParseError, "Malformed CSV (#{path}): #{e.message}"
    end

    def read_tsv(path, **opts)
      read_csv(path, col_sep: "\t", **opts)
    end

    def read_json(path, root: nil, **)
      data = JSON.parse(File.read(path))
      Dataset.from_rows(extract_rows(data, root))
    rescue JSON::ParserError => e
      raise ParseError, "Invalid JSON (#{path}): #{e.message}"
    end

    def read_excel(path, sheet: nil, **)
      require "rubyXL"

      workbook = RubyXL::Parser.parse(path)
      worksheet = sheet ? workbook[sheet] : workbook.worksheets.first
      raise ParseError, "No worksheet found in #{path}" unless worksheet

      matrix = worksheet.filter_map { |row| row&.cells&.map { |cell| cell&.value } }
      matrix_to_dataset(matrix)
    rescue LoadError
      raise Error, "Reading Excel files requires the 'rubyXL' gem. Add it to your Gemfile."
    end

    # Turn a 2-D array (first row = headers) into a {Dataset}.
    def matrix_to_dataset(matrix)
      return Dataset.new if matrix.empty?

      headers = matrix.shift.map(&:to_s)
      rows = matrix.map do |cells|
        headers.each_with_index.with_object({}) { |(h, i), hash| hash[h] = cells[i] }
      end
      Dataset.new(headers: headers, rows: rows)
    end

    # Pull the array of records out of a parsed JSON document. Supports a bare
    # array, a wrapper object (uses +root+ or the first array value found), or a
    # single object (treated as one row).
    def extract_rows(data, root = nil)
      data = data.dig(*Array(root)) if root
      case data
      when Array then data
      when Hash then data.values.find { |v| v.is_a?(Array) } || [data]
      else
        raise ParseError, "Unexpected JSON structure: #{data.class}"
      end
    end
  end
end
