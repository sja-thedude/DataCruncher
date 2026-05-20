# frozen_string_literal: true

RSpec.describe DataCruncher::Dataset do
  subject(:dataset) do
    described_class.new(
      headers: %w[name role],
      rows: [{ "name" => "Ada", "role" => "Engineer" },
             { "name" => "Linus", "role" => "Engineer" }]
    )
  end

  it "exposes headers and rows" do
    expect(dataset.headers).to eq(%w[name role])
    expect(dataset.size).to eq(2)
    expect(dataset).not_to be_empty
  end

  it "stringifies symbol keys on construction" do
    ds = described_class.new(rows: [{ name: "Ada", age: 30 }])
    expect(ds.headers).to eq(%w[name age])
    expect(ds.first).to eq("name" => "Ada", "age" => 30)
  end

  describe ".from_rows" do
    it "infers column order from the first appearance of each key" do
      ds = described_class.from_rows([{ "b" => 1 }, { "a" => 2, "b" => 3 }])
      expect(ds.headers).to eq(%w[b a])
    end
  end

  it "reads a single column" do
    expect(dataset.column("name")).to eq(%w[Ada Linus])
  end

  it "appends rows and extends headers" do
    dataset << { "name" => "Yukihiro", "role" => "Engineer", "lang" => "Ruby" }
    expect(dataset.size).to eq(3)
    expect(dataset.headers).to include("lang")
  end

  it "adds a computed column" do
    dataset.add_column("initial") { |row| row["name"][0] }
    expect(dataset.column("initial")).to eq(%w[A L])
  end

  it "selects a subset of columns" do
    projected = dataset.select_columns("name")
    expect(projected.headers).to eq(%w[name])
    expect(projected.first).to eq("name" => "Ada")
  end

  it "is enumerable" do
    expect(dataset.map { |r| r["name"] }).to eq(%w[Ada Linus])
  end

  it "deep-dups without affecting the original" do
    copy = dataset.deep_dup
    copy.first["name"] = "Changed"
    expect(dataset.first["name"]).to eq("Ada")
  end

  it "compares by headers and rows" do
    expect(dataset).to eq(dataset.deep_dup)
  end
end
