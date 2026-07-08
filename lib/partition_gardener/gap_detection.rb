module PartitionGardener
  class GapDetection
    Gap = Data.define(:range_start, :range_end, :message)

    def self.call(table_name, config: Registry.find_by_table_name(table_name))
      new(table_name, config: config).call
    end

    def initialize(table_name, config: nil)
      @table_name = table_name
      @config = config || Registry.find_by_table_name(table_name)
    end

    def call
      return [] unless @config

      strategy = Strategy.for(@config)
      return [] unless range_layout?(strategy)

      segments = strategy.attached_tail_segments
      return [] if segments.empty?

      sorted = segments.sort_by { |segment| [segment.range_start.to_s, segment.name] }
      gaps = []

      sorted.each_cons(2) do |left, right|
        left_end = normalize_range_end(left.range_end)
        right_start = right.range_start
        next if left_end == right_start

        gaps << Gap.new(
          range_start: left_end,
          range_end: right_start,
          message: "uncovered range between #{left.name} and #{right.name} (#{left_end}..#{right_start})"
        )
      end

      unless sorted.any? { |segment| segment.range_end == :max }
        gaps << Gap.new(
          range_start: sorted.last.range_end,
          range_end: :max,
          message: "no attached tail partition extends to MAXVALUE"
        )
      end

      gaps
    end

    private

    def range_layout?(strategy)
      strategy.is_a?(Strategy::DateRange) || strategy.is_a?(Strategy::IntegerRange)
    end

    def normalize_range_end(range_end)
      (range_end == :max) ? nil : range_end
    end
  end
end
