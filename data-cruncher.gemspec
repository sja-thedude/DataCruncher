# frozen_string_literal: true

require_relative "lib/data_cruncher/version"

Gem::Specification.new do |spec|
  spec.name = "data-cruncher"
  spec.version = DataCruncher::VERSION
  spec.authors = ["Syeda Juveria Afreen"]
  spec.email = ["sja.affu765@gmail.com"]

  spec.summary = "A batteries-included Ruby toolkit for reading, cleaning, validating, transforming and reporting on tabular data."
  spec.description = <<~DESC
    DataCruncher is a pure-Ruby data-processing library. Read CSV, TSV, JSON and
    Excel into one unified dataset; clean and normalize it (de-duplicate, fill or
    interpolate missing values, normalize dates/emails/phones); validate it against
    declarative rules with detailed row/column error reports; transform it (filter,
    sort, group, aggregate, pivot, merge); pull in data from any REST API; and
    export polished reports as CSV, JSON or formatted terminal tables — from code
    or via the bundled `datacruncher` CLI.
  DESC
  spec.homepage = "https://github.com/sja-thedude/DataCruncher"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.0"

  spec.metadata["source_code_uri"] = spec.homepage
  spec.metadata["changelog_uri"] = "#{spec.homepage}/blob/main/CHANGELOG.md"
  spec.metadata["bug_tracker_uri"] = "#{spec.homepage}/issues"
  spec.metadata["rubygems_mfa_required"] = "true"

  spec.files = Dir[
    "lib/**/*.rb",
    "bin/*",
    "*.md",
    "LICENSE",
    "data-cruncher.gemspec"
  ]
  spec.bindir = "bin"
  spec.executables = ["datacruncher"]
  spec.require_paths = ["lib"]

  # `csv` ships as a bundled (no longer default) gem from Ruby 3.4 onward.
  spec.add_dependency "csv", "~> 3.3"
  spec.add_dependency "rubyXL", "~> 3.4"
  spec.add_dependency "terminal-table", "~> 3.0"

  spec.add_development_dependency "rake", "~> 13.0"
  spec.add_development_dependency "rspec", "~> 3.13"
  spec.add_development_dependency "rubocop", "~> 1.60"
  spec.add_development_dependency "webmock", "~> 3.23"
end
