module PartitionGardener
  class MemoryRunRecordStore
    def initialize
      @records = {}
    end

    def load(table_name)
      @records[table_name]
    end

    def save(table_name, attributes)
      @records[table_name] = attributes
    end

    def clear(table_name)
      @records.delete(table_name)
    end
  end
end
