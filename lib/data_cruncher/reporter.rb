# frozen_string_literal: true

require "csv"
require "json"

module DataCruncher
  # Render a {Dataset} as CSV, JSON, a formatted terminal table, or a PDF.
  #
  # Each format method returns the rendered String, and writes it to disk
  # instead when a +path:+ is given (returning the path).
  #
  # @example
  #   DataCruncher::Reporter.to_csv(data, path: "out.csv")
  #   puts DataCruncher::Reporter.to_table(data, title: "Q1 Sales", limit: 20)
  #   DataCruncher::Reporter.to_pdf(data, path: "report.pdf", title: "Q1 Sales")
  module Reporter
    module_function

    # Render +dataset+ in +format+ (:csv, :json, :table, :pdf).
    def render(dataset, format:, **opts)
      case format.to_sym
      when :csv then to_csv(dataset, **opts)
      when :json then to_json(dataset, **opts)
      when :table, :terminal then to_table(dataset, **opts)
      when :pdf then to_pdf(dataset, **opts)
      else raise UnsupportedFormatError, "Unknown report format: #{format} (use :csv, :json, :table or :pdf)"
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

    # Render a PDF document with a heading and a styled table, using the
    # +prawn+ and +prawn-table+ gems.
    # @return [String, String] PDF binary data, or the path written to
    def to_pdf(dataset, path: nil, title: nil, **)
      require "prawn"
      require "prawn/table"

      pdf = Prawn::Document.new(page_size: "A4", margin: 36)
      render_pdf_title(pdf, title) if title
      render_pdf_table(pdf, dataset)
      write(path, pdf.render, binary: true)
    rescue LoadError
      raise Error, "PDF output requires the 'prawn' and 'prawn-table' gems. Add them to your Gemfile."
    end

    def render_pdf_title(pdf, title)
      pdf.text(title, size: 18, style: :bold)
      pdf.move_down(12)
    end

    def render_pdf_table(pdf, dataset)
      if dataset.headers.empty?
        pdf.text("No data.")
        return
      end

      body = dataset.rows.map { |row| dataset.headers.map { |h| row[h].to_s } }
      pdf.table([dataset.headers] + body, header: true, width: pdf.bounds.width) do |t|
        t.cells.padding = 6
        t.cells.borders = %i[bottom]
        t.row(0).font_style = :bold
        t.row(0).background_color = "EEEEEE"
      end
    end

    def write(path, content, binary: false)
      return content unless path

      binary ? File.binwrite(path, content) : File.write(path, content)
      path
    end
  end
end
