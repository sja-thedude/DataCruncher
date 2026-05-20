# frozen_string_literal: true

RSpec.describe DataCruncher::Cleaner do
  let(:customers) { DataCruncher::Reader.read(fixture("customers.csv")) }

  it "does not mutate the source dataset" do
    original_name = customers.first["name"]
    described_class.new(customers).trim_whitespace
    expect(customers.first["name"]).to eq(original_name)
  end

  describe "#trim_whitespace" do
    it "strips surrounding whitespace from strings" do
      cleaned = described_class.new(customers).trim_whitespace.result
      expect(cleaned.first["name"]).to eq("Alice Johnson")
      expect(cleaned.column("name")).to include("Dan Brown")
    end
  end

  describe "#remove_duplicates" do
    it "drops rows that repeat on the given columns" do
      cleaned = described_class.new(customers)
                               .remove_duplicates(columns: %w[name email])
                               .result
      expect(cleaned.size).to eq(4)
      expect(cleaned.column("name").count("Bob Smith")).to eq(1)
    end
  end

  describe "#handle_missing" do
    it "drops rows with blank values in the chosen column" do
      cleaned = described_class.new(customers)
                               .handle_missing(strategy: :drop, columns: "country")
                               .result
      expect(cleaned.size).to eq(3)
    end

    it "fills blanks from a per-column map" do
      cleaned = described_class.new(customers)
                               .handle_missing(strategy: :fill, value: { "country" => "Unknown" })
                               .result
      expect(cleaned.column("country")).to all(be_truthy)
      expect(cleaned.column("country")).to include("Unknown")
    end

    it "interpolates numeric gaps" do
      ds = DataCruncher::Dataset.new(
        headers: %w[t v],
        rows: [{ "t" => 1, "v" => 10 }, { "t" => 2, "v" => "" }, { "t" => 3, "v" => 30 }]
      )
      cleaned = described_class.new(ds).handle_missing(strategy: :interpolate, columns: "v").result
      expect(cleaned.column("v")).to eq([10.0, 20.0, 30.0])
    end
  end

  describe "#coerce_types" do
    it "converts string cells to typed values" do
      cleaned = described_class.new(customers).coerce_types("id" => :integer).result
      expect(cleaned.column("id")).to eq([1, 2, 3, 4, 5])
    end

    it "parses booleans" do
      ds = DataCruncher::Dataset.new(headers: %w[flag], rows: [{ "flag" => "yes" }, { "flag" => "0" }])
      cleaned = described_class.new(ds).coerce_types("flag" => :boolean).result
      expect(cleaned.column("flag")).to eq([true, false])
    end
  end

  describe "normalization" do
    let(:cleaned) do
      described_class.new(customers)
                     .trim_whitespace
                     .normalize_emails(columns: "email")
                     .normalize_phones(columns: "phone")
                     .normalize_dates(columns: "signup_date")
                     .result
    end

    it "lower-cases emails" do
      expect(cleaned.first["email"]).to eq("alice@example.com")
    end

    it "formats US phone numbers consistently" do
      expect(cleaned.column("phone")).to include("+1 (415) 555-1234", "+1 (415) 555-9876")
    end

    it "reformats parseable dates to ISO 8601" do
      expect(cleaned.first["signup_date"]).to eq("2025-01-15")
      expect(cleaned.column("signup_date")).to include("2025-01-20")
    end

    it "leaves blank dates untouched" do
      expect(cleaned.column("signup_date")).to include(nil)
    end
  end
end
