module PartitionGardener
  module Templates
    module_function

    def normalize(config)
      config = config.dup
      config[:layout] ||= :sliding_window
      config[:bucket] ||= :month if date_layout?(config[:layout])
      config
    end

    def expand(config)
      normalized = normalize(config)
      return [normalized] unless normalized[:layout] == :composite

      configs = []
      parent_mode = normalized.fetch(:parent_mode, :list)

      case parent_mode
      when :list
        if normalized[:list_branches]
          configs << list_split(
            table_name: normalized[:table_name],
            branches: normalized[:list_branches],
            conflict_key: normalized[:conflict_key],
            partition_key_column: normalized.fetch(:partition_key_column, normalized[:discriminator_column])
          )
        end
      when :range
        configs << range_parent_config_for(normalized)
      end

      normalized.fetch(:branches, []).each do |branch|
        configs << branch_config_for(normalized, branch)
      end

      configs
    end

    def sliding_window_monthly(table_name:, partition_key_column:, conflict_key:, active_months: 12, split_row_threshold: nil, **options)
      sliding_window_for_bucket(
        :month,
        table_name: table_name,
        partition_key_column: partition_key_column,
        conflict_key: conflict_key,
        active_months: active_months,
        split_row_threshold: split_row_threshold,
        **options
      )
    end

    def sliding_window_daily(table_name:, partition_key_column:, conflict_key:, active_days: 90, split_row_threshold: nil, **options)
      sliding_window_for_bucket(
        :day,
        table_name: table_name,
        partition_key_column: partition_key_column,
        conflict_key: conflict_key,
        active_days: active_days,
        split_row_threshold: split_row_threshold,
        **options
      )
    end

    def sliding_window_weekly(table_name:, partition_key_column:, conflict_key:, active_weeks: 52, split_row_threshold: nil, **options)
      sliding_window_for_bucket(
        :week,
        table_name: table_name,
        partition_key_column: partition_key_column,
        conflict_key: conflict_key,
        active_weeks: active_weeks,
        split_row_threshold: split_row_threshold,
        **options
      )
    end

    def sliding_window_quarterly(table_name:, partition_key_column:, conflict_key:, active_quarters: 8, split_row_threshold: nil, **options)
      sliding_window_for_bucket(
        :quarter,
        table_name: table_name,
        partition_key_column: partition_key_column,
        conflict_key: conflict_key,
        active_quarters: active_quarters,
        split_row_threshold: split_row_threshold,
        **options
      )
    end

    def rolling_current_monthly(table_name:, partition_key_column:, conflict_key:, active_months: 12, **options)
      sliding_window_monthly(
        table_name: table_name,
        partition_key_column: partition_key_column,
        conflict_key: conflict_key,
        active_months: active_months,
        layout: :rolling_current,
        split_row_threshold: Float::INFINITY,
        **options
      )
    end

    def premake_monthly(table_name:, partition_key_column:, conflict_key:, premake_months: 3, split_row_threshold: nil, **options)
      normalize({
        table_name: table_name,
        layout: :premake_monthly,
        bucket: :month,
        partition_key_column: partition_key_column,
        conflict_key: conflict_key,
        premake_months: premake_months,
        maintenance_backend: options.fetch(:maintenance_backend, :gardener),
        partition_name_format: options.fetch(:partition_name_format) {
          ->(identifier) { DateBucket.partition_name(table_name, identifier, :month) }
        },
        partition_definition: options.fetch(:partition_definition) {
          ->(date) { DateBucket.partition_definition_clause(date, :month) }
        },
        extract_partition_identifier: options.fetch(:extract_partition_identifier) {
          ->(date_value) { DateBucket.beginning_of_bucket(date_value, :month) }
        }
      }.merge(options.except(:partition_name_format, :partition_definition, :extract_partition_identifier)).tap do |config|
        config[:split_row_threshold] = split_row_threshold if split_row_threshold
      end)
    end

    def calendar_year(table_name:, partition_key_column:, conflict_key:, active_years: 2, split_row_threshold: nil, **options)
      normalize({
        table_name: table_name,
        layout: :calendar_year,
        bucket: :year,
        partition_key_column: partition_key_column,
        conflict_key: conflict_key,
        active_years: active_years,
        partition_name_format: options.fetch(:partition_name_format) {
          ->(identifier) { DateBucket.partition_name(table_name, identifier, :year) }
        },
        partition_definition: options.fetch(:partition_definition) {
          ->(date) { DateBucket.partition_definition_clause(date, :year) }
        },
        extract_partition_identifier: options.fetch(:extract_partition_identifier) {
          ->(date_value) { DateBucket.beginning_of_bucket(date_value, :year) }
        }
      }.merge(options.except(:partition_name_format, :partition_definition, :extract_partition_identifier)).tap do |config|
        config[:split_row_threshold] = split_row_threshold if split_row_threshold
      end)
    end

    def integer_window(table_name:, partition_key_column:, conflict_key:, active_id_lo: 0, active_id_width: nil, current_band_size: nil, split_row_threshold: nil, **options)
      normalize({
        table_name: table_name,
        layout: :integer_window,
        partition_key_column: partition_key_column,
        conflict_key: conflict_key,
        active_id_lo: active_id_lo,
        active_id_width: active_id_width || Strategy::IntegerRange::DEFAULT_ACTIVE_ID_WIDTH,
        current_band_size: current_band_size || Strategy::IntegerRange::DEFAULT_CURRENT_BAND_SIZE,
        archive_band_size: options.fetch(:archive_band_size, Strategy::IntegerRange::DEFAULT_ARCHIVE_BAND_SIZE)
      }.merge(options).tap do |config|
        config[:split_row_threshold] = split_row_threshold if split_row_threshold
      end)
    end

    def hash_branches(table_name:, partition_key_column:, conflict_key:, hash_modulus: nil, split_row_threshold: nil, **options)
      normalize({
        table_name: table_name,
        layout: :hash_branches,
        partition_key_column: partition_key_column,
        conflict_key: conflict_key,
        hash_modulus: hash_modulus || Strategy::HashBranches::DEFAULT_MODULUS
      }.merge(options).tap do |config|
        config[:split_row_threshold] = split_row_threshold if split_row_threshold
      end)
    end

    def list_split(table_name:, branches:, conflict_key:, partition_key_column: nil, **options)
      discriminator_column = partition_key_column || branches.first&.fetch(:discriminator_column, nil)
      normalized_branches = Predicate.normalize_branches!(
        branches,
        discriminator_column: discriminator_column
      )

      normalize({
        table_name: table_name,
        layout: :list_split,
        branches: normalized_branches,
        conflict_key: conflict_key,
        partition_key_column: partition_key_column || discriminator_column || "id"
      }.merge(options))
    end

    def composite_list_hash(parent_table:, discriminator_column:, branches:, conflict_key:, **options)
      composite_with_branches(
        parent_table: parent_table,
        discriminator_column: discriminator_column,
        branches: branches,
        conflict_key: conflict_key,
        parent_mode: :list,
        default_child_layout: :hash_branches,
        **options
      )
    end

    def composite_list_range(parent_table:, discriminator_column:, branches:, conflict_key:, bucket: :month, **options)
      composite_with_branches(
        parent_table: parent_table,
        discriminator_column: discriminator_column,
        branches: branches,
        conflict_key: conflict_key,
        parent_mode: :list,
        default_child_layout: :sliding_window,
        default_child_bucket: bucket,
        **options
      )
    end

    def list_range(parent_table:, discriminator_column:, branches:, conflict_key:, **options)
      composite_list_range(
        parent_table: parent_table,
        discriminator_column: discriminator_column,
        branches: branches,
        conflict_key: conflict_key,
        **options
      )
    end

    def composite_range_hash(parent_table:, partition_key_column:, branches:, conflict_key:, bucket: :month, **options)
      composite_with_branches(
        parent_table: parent_table,
        partition_key_column: partition_key_column,
        branches: branches,
        conflict_key: conflict_key,
        parent_mode: :range,
        parent_bucket: bucket,
        default_child_layout: :hash_branches,
        **options
      )
    end

    def composite_range_list(parent_table:, partition_key_column:, branches:, conflict_key:, bucket: :month, **options)
      composite_with_branches(
        parent_table: parent_table,
        partition_key_column: partition_key_column,
        branches: branches,
        conflict_key: conflict_key,
        parent_mode: :range,
        parent_bucket: bucket,
        default_child_layout: :list_split,
        **options
      )
    end

    def branch_config_for(parent_config, branch)
      branch_table_name = "#{parent_config[:table_name]}_#{branch.fetch(:name)}"
      child = branch.dup
      child.delete(:name)
      child[:table_name] = branch_table_name
      child[:parent_table_name] = parent_config[:table_name]
      child[:layout] ||= parent_config.fetch(:default_child_layout, :hash_branches)

      if child[:layout] == :sliding_window
        child[:bucket] ||= parent_config.fetch(:default_child_bucket, :month)
        child[:partition_key_column] ||= branch.fetch(:partition_key_column)
        return sliding_window_for_bucket(
          child[:bucket],
          table_name: branch_table_name,
          partition_key_column: child[:partition_key_column],
          conflict_key: parent_config[:conflict_key],
          parent_table_name: parent_config[:table_name],
          split_row_threshold: child[:split_row_threshold],
          active_months: child[:active_months],
          active_days: child[:active_days],
          active_weeks: child[:active_weeks],
          active_quarters: child[:active_quarters]
        )
      end

      if child[:layout] == :list_split
        child[:branches] = branch.fetch(:branches)
        child[:conflict_key] = parent_config[:conflict_key]
        return list_split(
          table_name: branch_table_name,
          branches: child[:branches],
          conflict_key: child[:conflict_key],
          partition_key_column: child[:partition_key_column],
          parent_table_name: parent_config[:table_name]
        )
      end

      normalize(child)
    end

    def date_layout?(layout)
      layout == :sliding_window || layout == :calendar_year || layout == :premake_monthly || layout == :rolling_current
    end

    def sliding_window_for_bucket(bucket, table_name:, partition_key_column:, conflict_key:, split_row_threshold: nil, layout: :sliding_window, **options)
      active_key = DateBucket.active_key(bucket)
      active_value = options[active_key] || DateBucket.default_active_span(bucket)

      normalize({
        table_name: table_name,
        layout: layout,
        bucket: bucket,
        partition_key_column: partition_key_column,
        conflict_key: conflict_key,
        active_key => active_value,
        partition_name_format: options.fetch(:partition_name_format) {
          ->(identifier) { DateBucket.partition_name(table_name, identifier, bucket) }
        },
        partition_definition: options.fetch(:partition_definition) {
          ->(date) { DateBucket.partition_definition_clause(date, bucket) }
        },
        extract_partition_identifier: options.fetch(:extract_partition_identifier) {
          ->(date_value) { DateBucket.beginning_of_bucket(date_value, bucket) }
        }
      }.merge(options.except(:partition_name_format, :partition_definition, :extract_partition_identifier, active_key)).tap do |config|
        config[:split_row_threshold] = split_row_threshold if split_row_threshold
      end)
    end

    def composite_with_branches(parent_table:, branches:, conflict_key:, parent_mode:, default_child_layout:, discriminator_column: nil, partition_key_column: nil, parent_bucket: :month, default_child_bucket: :month, **options)
      list_branch_entries = Predicate.list_branch_entries(branches, discriminator_column: discriminator_column) if parent_mode == :list

      child_branches = branches.map do |branch|
        entry = {
          name: branch.fetch(:name),
          layout: branch.fetch(:layout, default_child_layout)
        }
        entry[:partition_key_column] = branch[:partition_key_column] if branch[:partition_key_column]
        entry[:hash_modulus] = branch.fetch(:hash_modulus, Strategy::HashBranches::DEFAULT_MODULUS) if entry[:layout] == :hash_branches
        entry[:bucket] = branch.fetch(:bucket, default_child_bucket) if entry[:layout] == :sliding_window
        entry[:active_months] = branch[:active_months] if branch[:active_months]
        entry[:active_days] = branch[:active_days] if branch[:active_days]
        entry[:active_weeks] = branch[:active_weeks] if branch[:active_weeks]
        entry[:active_quarters] = branch[:active_quarters] if branch[:active_quarters]
        entry[:split_row_threshold] = branch[:split_row_threshold] if branch[:split_row_threshold]
        entry[:branches] = branch[:branches] if branch[:branches]
        entry
      end

      normalize({
        table_name: parent_table,
        layout: :composite,
        parent_mode: parent_mode,
        bucket: parent_bucket,
        discriminator_column: discriminator_column,
        partition_key_column: partition_key_column,
        conflict_key: conflict_key,
        default_child_layout: default_child_layout,
        default_child_bucket: default_child_bucket,
        list_branches: parent_mode == :list ? list_branch_entries : nil,
        branches: child_branches
      }.compact.merge(options))
    end

    def range_parent_config_for(parent_config)
      bucket = parent_config.fetch(:bucket, :month)
      base = {
        table_name: parent_config[:table_name],
        partition_key_column: parent_config.fetch(:partition_key_column),
        conflict_key: parent_config[:conflict_key]
      }
      passthrough = parent_config.slice(
        :active_months, :active_days, :active_weeks, :active_quarters, :active_years,
        :split_row_threshold, :maintenance_backend, :retention_months, :move_batch_size,
        :statement_timeout, :incremental_rebalance, :analyze_after_rebalance
      )

      if bucket == :year
        calendar_year(**base, **passthrough)
      else
        sliding_window_for_bucket(bucket, **base, **passthrough)
      end
    end
  end
end
