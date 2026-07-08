require "json"

module PartitionGardener
  class PlanReport
    SCHEMA_VERSION = "1.0"

    def self.build(config)
      planner = Planner.new(config)
      plan = planner.build
      attached_segments = planner.attached_tail_segments
      operations = PlanDiff.operations(attached_segments, plan.segments)
      gaps = GapDetection.call(config[:table_name], config: config)

      new(
        table_name: config[:table_name],
        layout: config.fetch(:layout, :sliding_window),
        changed: PlanDiff.changed?(attached_segments, plan.segments),
        plan_signature: PlanDiff.plan_signature(plan.segments),
        target_segments: plan.segments,
        attached_segments: attached_segments,
        operations: operations,
        gaps: gaps,
        hot_buckets: plan.hot_buckets
      )
    end

    attr_reader :table_name,
      :layout,
      :changed,
      :plan_signature,
      :target_segments,
      :attached_segments,
      :operations,
      :gaps,
      :hot_buckets

    def initialize(table_name:, layout:, changed:, plan_signature:, target_segments:, attached_segments:, operations:, gaps:, hot_buckets:)
      @table_name = table_name
      @layout = layout
      @changed = changed
      @plan_signature = plan_signature
      @target_segments = target_segments
      @attached_segments = attached_segments
      @operations = operations
      @gaps = gaps
      @hot_buckets = hot_buckets
    end

    def to_h
      {
        schema_version: self.class::SCHEMA_VERSION,
        table_name: table_name,
        layout: layout,
        changed: changed,
        plan_signature: plan_signature,
        target_segments: target_segments.map { |segment| segment_to_h(segment) },
        attached_segments: attached_segments.map { |segment| segment_to_h(segment) },
        operations: operations.map { |operation| operation_to_h(operation) },
        gaps: gaps.map { |gap| gap_to_h(gap) },
        hot_buckets: hot_buckets
      }
    end

    def to_json(...)
      to_h.to_json(...)
    end

    private

    def segment_to_h(segment)
      {
        name: segment.name,
        range_start: segment.range_start,
        range_end: segment.range_end,
        kind: segment.kind
      }
    end

    def operation_to_h(operation)
      {
        action: operation.action,
        segment: operation.segment ? segment_to_h(operation.segment) : nil,
        attached_segment: operation.attached_segment ? segment_to_h(operation.attached_segment) : nil
      }
    end

    def gap_to_h(gap)
      {
        range_start: gap.range_start,
        range_end: gap.range_end,
        message: gap.message
      }
    end
  end
end
