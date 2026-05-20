# frozen_string_literal: true

RSpec.describe DataCruncher::Transformer do
  let(:sales) { DataCruncher::Reader.read(fixture("sales.csv")) }
  subject(:transformer) { described_class.new(sales) }

  describe "#filter / #where" do
    it "keeps rows matching a block" do
      result = transformer.filter { |r| r["region"] == "West" }.dataset
      expect(result.size).to eq(3)
    end

    it "keeps rows matching equality conditions" do
      result = transformer.where("region" => "East").dataset
      expect(result.column("product")).to all(be_a(String))
      expect(result.size).to eq(2)
    end

    it "supports callable conditions" do
      result = transformer.where("amount" => ->(v) { v.to_f > 1000 }).dataset
      expect(result.size).to eq(2)
    end
  end

  describe "#sort_by" do
    it "sorts numerically ascending and descending" do
      asc = transformer.sort_by("amount").dataset.column("amount").map(&:to_f)
      expect(asc).to eq(asc.sort)
      desc = transformer.sort_by("amount", direction: :desc).dataset.column("amount").map(&:to_f)
      expect(desc.first).to eq(1500.75)
    end
  end

  describe "#select and #limit" do
    it "projects columns and truncates rows" do
      result = transformer.select("region", "amount").limit(2).dataset
      expect(result.headers).to eq(%w[region amount])
      expect(result.size).to eq(2)
    end
  end

  describe "#group_by" do
    it "buckets rows by a column value" do
      groups = transformer.group_by("region")
      expect(groups.keys).to contain_exactly("West", "East", "North")
      expect(groups["West"]).to be_a(DataCruncher::Dataset)
      expect(groups["West"].size).to eq(3)
    end
  end

  describe "#aggregate" do
    it "computes grouped aggregates" do
      result = transformer.aggregate(group_by: "region", sum: "amount", avg: "amount", count: true)
      west = result.find { |r| r["region"] == "West" }
      expect(west["count"]).to eq(3)
      expect(west["sum_amount"]).to be_within(0.01).of(2250.75)
      expect(west["avg_amount"]).to be_within(0.01).of(750.25)
    end

    it "computes whole-dataset aggregates" do
      result = transformer.aggregate(sum: "quantity", min: "amount", max: "amount")
      expect(result.size).to eq(1)
      expect(result.first["sum_quantity"]).to eq(36)
      expect(result.first["max_amount"]).to eq(1500.75)
    end
  end

  describe "#pivot" do
    it "builds a region x product matrix" do
      pivot = transformer.pivot(rows: "region", columns: "product", values: "amount", aggregate: :sum)
      expect(pivot.headers).to include("region", "Widget", "Gadget")
      west = pivot.find { |r| r["region"] == "West" }
      expect(west["Widget"]).to be_within(0.01).of(1800.50)
      expect(west["Gadget"]).to be_within(0.01).of(450.25)
    end
  end

  describe "#merge" do
    let(:left) do
      DataCruncher::Dataset.from_rows([{ "id" => 1, "name" => "A" }, { "id" => 2, "name" => "B" }])
    end
    let(:right) do
      DataCruncher::Dataset.from_rows([{ "id" => 1, "city" => "NYC" }, { "id" => 3, "city" => "LA" }])
    end

    it "performs an inner join" do
      result = described_class.new(left).merge(right, on: "id", how: :inner)
      expect(result.size).to eq(1)
      expect(result.first).to include("name" => "A", "city" => "NYC")
    end

    it "performs a left join keeping unmatched left rows" do
      result = described_class.new(left).merge(right, on: "id", how: :left)
      expect(result.size).to eq(2)
      expect(result.find { |r| r["id"] == 2 }["city"]).to be_nil
    end

    it "performs an outer join keeping unmatched rows from both sides" do
      result = described_class.new(left).merge(right, on: "id", how: :outer)
      expect(result.map { |r| r["id"] }).to contain_exactly(1, 2, 3)
    end
  end
end
