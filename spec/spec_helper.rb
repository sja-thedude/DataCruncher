# frozen_string_literal: true

require "data_cruncher"
require "webmock/rspec"
require "tmpdir"
require "stringio"

# Shared helpers available in every example.
module SpecHelpers
  FIXTURES_DIR = File.expand_path("fixtures", __dir__)

  # Absolute path to a file under spec/fixtures.
  def fixture(name)
    File.join(FIXTURES_DIR, name)
  end

  # Capture $stdout produced by the block.
  def capture_stdout
    original = $stdout
    $stdout = StringIO.new
    yield
    $stdout.string
  ensure
    $stdout = original
  end
end

RSpec.configure do |config|
  config.include SpecHelpers

  config.expect_with(:rspec) { |c| c.syntax = :expect }
  config.mock_with(:rspec) { |c| c.verify_partial_doubles = true }
  config.disable_monkey_patching!
  config.order = :random
  Kernel.srand config.seed
end
