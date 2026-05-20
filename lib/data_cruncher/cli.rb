# frozen_string_literal: true

require "optparse"

module DataCruncher
  # Command-line entry point for the +datacruncher+ executable.
  #
  #   datacruncher process input.csv --clean --validate --report table
  #   datacruncher process sales.csv --group-by region --sum amount --report csv -o out.csv
  #
  # Run +datacruncher help+ for the full option list.
  class CLI
    # Build a CLI and run it, returning a process exit status (Integer).
    def self.start(argv)
      new(argv).run
    end

    def initialize(argv)
      @argv = argv.dup
    end

    def run
      command = @argv.shift
      case command
      when "process" then process
      when "version", "--version", "-v" then puts("data-cruncher #{VERSION}") || 0
      when "help", "--help", "-h", nil then puts(banner) || 0
      else
        warn "Unknown command: #{command}\n\n#{banner}"
        1
      end
    rescue OptionParser::ParseError => e
      warn "Error: #{e.message}\n\nRun `datacruncher process --help` for usage."
      1
    rescue DataCruncher::Error => e
      warn "Error: #{e.message}"
      1
    end

    private

    def process
      options = parse_options
      input = options[:input]
      return error("No input file given.\n\n#{banner}") unless input

      dataset = Reader.read(input, format: options[:format])
      log options, "Read #{dataset.size} row(s) × #{dataset.headers.size} column(s) from #{input}"

      dataset = run_cleaning(dataset, options)
      dataset = run_transforms(dataset, options)

      status = run_validation(dataset, options)
      return status if status && status != 0

      emit_report(dataset, options)
      0
    end

    # ---- pipeline stages ---------------------------------------------------

    def run_cleaning(dataset, options)
      return dataset unless options[:clean] || options[:clean_ops].any?

      cleaner = Cleaner.new(dataset)
      ops = options[:clean] ? %i[trim dedupe drop_missing] : options[:clean_ops]
      cleaner.trim_whitespace if ops.include?(:trim)
      cleaner.remove_duplicates if ops.include?(:dedupe)
      cleaner.handle_missing(strategy: :drop) if ops.include?(:drop_missing)
      cleaner.handle_missing(strategy: :fill, value: options[:fill]) if ops.include?(:fill)
      result = cleaner.result
      log options, "Cleaned: #{result.size} row(s) remain"
      result
    end

    def run_transforms(dataset, options)
      t = Transformer.new(dataset)
      options[:where].each { |cond| t = t.where(cond) }
      t = t.sort_by(options[:sort][:column], direction: options[:sort][:direction]) if options[:sort]
      t = t.select(*options[:select]) if options[:select]
      t = t.limit(options[:limit]) if options[:limit]
      dataset = t.dataset

      if options[:group_by]
        dataset = Transformer.new(dataset).aggregate(
          group_by: options[:group_by],
          count: options[:aggregations].include?(:count),
          sum: options[:agg_columns][:sum],
          avg: options[:agg_columns][:avg],
          min: options[:agg_columns][:min],
          max: options[:agg_columns][:max]
        )
        log options, "Aggregated into #{dataset.size} group(s)"
      end
      dataset
    end

    def run_validation(dataset, options)
      return nil unless options[:validate]

      validator = build_validator(options)
      report = validator.validate(dataset)
      puts report
      options[:strict] && report.invalid? ? 2 : nil
    end

    def emit_report(dataset, options)
      format = options[:report]
      output = Reporter.render(dataset, format: format, path: options[:output], title: options[:title])
      if options[:output]
        log options, "Wrote #{format} report to #{output}"
      else
        puts output
      end
    end

    # ---- validator construction -------------------------------------------

    # When a --rules file is supplied it is evaluated inside the Validator DSL;
    # otherwise we run a basic completeness check (every column non-blank).
    def build_validator(options)
      if options[:rules]
        source = File.read(options[:rules])
        Validator.new { instance_eval(source, options[:rules]) }
      else
        headers = options[:_headers]
        Validator.new { required(*headers) }
      end
    end

    # ---- option parsing ----------------------------------------------------

    def parse_options
      options = default_options
      parser = build_parser(options)
      positional = parser.parse(@argv)
      options[:input] = positional.first
      # headers are needed for the default validator; read lazily and cached
      options[:_headers] =
        options[:input] && File.exist?(options[:input]) ? Reader.read(options[:input], format: options[:format]).headers : []
      options
    end

    def default_options
      {
        clean: false, clean_ops: [], fill: "",
        where: [], select: nil, sort: nil, limit: nil,
        group_by: nil, aggregations: [], agg_columns: {},
        validate: false, rules: nil, strict: false,
        report: :table, output: nil, title: nil, quiet: false
      }
    end

    def build_parser(options) # rubocop:disable Metrics/AbcSize, Metrics/MethodLength
      OptionParser.new do |o|
        o.banner = "Usage: datacruncher process FILE [options]"

        o.on("-f", "--format FORMAT", "Override input format (csv, tsv, json, excel)") { |v| options[:format] = v.to_sym }

        o.separator "\nCleaning:"
        o.on("--clean", "Run standard cleaning (trim, de-duplicate, drop missing)") { options[:clean] = true }
        o.on("--trim", "Trim surrounding whitespace") { options[:clean_ops] << :trim }
        o.on("--dedupe", "Remove duplicate rows") { options[:clean_ops] << :dedupe }
        o.on("--drop-missing", "Drop rows with missing values") { options[:clean_ops] << :drop_missing }
        o.on("--fill VALUE", "Fill missing values with VALUE") do |v|
          options[:clean_ops] << :fill
          options[:fill] = v
        end

        o.separator "\nTransform:"
        o.on("--where COND", "Keep rows matching col=value (repeatable)") { |v| options[:where] << parse_condition(v) }
        o.on("--select COLS", "Keep only these comma-separated columns") { |v| options[:select] = v.split(",").map(&:strip) }
        o.on("--sort COL[:desc]", "Sort by column (append :desc to reverse)") { |v| options[:sort] = parse_sort(v) }
        o.on("--limit N", Integer, "Keep only the first N rows") { |v| options[:limit] = v }
        o.on("--group-by COL", "Group rows by column for aggregation") { |v| options[:group_by] = v }
        o.on("--count", "Add a count column (with --group-by)") { options[:aggregations] << :count }
        o.on("--sum COLS", "Sum these columns (with --group-by)") { |v| options[:agg_columns][:sum] = v.split(",").map(&:strip) }
        o.on("--avg COLS", "Average these columns (with --group-by)") { |v| options[:agg_columns][:avg] = v.split(",").map(&:strip) }
        o.on("--min COLS", "Minimum of these columns (with --group-by)") { |v| options[:agg_columns][:min] = v.split(",").map(&:strip) }
        o.on("--max COLS", "Maximum of these columns (with --group-by)") { |v| options[:agg_columns][:max] = v.split(",").map(&:strip) }

        o.separator "\nValidate:"
        o.on("--validate", "Validate the data") { options[:validate] = true }
        o.on("--rules FILE", "Ruby file describing validation rules") { |v| options[:rules] = v }
        o.on("--strict", "Exit non-zero when validation fails") { options[:strict] = true }

        o.separator "\nReport:"
        o.on("--report FORMAT", %i[csv json table], "Output format: csv, json or table (default: table)") { |v| options[:report] = v }
        o.on("-o", "--output FILE", "Write the report to FILE instead of stdout") { |v| options[:output] = v }
        o.on("--title TITLE", "Title for the terminal table") { |v| options[:title] = v }

        o.separator "\nMisc:"
        o.on("-q", "--quiet", "Suppress progress logging") { options[:quiet] = true }
        o.on("-h", "--help", "Show this help") do
          puts o
          exit 0
        end
      end
    end

    def parse_condition(str)
      key, value = str.split("=", 2)
      { key.strip => value.to_s.strip }
    end

    def parse_sort(str)
      column, dir = str.split(":", 2)
      { column: column.strip, direction: (dir || "asc").to_sym }
    end

    # ---- helpers -----------------------------------------------------------

    def log(options, message)
      warn(message) unless options[:quiet]
    end

    def error(message)
      warn "Error: #{message}"
      1
    end

    def banner
      <<~TXT
        datacruncher — read, clean, validate, transform and report on tabular data.

        Usage:
          datacruncher process FILE [options]
          datacruncher version
          datacruncher help

        Examples:
          datacruncher process sales.csv --clean --validate --report table
          datacruncher process sales.csv --group-by region --sum amount --report csv -o summary.csv
          datacruncher process customers.csv --clean --select name,email --report json

        Run `datacruncher process --help` for the full list of options.
      TXT
    end
  end
end
