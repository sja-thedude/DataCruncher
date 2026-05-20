# frozen_string_literal: true

RSpec.describe DataCruncher::CLI do
  def run(*args)
    status = nil
    output = capture_stdout { status = described_class.start(args) }
    [output, status]
  end

  it "prints the version" do
    output, status = run("version")
    expect(output).to include(DataCruncher::VERSION)
    expect(status).to eq(0)
  end

  it "prints help with no command" do
    output, = run
    expect(output).to include("Usage:", "datacruncher process")
  end

  it "returns non-zero for an unknown command" do
    _, status = run("frobnicate")
    expect(status).to eq(1)
  end

  it "processes a file and emits a JSON report" do
    output, status = run("process", fixture("sales.csv"), "--report", "json", "--quiet")
    expect(status).to eq(0)
    expect(JSON.parse(output).first).to include("region")
  end

  it "cleans and selects columns" do
    output, = run("process", fixture("customers.csv"),
                  "--clean", "--select", "name,email", "--report", "csv", "--quiet")
    expect(output).to start_with("name,email\n")
    expect(output).to include("Alice Johnson")
  end

  it "groups and aggregates" do
    output, = run("process", fixture("sales.csv"),
                  "--group-by", "region", "--sum", "amount", "--count",
                  "--report", "csv", "--quiet")
    rows = output.lines
    expect(rows.first).to include("region", "count", "sum_amount")
    expect(rows.size).to eq(4) # header + 3 regions
  end

  it "validates with a rules file and exits non-zero under --strict" do
    Dir.mktmpdir do |dir|
      rules = File.join(dir, "rules.rb")
      File.write(rules, <<~RUBY)
        required :name, :email
        range :age, min: 18, max: 99
        format :email, :email
      RUBY
      _, status = run("process", fixture("employees.json"),
                      "--validate", "--rules", rules, "--strict", "--report", "csv", "--quiet")
      expect(status).to eq(2)
    end
  end

  it "reports a clean OptionParser error for an invalid report format" do
    _, status = run("process", fixture("sales.csv"), "--report", "xml", "--quiet")
    expect(status).to eq(1)
  end

  it "writes a PDF report" do
    Dir.mktmpdir do |dir|
      path = File.join(dir, "report.pdf")
      _, status = run("process", fixture("sales.csv"),
                      "--group-by", "region", "--sum", "amount",
                      "--report", "pdf", "-o", path, "--quiet")
      expect(status).to eq(0)
      expect(File.binread(path, 4)).to eq("%PDF")
    end
  end
end
