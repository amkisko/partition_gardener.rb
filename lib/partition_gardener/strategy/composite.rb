module PartitionGardener
  class CompositeMaintenance
    def initialize(config, job_class_name: "PartitionGardener", executor: nil)
      @config = config
      @job_class_name = job_class_name
      @executor = executor || Executor.for_config(config)
    end

    def run!
      Templates.expand(@config).each do |branch_config|
        ThreeAreaMaintenance.new(branch_config, job_class_name: @job_class_name, executor: @executor).run!
      end
    end

    def split_future_month_from_current!(_identifier = nil)
      run!
    end

    def split_pressured_future_month_partitions
      run!
    end

    def collapse_low_volume_future_month_partitions
      run!
    end
  end
end
