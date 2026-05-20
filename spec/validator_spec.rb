# frozen_string_literal: true

RSpec.describe DataCruncher::Validator do
  let(:employees) { DataCruncher::Reader.read(fixture("employees.json")) }

  let(:validator) do
    described_class.new do
      required  :name, :email
      type      :age, :integer
      range     :age, min: 18, max: 99
      format    :email, :email
      inclusion :status, in: %w[active inactive]
    end
  end

  subject(:report) { validator.validate(employees) }

  it "flags an invalid dataset" do
    expect(report).to be_invalid
    expect(report).not_to be_valid
  end

  it "reports the under-age employee against the age column" do
    age_errors = report.errors_for_column("age")
    expect(age_errors.map(&:row)).to include(1)
    expect(age_errors.first.message).to match(/>= 18/)
  end

  it "flags the malformed email" do
    email_errors = report.errors_for_column("email")
    expect(email_errors.map(&:row)).to include(2)
  end

  it "flags the missing name" do
    expect(report.errors_for_row(3).map(&:rule)).to include(:required)
  end

  it "flags a status outside the allowed set" do
    status_errors = report.errors_for_column("status")
    expect(status_errors.first.message).to include("active", "inactive")
  end

  it "passes a clean dataset" do
    clean = DataCruncher::Dataset.from_rows(
      [{ "name" => "Eve", "email" => "eve@corp.com", "age" => 30, "status" => "active" }]
    )
    expect(validator.validate(clean)).to be_valid
  end

  describe "regex format and length rules" do
    it "validates against a custom pattern and length bounds" do
      v = described_class.new do
        format :code, /\A[A-Z]{3}\z/
        length :code, min: 3, max: 3
      end
      ds = DataCruncher::Dataset.from_rows([{ "code" => "AB" }, { "code" => "ABC" }])
      result = v.validate(ds)
      expect(result.errors_for_row(0).map(&:rule)).to include(:format, :length)
      expect(result.errors_for_row(1)).to be_empty
    end
  end

  describe "cross-field rules" do
    it "evaluates a rule against the whole row" do
      v = described_class.new do
        cross :salary_band do |row|
          "salary below band minimum" if row["salary"].to_f < row["band_min"].to_f
        end
      end
      ds = DataCruncher::Dataset.from_rows(
        [{ "salary" => 50_000, "band_min" => 60_000 }, { "salary" => 70_000, "band_min" => 60_000 }]
      )
      result = v.validate(ds)
      expect(result.error_count).to eq(1)
      expect(result.errors.first.row).to eq(0)
      expect(result.errors.first.column).to be_nil
    end
  end

  describe "report export" do
    it "serializes to a hash and JSON" do
      hash = report.to_h
      expect(hash).to include(:valid, :row_count, :error_count, :errors)
      expect(JSON.parse(report.to_json)).to include("error_count" => report.error_count)
    end

    it "produces a readable summary" do
      expect(report.to_s).to match(/validation error/)
    end
  end
end
