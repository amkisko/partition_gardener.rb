require "digest"
require "json"

module PartitionGardener
  class PlanDiff
    Operation = Data.define(:action, :segment, :attached_segment)

    def self.operations(attached_segments, target_segments)
      new(attached_segments, target_segments).operations
    end

    def self.plan_signature(segments)
      payload = segments.map(&:signature).sort_by(&:to_s).to_json
      Digest::SHA256.hexdigest(payload)[0, 16]
    end

    def self.changed?(attached_segments, target_segments)
      attached_segments.map(&:signature).sort != target_segments.map(&:signature).sort
    end

    def initialize(attached_segments, target_segments)
      @attached_segments = attached_segments
      @target_segments = target_segments
    end

    def operations
      attached_by_name = @attached_segments.each_with_object({}) { |segment, index| index[segment.name] = segment }
      target_by_name = @target_segments.each_with_object({}) { |segment, index| index[segment.name] = segment }
      result = []

      target_by_name.each_value do |segment|
        attached = attached_by_name[segment.name]
        result << if attached.nil?
          Operation.new(:create, segment, nil)
        elsif attached.signature == segment.signature
          Operation.new(:keep, segment, attached)
        else
          Operation.new(:reshape, segment, attached)
        end
      end

      attached_by_name.each_value do |attached|
        next if target_by_name[attached.name]

        result << Operation.new(:drop, nil, attached)
      end

      result
    end
  end
end
