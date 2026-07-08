require "spec_helper"

RSpec.describe PartitionGardener::DateBucket do
  describe ".partition_name" do
    it "formats daily partitions" do
      name = described_class.partition_name("events", Date.new(2026, 7, 7), :day)
      expect(name).to eq("events_2026_07_07")
    end

    it "formats weekly partitions" do
      name = described_class.partition_name("events", Date.new(2026, 7, 7), :week)
      expect(name).to eq("events_2026_W28")
    end

    it "formats quarterly partitions" do
      name = described_class.partition_name("events", Date.new(2026, 7, 7), :quarter)
      expect(name).to eq("events_2026_Q3")
    end
  end

  describe ".archive_bucket_from_partition_name" do
    it "parses daily partition names" do
      bucket = described_class.archive_bucket_from_partition_name("events", "events_2026_07_07", :day)
      expect(bucket).to eq(Date.new(2026, 7, 7))
    end

    it "parses quarterly partition names" do
      bucket = described_class.archive_bucket_from_partition_name("events", "events_2026_Q3", :quarter)
      expect(bucket).to eq(Date.new(2026, 7, 1))
    end
  end

  describe ".partition_definition_clause" do
    it "builds a weekly range clause" do
      clause = described_class.partition_definition_clause(Date.new(2026, 7, 7), :week)
      week_start = PartitionGardener::DateCalendar.beginning_of_week(Date.new(2026, 7, 7))
      week_end = PartitionGardener::DateCalendar.add_weeks(week_start, 1)
      expect(clause).to eq("FROM ('#{week_start}') TO ('#{week_end}')")
    end
  end
end
