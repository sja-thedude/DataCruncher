# frozen_string_literal: true

module DataCruncher
  # Base error for everything raised by the library, so callers can rescue
  # +DataCruncher::Error+ and catch any library-specific failure.
  class Error < StandardError; end

  # Raised when a file passed to {Reader} does not exist.
  class FileNotFoundError < Error; end

  # Raised when a file extension/format is not supported.
  class UnsupportedFormatError < Error; end

  # Raised when a file cannot be parsed (malformed CSV, invalid JSON, ...).
  class ParseError < Error; end

  # Raised for unrecoverable validation configuration problems.
  class ValidationError < Error; end

  # Raised when a remote API request or its response cannot be handled.
  class APIError < Error; end
end
