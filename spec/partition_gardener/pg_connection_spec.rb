require "spec_helper"

RSpec.describe PartitionGardener::PgConnection do
  let(:raw_connection) { instance_double(PG::Connection) }
  let(:connection) { described_class.new(raw_connection) }

  before do
    allow(raw_connection).to receive(:escape_string) { |value| value.gsub("'", "''") }
    allow(raw_connection).to receive(:quote_ident).with("events").and_return('"events"')
    allow(raw_connection).to receive(:exec_params).and_return(instance_double(PG::Result, getvalue: "t", ntuples: 1))
    allow(raw_connection).to receive(:exec).and_return(instance_double(PG::Result, :ntuples => 0, :cmd_tuples => 0, :[] => nil, :each => [].each))
  end

  it "quotes string values for SQL" do
    expect(connection.quote("events")).to eq("'events'")
  end

  it "quotes table names" do
    expect(connection.quote_table_name("events")).to eq('"events"')
  end

  it "checks table existence through PostgreSQL catalogs" do
    expect(connection.table_exists?("events")).to be(true)
    expect(raw_connection).to have_received(:exec_params)
  end

  it "commits successful transactions" do
    allow(raw_connection).to receive(:exec)

    connection.transaction { :done }

    expect(raw_connection).to have_received(:exec).with("BEGIN").ordered
    expect(raw_connection).to have_received(:exec).with("COMMIT").ordered
  end

  it "rolls back failed transactions" do
    allow(raw_connection).to receive(:exec)

    expect {
      connection.transaction { raise StandardError, "boom" }
    }.to raise_error(StandardError, "boom")

    expect(raw_connection).to have_received(:exec).with("BEGIN").ordered
    expect(raw_connection).to have_received(:exec).with("ROLLBACK").ordered
    expect(raw_connection).not_to have_received(:exec).with("COMMIT")
  end

  it "enumerates query rows like an ActiveRecord result" do
    rows = [{"count" => "2"}, {"count" => "0"}]
    pg_result = instance_double(PG::Result, ntuples: 2, cmd_tuples: 2)
    allow(pg_result).to receive(:[]).with(0).and_return(rows[0])
    allow(pg_result).to receive(:to_a).and_return(rows)
    allow(pg_result).to receive(:each).and_yield(rows[0]).and_yield(rows[1])
    allow(raw_connection).to receive(:exec).and_return(pg_result)

    result = connection.execute("SELECT COUNT(*) AS count FROM events")

    expect(result.map { |row| row["count"].to_i }).to eq([2, 0])
    expect(result.to_a).to eq(rows)
    expect(result.any?).to be(true)
  end
end
