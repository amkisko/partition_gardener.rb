module PartitionGardener
  module DateBucket
    module_function

    def normalize(bucket)
      bucket.to_sym
    end

    def active_key(bucket)
      case normalize(bucket)
      when :day then :active_days
      when :week then :active_weeks
      when :quarter then :active_quarters
      when :year then :active_years
      else :active_months
      end
    end

    def default_active_span(bucket)
      case normalize(bucket)
      when :day then 90
      when :week then 52
      when :quarter then 8
      when :year then 2
      else 12
      end
    end

    def date_trunc_unit(bucket)
      case normalize(bucket)
      when :day then "day"
      when :week then "week"
      when :quarter then "quarter"
      when :year then "year"
      else "month"
      end
    end

    def beginning_of_bucket(date, bucket)
      case normalize(bucket)
      when :day then DateCalendar.beginning_of_day(date)
      when :week then DateCalendar.beginning_of_week(date)
      when :quarter then DateCalendar.beginning_of_quarter(date)
      when :year then DateCalendar.beginning_of_year(date)
      else DateCalendar.beginning_of_month(date)
      end
    end

    def end_of_bucket(date, bucket)
      beginning_of_bucket(next_bucket(date, bucket), bucket)
    end

    def next_bucket(date, bucket)
      case normalize(bucket)
      when :day then DateCalendar.add_days(date, 1)
      when :week then DateCalendar.add_weeks(date, 1)
      when :quarter then DateCalendar.add_quarters(date, 1)
      when :year then DateCalendar.next_year(date)
      else DateCalendar.next_month(date)
      end
    end

    def add_buckets(date, count, bucket)
      case normalize(bucket)
      when :day then DateCalendar.add_days(date, count)
      when :week then DateCalendar.add_weeks(date, count)
      when :quarter then DateCalendar.add_quarters(date, count)
      when :year then DateCalendar.add_years(date, count)
      else DateCalendar.add_months(date, count)
      end
    end

    def partition_name_suffix(identifier, bucket)
      case normalize(bucket)
      when :day then identifier.strftime("%Y_%m_%d")
      when :week then identifier.strftime("%G_W%V")
      when :quarter
        quarter = ((identifier.month - 1) / 3) + 1
        format("%d_Q%d", identifier.year, quarter)
      when :year then identifier.year.to_s
      else identifier.strftime("%Y_%m")
      end
    end

    def partition_name(table_name, identifier, bucket)
      "#{table_name}_#{partition_name_suffix(identifier, bucket)}"
    end

    def archive_bucket_from_partition_name(table_name, partition_name, bucket)
      case normalize(bucket)
      when :day
        match = partition_name.match(/^#{Regexp.escape(table_name)}_(\d{4})_(\d{2})_(\d{2})$/)
        return Date.new(match[1].to_i, match[2].to_i, match[3].to_i) if match
      when :week
        match = partition_name.match(/^#{Regexp.escape(table_name)}_(\d{4})_W(\d{2})$/)
        return DateCalendar.beginning_of_week(Date.strptime("#{match[1]}-W#{match[2]}-1", "%G-W%V-%u")) if match
      when :quarter
        match = partition_name.match(/^#{Regexp.escape(table_name)}_(\d{4})_Q([1-4])$/)
        return Date.new(match[1].to_i, ((match[2].to_i - 1) * 3) + 1, 1) if match
      when :year
        match = partition_name.match(/^#{Regexp.escape(table_name)}_(\d{4})$/)
        return Date.new(match[1].to_i, 1, 1) if match
      else
        match = partition_name.match(/^#{Regexp.escape(table_name)}_(\d{4})_(\d{2})$/)
        return Date.new(match[1].to_i, match[2].to_i, 1) if match
      end

      nil
    end

    def partition_definition_clause(date, bucket)
      start_range = beginning_of_bucket(date, bucket)
      end_range = end_of_bucket(date, bucket)
      "FROM ('#{start_range}') TO ('#{end_range}')"
    end
  end
end
