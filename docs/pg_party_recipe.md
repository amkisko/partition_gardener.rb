# pg_party recipe — partitioned table creation

Use [pg_party](https://github.com/rkrage/pg_party) in migrations only. Partition Gardener owns nightly runtime maintenance after cutover.

## Migration outline

```ruby
class PartitionEvents < ActiveRecord::Migration[8.0]
  def up
    create_range_partition :events,
      partition_key: :occurred_on,
      template: false

    create_default_partition :events

    # Minimal premake at creation; gardener extends the window after cutover
    [Date.today.beginning_of_month, Date.today.next_month.beginning_of_month].each do |month|
      create_range_partition_of :events,
        name: "events_#{month.strftime('%Y_%m')}",
        start_range: month,
        end_range: month.next_month.beginning_of_month
    end

    add_index :events, %i[id occurred_on], unique: true
  end
end
```

## Cutover

1. Backfill shadow partitioned table (`p_events`) from current table.
2. Include `PartitionGardener::Migration::HotSwitchConcern` in a follow-up migration.
3. `hot_switch_tables` with `months_ahead: 1`.
4. Register `events` in `PartitionGardener::Registry` with `sliding_window_monthly`.
5. Enable nightly `PartitionGardener.run!`.

Full playbook: [cutover.md](cutover.md).

## Do not

- Call pg_party `create_range_partition_of` every night for the same bounds gardener maintains.
- Run pg_partman premake and gardener tail rebalance on the same parent without `hybrid_layout_only`.

See [tooling_split.md](tooling_split.md) for the three-way responsibility split.
