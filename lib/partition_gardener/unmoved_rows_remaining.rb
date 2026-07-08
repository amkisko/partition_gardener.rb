module PartitionGardener
  class UnmovedRowsRemaining < StandardError
    attr_reader :source_partition_name, :batch_size, :last_cursor

    def initialize(source_partition_name:, batch_size:, last_cursor:)
      @source_partition_name = source_partition_name
      @batch_size = batch_size
      @last_cursor = last_cursor
      super(
        "Stopped moving rows from #{source_partition_name}: " \
        "batch selected #{batch_size} row(s) but none could be removed"
      )
    end
  end
end
