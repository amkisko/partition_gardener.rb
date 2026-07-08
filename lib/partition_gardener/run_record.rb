module PartitionGardener
  class RunRecord
    PHASES = %w[detach segments rows cleanup complete].freeze

    attr_reader :table_name, :phase, :plan_signature, :staging_row_count

    def self.load(table_name)
      attributes = PartitionGardener.configuration.run_record_store.load(table_name)
      return unless attributes

      from_h(attributes)
    end

    def self.from_h(attributes)
      new(
        table_name: fetch_attribute(attributes, :table_name),
        phase: fetch_attribute(attributes, :phase),
        plan_signature: fetch_attribute(attributes, :plan_signature),
        staging_row_count: fetch_attribute(attributes, :staging_row_count) || 0
      )
    end

    def self.fetch_attribute(attributes, key)
      attributes[key] || attributes[key.to_s]
    end

    def self.clear(table_name)
      PartitionGardener.configuration.run_record_store.clear(table_name)
    end

    def self.start(table_name:, plan_signature:)
      new(
        table_name: table_name,
        phase: "detach",
        plan_signature: plan_signature,
        staging_row_count: 0
      ).tap(&:save!)
    end

    def initialize(table_name:, phase:, plan_signature:, staging_row_count: 0)
      @table_name = table_name
      @phase = phase
      @plan_signature = plan_signature
      @staging_row_count = staging_row_count
    end

    def incomplete?
      Blank.present?(phase) && phase != "complete"
    end

    def save!
      PartitionGardener.configuration.run_record_store.save(
        table_name,
        {
          table_name: table_name,
          phase: phase,
          plan_signature: plan_signature,
          staging_row_count: staging_row_count
        }
      )
    end

    def advance!(phase, staging_row_count: nil)
      RunRecord.new(
        table_name: table_name,
        phase: phase,
        plan_signature: plan_signature,
        staging_row_count: staging_row_count.nil? ? self.staging_row_count : staging_row_count
      ).tap(&:save!)
    end

    def phase_at_least?(name)
      PHASES.index(phase) >= PHASES.index(name)
    end
  end
end
