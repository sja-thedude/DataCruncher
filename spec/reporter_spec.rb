# frozen_string_literal: true

RSpec.describe DataCruncher::Reporter do
  let(:dataset) do
    DataCruncher::Dataset.new(
      headers: %w[name amount],
      rows: [{ "name" => "Widget", "amount" => 1200.5 }, { "name" => "Gadget", "amount" => 800 }]
    )
  end

  describe ".to_csv" do
    it "renders headers and rows as CSV text" do
      csv = described_class.to_csv(dataset)
      expect(csv).to start_with("name,amount\n")
      expect(csv).to include("Widget,1200.5")
    end

    it "writes to a file when given a path" do
      Dir.mktmpdir do |dir|
        path = File.join(dir, "out.csv")
        expect(described_class.to_csv(dataset, path: path)).to eq(path)
        expect(File.read(path)).to include("Gadget,800")
      end
    end
  end

  describe ".to_json" do
    it "round-trips through JSON" do
      parsed = JSON.parse(described_class.to_json(dataset))
      expect(parsed.first).to eq("name" => "Widget", "amount" => 1200.5)
    end
  end

  describe ".to_table" do
    it "produces a bordered terminal table containing the data" do
      table = described_class.to_table(dataset, title: "Products")
      expect(table).to include("Products", "name", "amount", "Widget")
      expect(table).to include("+", "|")
    end

    it "notes truncation when a limit is applied" do
      table = described_class.to_table(dataset, limit: 1)
      expect(table).to include("showing 1 of 2 rows")
    end
  end

  describe ".render" do
    it "dispatches on the format symbol" do
      expect(described_class.render(dataset, format: :csv)).to include("name,amount")
    end

    it "raises for an unsupported format" do
      expect { described_class.render(dataset, format: :pdf) }
        .to raise_error(DataCruncher::UnsupportedFormatError)
    end
  end
end
