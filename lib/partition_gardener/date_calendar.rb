module PartitionGardener
  module DateCalendar
    module_function

    def to_date(value)
      value.respond_to?(:to_date) ? value.to_date : Date.parse(value.to_s)
    end

    def beginning_of_month(date)
      value = to_date(date)
      Date.new(value.year, value.month, 1)
    end

    def beginning_of_year(date)
      value = to_date(date)
      Date.new(value.year, 1, 1)
    end

    def beginning_of_day(date)
      to_date(date)
    end

    def beginning_of_week(date)
      value = to_date(date)
      value - ((value.wday + 6) % 7)
    end

    def beginning_of_quarter(date)
      value = to_date(date)
      quarter_month = ((value.month - 1) / 3) * 3 + 1
      Date.new(value.year, quarter_month, 1)
    end

    def add_days(date, count)
      to_date(date) + count
    end

    def add_weeks(date, count)
      add_days(date, count * 7)
    end

    def add_quarters(date, count)
      add_months(date, count * 3)
    end

    def next_month(date)
      add_months(beginning_of_month(date), 1)
    end

    def next_year(date)
      Date.new(to_date(date).year + 1, 1, 1)
    end

    def add_years(date, count)
      value = to_date(date)
      Date.new(value.year + count, value.month, value.day)
    end

    def add_months(date, count)
      base = beginning_of_month(date)
      month_index = (base.year * 12) + (base.month - 1) + count
      Date.new(month_index / 12, (month_index % 12) + 1, 1)
    end
  end
end
