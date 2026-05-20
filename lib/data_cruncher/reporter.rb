# frozen_string_literal: true

require "csv"
require "json"

module DataCruncher
  # Render a {Dataset} as CSV, JSON, or a formatted terminal table.
  #
  # Each format method returns the rendered String, and writes it to disk
  # instead when a +path:+ is given (returning the path).
  #
  # @example
  #   DataCruncher::Reporter.to_csv(data, path: "out.csv")
  #   puts DataCruncher::Reporter.to_table(data, title: "Q1 Sales", limit: 20)
  module Reporter
    module_function

    # Render +dataset+ in +format+ (:csv, :json, :table).
    def render(dataset, format:, **opts)
      case format.to_sym
      when :csv then to_csv(dataset, **opts)
      when :json then to_json(dataset, **opts)
      when :table, :terminal then to_table(dataset, **opts)
      else raise UnsupportedFormatError, "Unknown report format: #{format} (use :csv, :json or :table)"
      end
    end

    # @return [String, String] CSV text, or the path written to
    def to_csv(dataset, path: nil, **)
      output = CSV.generate do |csv|
        csv << dataset.headers
        dataset.each { |row| csv << dataset.headers.map { |h| row[h] } }
      end
      write(path, output)
    end

    # @return [String, String] JSON text, or the path written to
    def to_json(dataset, path: nil, pretty: true, **)
      data = dataset.to_a
      output = pretty ? JSON.pretty_generate(data) : JSON.generate(data)
      write(path, output)
    end

    # Render an ASCII table using the +terminal-table+ gem.
    # @return [String]
    def to_table(dataset, title: nil, limit: nil, **)
      require "terminal-table"

      rows = limit ? dataset.rows.first(limit) : dataset.rows
      table = Terminal::Table.new do |t|
        t.title = title if title
        t.headings = dataset.headers
        rows.each { |row| t.add_row(dataset.headers.map { |h| row[h] }) }
      end
      footer = limit && dataset.size > limit ? "\n(showing #{limit} of #{dataset.size} rows)" : ""
      "#{table}#{footer}"
    rescue LoadError
      raise Error, "Terminal table output requires the 'terminal-table' gem. Add it to your Gemfile."
    end

    def write(path, content)
      return content unless path

      File.write(path, content)
      path
    end
  end
end
