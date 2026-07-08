module PartitionGardener
  module Integration
    module Fixtures
      module_function

      def unique_table_name(prefix = "pg_gardener")
        "#{prefix}_#{SecureRandom.hex(4)}"
      end

      def create_sliding_window_table!(
        table_name,
        today: Date.new(2026, 7, 5),
        active_months: 12
      )
        connection = Database.connection
        active_start = today.beginning_of_month
        active_end = active_start + active_months.months

        connection.execute(<<~SQL)
          CREATE TABLE #{quote_table(table_name)} (
            id bigint NOT NULL,
            occurred_on date NOT NULL,
            PRIMARY KEY (id, occurred_on)
          ) PARTITION BY RANGE (occurred_on)
        SQL

        connection.execute(<<~SQL)
          CREATE TABLE #{quote_table(default_name(table_name))} PARTITION OF #{quote_table(table_name)} DEFAULT
        SQL

        connection.execute(<<~SQL)
          CREATE TABLE #{quote_table(current_name(table_name))} PARTITION OF #{quote_table(table_name)}
          FOR VALUES FROM ('#{active_start}') TO ('#{active_end}')
        SQL

        connection.execute(<<~SQL)
          CREATE TABLE #{quote_table(future_name(table_name))} PARTITION OF #{quote_table(table_name)}
          FOR VALUES FROM ('#{active_end}') TO (MAXVALUE)
        SQL

        table_name
      end

      def register_sliding_window!(
        table_name,
        today: Date.new(2026, 7, 5),
        active_months: 12,
        split_row_threshold: 2
      )
        PartitionGardener::Registry.register(
          PartitionGardener::Templates.sliding_window_monthly(
            table_name: table_name,
            partition_key_column: "occurred_on",
            conflict_key: %w[id occurred_on],
            active_months: active_months,
            split_row_threshold: split_row_threshold
          )
        )
      end

      def create_composite_list_hash_tables!(parent_name, hash_modulus: 2)
        connection = Database.connection

        connection.execute(<<~SQL)
          CREATE TABLE #{quote_table(parent_name)} (
            id bigint NOT NULL,
            branch text NOT NULL,
            workspace_id bigint NOT NULL,
            PRIMARY KEY (id, branch, workspace_id)
          ) PARTITION BY LIST (branch)
        SQL

        connection.execute(<<~SQL)
          CREATE TABLE #{quote_table(default_name(parent_name))} PARTITION OF #{quote_table(parent_name)} DEFAULT
        SQL

        %w[cached workspace].each do |branch|
          branch_table = "#{parent_name}_#{branch}"
          connection.execute(<<~SQL)
            CREATE TABLE #{quote_table(branch_table)} PARTITION OF #{quote_table(parent_name)}
            FOR VALUES IN (#{connection.quote(branch)})
            PARTITION BY HASH (workspace_id)
          SQL

          hash_modulus.times do |remainder|
            partition_name = format("#{branch_table}_a_%02d", remainder)
            connection.execute(<<~SQL)
              CREATE TABLE #{quote_table(partition_name)} PARTITION OF #{quote_table(branch_table)}
              FOR VALUES WITH (MODULUS #{hash_modulus}, REMAINDER #{remainder})
            SQL
          end
        end

        parent_name
      end

      def register_composite_list_hash!(parent_name, hash_modulus: 2)
        PartitionGardener::Registry.register(
          PartitionGardener::Templates.composite_list_hash(
            parent_table: parent_name,
            discriminator_column: "branch",
            conflict_key: %w[id branch workspace_id],
            branches: [
              {
                name: "cached",
                value: "cached",
                where_condition: "branch = 'cached'",
                partition_key_column: "workspace_id",
                hash_modulus: hash_modulus
              },
              {
                name: "workspace",
                value: "workspace",
                where_condition: "branch = 'workspace'",
                partition_key_column: "workspace_id",
                hash_modulus: hash_modulus
              }
            ]
          )
        )
      end

      def insert_composite_row!(parent_name, id:, branch:, workspace_id:)
        connection = Database.connection
        connection.execute(<<~SQL)
          INSERT INTO #{quote_table(parent_name)} (id, branch, workspace_id)
          VALUES (#{connection.quote(id)}, #{connection.quote(branch)}, #{connection.quote(workspace_id)})
        SQL
      end

      def create_hot_switch_source_table!(table_name)
        connection = Database.connection
        connection.execute(<<~SQL)
          CREATE TABLE #{quote_table(table_name)} (
            id bigint NOT NULL,
            occurred_on date NOT NULL,
            updated_at timestamp NOT NULL DEFAULT NOW(),
            PRIMARY KEY (id, occurred_on)
          )
        SQL
      end

      def create_hot_switch_source_table_with_serial!(table_name)
        connection = Database.connection
        connection.execute(<<~SQL)
          CREATE TABLE #{quote_table(table_name)} (
            id bigserial NOT NULL,
            occurred_on date NOT NULL,
            updated_at timestamp NOT NULL DEFAULT NOW(),
            PRIMARY KEY (id, occurred_on)
          )
        SQL
      end

      def serial_sequence_owned_by_table?(table_name, column_name)
        connection = Database.connection
        row = connection.execute(<<~SQL).first
          SELECT c.relname AS sequence_name, t.relname AS owned_table, a.attname AS owned_column
          FROM pg_depend dependency
          JOIN pg_class sequence_relation ON sequence_relation.oid = dependency.objid
          JOIN pg_class table_relation ON table_relation.oid = dependency.refobjid
          JOIN pg_attribute attribute ON attribute.attrelid = table_relation.oid AND attribute.attnum = dependency.refobjsubid
          JOIN pg_class sequence_class ON sequence_class.oid = dependency.objid
          JOIN pg_class c ON c.oid = sequence_class.oid
          JOIN pg_class t ON t.oid = table_relation.oid
          JOIN pg_attribute a ON a.attrelid = t.oid AND a.attnum = dependency.refobjsubid
          WHERE dependency.deptype = 'a'
            AND sequence_relation.relkind = 'S'
            AND table_relation.relname = #{connection.quote(table_name)}
            AND attribute.attname = #{connection.quote(column_name)}
        SQL
        !row.nil?
      end

      def create_hot_switch_partitioned_table!(table_name, today: Date.new(2026, 7, 5))
        connection = Database.connection

        connection.execute(<<~SQL)
          CREATE TABLE #{quote_table(table_name)} (
            id bigint NOT NULL,
            occurred_on date NOT NULL,
            updated_at timestamp NOT NULL DEFAULT NOW(),
            PRIMARY KEY (id, occurred_on)
          ) PARTITION BY RANGE (occurred_on)
        SQL

        connection.execute(<<~SQL)
          CREATE TABLE #{quote_table(default_name(table_name))} PARTITION OF #{quote_table(table_name)} DEFAULT
        SQL

        table_name
      end

      def insert_row!(table_name, id:, occurred_on: nil, workspace_id: nil)
        connection = Database.connection
        if workspace_id
          connection.execute(<<~SQL)
            INSERT INTO #{quote_table(table_name)} (id, workspace_id)
            VALUES (#{connection.quote(id)}, #{connection.quote(workspace_id)})
          SQL
        elsif !occurred_on.nil?
          connection.execute(<<~SQL)
            INSERT INTO #{quote_table(table_name)} (id, occurred_on)
            VALUES (#{connection.quote(id)}, #{connection.quote(occurred_on)})
          SQL
        else
          connection.execute(<<~SQL)
            INSERT INTO #{quote_table(table_name)} (id)
            VALUES (#{connection.quote(id)})
          SQL
        end
      end

      def create_integer_window_table!(
        table_name,
        active_id_lo: 0,
        active_id_width: 10_000
      )
        connection = Database.connection
        active_end = active_id_lo + active_id_width

        connection.execute(<<~SQL)
          CREATE TABLE #{quote_table(table_name)} (
            id bigint NOT NULL,
            PRIMARY KEY (id)
          ) PARTITION BY RANGE (id)
        SQL

        connection.execute(<<~SQL)
          CREATE TABLE #{quote_table(default_name(table_name))} PARTITION OF #{quote_table(table_name)} DEFAULT
        SQL

        connection.execute(<<~SQL)
          CREATE TABLE #{quote_table(current_name(table_name))} PARTITION OF #{quote_table(table_name)}
          FOR VALUES FROM (#{active_id_lo}) TO (#{active_end})
        SQL

        connection.execute(<<~SQL)
          CREATE TABLE #{quote_table(future_name(table_name))} PARTITION OF #{quote_table(table_name)}
          FOR VALUES FROM (#{active_end}) TO (MAXVALUE)
        SQL

        table_name
      end

      def register_integer_window!(
        table_name,
        active_id_lo: 0,
        active_id_width: 10_000,
        current_band_size: 1_000,
        split_row_threshold: 2
      )
        PartitionGardener::Registry.register(
          PartitionGardener::Templates.integer_window(
            table_name: table_name,
            partition_key_column: "id",
            conflict_key: %w[id],
            active_id_lo: active_id_lo,
            active_id_width: active_id_width,
            current_band_size: current_band_size,
            split_row_threshold: split_row_threshold
          )
        )
      end

      def create_hash_branches_table!(table_name, hash_modulus: 4)
        connection = Database.connection

        connection.execute(<<~SQL)
          CREATE TABLE #{quote_table(table_name)} (
            id bigint NOT NULL,
            workspace_id bigint NOT NULL,
            PRIMARY KEY (id, workspace_id)
          ) PARTITION BY HASH (workspace_id)
        SQL

        hash_modulus.times do |remainder|
          partition_name = format("#{table_name}_a_%02d", remainder)
          connection.execute(<<~SQL)
            CREATE TABLE #{quote_table(partition_name)} PARTITION OF #{quote_table(table_name)}
            FOR VALUES WITH (MODULUS #{hash_modulus}, REMAINDER #{remainder})
          SQL
        end

        table_name
      end

      def register_hash_branches!(
        table_name,
        hash_modulus: 4,
        split_row_threshold: 2
      )
        PartitionGardener::Registry.register(
          PartitionGardener::Templates.hash_branches(
            table_name: table_name,
            partition_key_column: "workspace_id",
            conflict_key: %w[id workspace_id],
            hash_modulus: hash_modulus,
            split_row_threshold: split_row_threshold
          )
        )
      end

      def hash_archive_partition_name(table_name, remainder)
        format("#{table_name}_a_%02d", remainder)
      end

      def hash_hot_partition_name(table_name, remainder)
        format("#{table_name}_h_%02d", remainder)
      end

      def insert_hash_row!(partition_name, id:, workspace_id:)
        connection = Database.connection
        connection.execute(<<~SQL)
          INSERT INTO #{quote_table(partition_name)} (id, workspace_id)
          VALUES (#{connection.quote(id)}, #{connection.quote(workspace_id)})
        SQL
      end

      def count_rows(table_name, where: nil)
        connection = Database.connection
        sql = "SELECT COUNT(*)::int AS count FROM #{quote_table(table_name)}"
        sql << " WHERE #{where}" if where
        connection.execute(sql).first["count"].to_i
      end

      def partition_attached?(parent_name, child_name)
        connection = Database.connection
        connection.execute(<<~SQL).first["count"].to_i.positive?
          SELECT COUNT(*) AS count
          FROM pg_catalog.pg_inherits i
          JOIN pg_class parent ON parent.oid = i.inhparent
          JOIN pg_namespace parent_ns ON parent_ns.oid = parent.relnamespace
          JOIN pg_class child ON child.oid = i.inhrelid
          JOIN pg_namespace child_ns ON child_ns.oid = child.relnamespace
          WHERE parent_ns.nspname = 'public'
            AND child_ns.nspname = 'public'
            AND parent.relname = #{connection.quote(parent_name)}
            AND child.relname = #{connection.quote(child_name)}
        SQL
      end

      def drop_table_cascade!(table_name)
        return unless table_name

        Database.connection.execute("DROP TABLE IF EXISTS #{quote_table(table_name)} CASCADE")
      rescue ActiveRecord::StatementInvalid
        nil
      end

      def default_name(table_name)
        "#{table_name}_default"
      end

      def current_name(table_name)
        "#{table_name}_current"
      end

      def future_name(table_name)
        "#{table_name}_future"
      end

      def month_partition_name(table_name, date)
        "#{table_name}_#{date.strftime("%Y_%m")}"
      end

      def quote_table(name)
        Database.connection.quote_table_name(name)
      end
    end
  end
end
