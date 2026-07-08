require "json"
require "optparse"

module PartitionGardener
  class CLI
    def self.start(argv = ARGV)
      new(argv).run
    end

    def initialize(argv)
      @argv = argv.dup
      @options = {
        pretty: false,
        rails: false,
        registry: nil,
        table: nil,
        all: false,
        confirm: false
      }
    end

    def run
      parse_options!
      command = @argv.shift || "help"
      @options[:table] ||= @argv.first

      case command
      when "plan"
        load_context!
        print_json(plan_output)
      when "audit"
        load_context!
        print_json(audit_output)
      when "apply"
        abort_with_help("apply requires --confirm (mutates the database)") unless @options[:confirm]
        load_context!
        print_json(apply_output)
      when "help", "-h", "--help"
        print_help
      else
        abort_with_help("unknown command: #{command}")
      end
    end

    private

    def parse_options!
      OptionParser.new do |parser|
        parser.banner = "Usage: partition_gardener [options] <plan|audit|apply> [table_name]"
        parser.on("--table NAME", "Table name (default: first positional argument)") { |value| @options[:table] = value }
        parser.on("--all", "All registered tables") { @options[:all] = true }
        parser.on("--registry PATH", "Load registry from JSON file") { |value| @options[:registry] = value }
        parser.on("--rails", "Load registry from Rails environment") { @options[:rails] = true }
        parser.on("--pretty", "Pretty-print JSON") { @options[:pretty] = true }
        parser.on("--confirm", "Required for apply (mutates the database)") { @options[:confirm] = true }
      end.parse!(@argv)
    end

    def load_context!
      if @options[:registry]
        ConfigDocument.load_registry_file!(@options[:registry])
      elsif @options[:rails]
        load_rails!
      elsif Registry.tables.empty?
        abort_with_help("no tables registered; pass --registry PATH or --rails")
      end
    end

    def load_rails!
      root = find_rails_root(Dir.pwd) || abort("could not find Rails application root")
      require File.join(root, "config", "environment")
    end

    def find_rails_root(start_directory)
      directory = start_directory
      loop do
        return directory if File.exist?(File.join(directory, "config", "application.rb"))

        parent = File.dirname(directory)
        return nil if parent == directory

        directory = parent
      end
    end

    def plan_output
      if @options[:all]
        {
          schema_version: PlanReport::SCHEMA_VERSION,
          tables: PartitionGardener.send(:plan_all)
        }
      else
        table_name = required_table_name!
        configs = Registry.configs_for_table(table_name)
        abort_with_help("no config for table #{table_name}") if configs.empty?

        if configs.one?
          PlanReport.build(configs.first).to_h
        else
          {
            schema_version: PlanReport::SCHEMA_VERSION,
            parent_table_name: table_name,
            tables: configs.map { |config| PlanReport.build(config).to_h }
          }
        end
      end
    end

    def audit_output
      if @options[:all]
        {
          schema_version: Audit::SCHEMA_VERSION,
          tables: Registry.expanded_table_configs.map { |config| audit_to_h(config[:table_name], config: config) }
        }
      else
        table_name = required_table_name!
        configs = Registry.configs_for_table(table_name)
        abort_with_help("no config for table #{table_name}") if configs.empty?

        if configs.one?
          audit_to_h(table_name, config: configs.first)
        else
          {
            schema_version: Audit::SCHEMA_VERSION,
            parent_table_name: table_name,
            tables: configs.map { |config| audit_to_h(config[:table_name], config: config) }
          }
        end
      end
    end

    def apply_output
      table_name = @options[:all] ? nil : @options[:table]
      PartitionGardener.run!(table_name: table_name).to_h
    end

    def audit_to_h(table_name, config: nil)
      result = Audit.call(table_name, config: config)
      {
        schema_version: Audit::SCHEMA_VERSION,
        table_name: result.table_name,
        partitioned: result.partitioned,
        default_row_count: result.default_row_count,
        attached_child_count: result.attached_child_count,
        horizon_days: result.horizon_days,
        gaps: result.gaps.map { |gap| {range_start: gap.range_start, range_end: gap.range_end, message: gap.message} },
        warnings: result.warnings
      }
    end

    def required_table_name!
      table_name = @options[:table]
      abort_with_help("table name is required (or pass --all)") unless table_name

      table_name
    end

    def print_json(payload)
      json = if @options[:pretty]
        JSON.pretty_generate(payload)
      else
        JSON.generate(payload)
      end

      puts json
    end

    def print_help
      puts <<~HELP
        partition_gardener — plan, audit, and apply partition maintenance

        Commands:
          plan   Print target layout diff as JSON (dry-run)
          audit  Print partition layout audit warnings as JSON
          apply  Run maintenance for registered tables (single table unless --all)

        Examples:
          partition_gardener --rails plan audits
          partition_gardener --registry config/tables.json audit --all
          partition_gardener --rails apply --confirm audits
      HELP
    end

    def abort_with_help(message)
      warn message
      print_help
      exit 1
    end
  end
end
