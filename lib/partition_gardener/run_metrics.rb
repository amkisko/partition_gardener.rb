module PartitionGardener
  class RunMetrics
    attr_reader :table_name, :started_at, :rows_moved, :finished_at, :skipped, :skip_reason
    attr_accessor :plan_signature

    def initialize(table_name)
      @table_name = table_name
      @started_at = monotonic_clock
      @plan_signature = nil
      @rows_moved = 0
      @finished_at = nil
      @skipped = false
      @skip_reason = nil
    end

    def add_rows(count)
      @rows_moved += count.to_i
    end

    def mark_skipped!(reason)
      @skipped = true
      @skip_reason = reason
      finish!
    end

    def finish!
      @finished_at = monotonic_clock
    end

    def duration_ms
      return nil unless @finished_at

      ((@finished_at - @started_at) * 1000).round
    end

    def to_h
      {
        table_name: table_name,
        duration_ms: duration_ms,
        plan_signature: plan_signature,
        rows_moved: rows_moved,
        skipped: skipped,
        skip_reason: skip_reason
      }
    end

    private

    def monotonic_clock
      Process.clock_gettime(Process::CLOCK_MONOTONIC)
    end
  end

  RunSummary = Data.define(:tables, :errors) do
    SCHEMA_VERSION = "1.0"

    def to_h
      {
        schema_version: SCHEMA_VERSION,
        tables: tables.map(&:to_h),
        errors: errors.map { |error| error.message }
      }
    end
  end
end
