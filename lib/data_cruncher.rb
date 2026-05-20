# frozen_string_literal: true

require_relative "data_cruncher/version"
require_relative "data_cruncher/errors"
require_relative "data_cruncher/dataset"
require_relative "data_cruncher/reader"
require_relative "data_cruncher/cleaner"
require_relative "data_cruncher/validator"
require_relative "data_cruncher/transformer"
require_relative "data_cruncher/reporter"
require_relative "data_cruncher/api"
require_relative "data_cruncher/cli"

# DataCruncher is a pure-Ruby toolkit for reading, cleaning, validating,
# transforming and reporting on tabular data.
#
# The top-level module exposes a few convenience shortcuts; the real work lives
# in the focused sub-modules ({Reader}, {Cleaner}, {Validator}, {Transformer},
# {Reporter} and {API}), all of which speak the same {Dataset} structure.
#
# @example Read, clean and print a CSV file
#   data = DataCruncher.read("sales.csv")
#   clean = DataCruncher::Cleaner.new(data).trim_whitespace.remove_duplicates.result
#   puts DataCruncher::Reporter.to_table(clean, title: "Sales")
module DataCruncher
  module_function

  # Read a file into a {Dataset}. Delegates to {Reader.read}.
  def read(path, **opts)
    Reader.read(path, **opts)
  end

  # Wrap a {Dataset} in a {Cleaner}.
  def clean(dataset)
    Cleaner.new(dataset)
  end

  # Wrap a {Dataset} in a {Transformer}.
  def transform(dataset)
    Transformer.new(dataset)
  end
end
