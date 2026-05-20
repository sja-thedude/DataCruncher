# frozen_string_literal: true

require "rubyXL"

RSpec.describe DataCruncher::Reader do
  describe ".read CSV" do
    let(:data) { described_class.read(fixture("sales.csv")) }

    it "loads headers and rows" do
      expect(data.headers).to eq(%w[date region product amount quantity])
      expect(data.size).to eq(6)
      expect(data.first["region"]).to eq("West")
    end
  end

  describe ".read TSV" do
    it "splits on tabs" do
      data = described_class.read(fixture("scores.tsv"))
      expect(data.headers).to eq(%w[name score team])
      expect(data.column("name")).to eq(%w[Anna Ben Cara])
    end
  end

  describe ".read JSON" do
    it "extracts the nested array of records" do
      data = described_class.read(fixture("employees.json"))
      expect(data.size).to eq(4)
      expect(data.headers).to include("name", "department", "salary")
    end

    it "honours an explicit root key" do
      data = described_class.read(fixture("employees.json"), root: "employees")
      expect(data.size).to eq(4)
    end
  end

  describe ".read Excel" do
    around do |example|
      Dir.mktmpdir do |dir|
        @dir = dir
        example.run
      end
    end

    it "reads the first worksheet" do
      path = File.join(@dir, "people.xlsx")
      workbook = RubyXL::Workbook.new
      sheet = workbook[0]
      %w[name age].each_with_index { |h, i| sheet.add_cell(0, i, h) }
      sheet.add_cell(1, 0, "Ada")
      sheet.add_cell(1, 1, 30)
      sheet.add_cell(2, 0, "Linus")
      sheet.add_cell(2, 1, 54)
      workbook.write(path)

      data = described_class.read(path)
      expect(data.headers).to eq(%w[name age])
      expect(data.size).to eq(2)
      expect(data.first).to eq("name" => "Ada", "age" => 30)
    end
  end

  describe "format handling" do
    it "auto-detects from the extension" do
      expect(described_class.detect_format("a/b/c.json")).to eq(:json)
      expect(described_class.detect_format("data.TSV")).to eq(:tsv)
    end

    it "raises for a missing file" do
      expect { described_class.read("nope.csv") }.to raise_error(DataCruncher::FileNotFoundError)
    end

    it "raises for an unknown extension" do
      expect { described_class.detect_format("data.xyz") }.to raise_error(DataCruncher::UnsupportedFormatError)
    end
  end
end
