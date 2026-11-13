require "spec_helper"
require "partition_gardener/stdlib_extensions"

RSpec.describe PartitionGardener::IntegerDurationMethods do
  it "installs minutes and seconds helpers when Active Support Duration is absent" do
    # Spec helper loads Active Support; install is a no-op when Duration exists.
    expect { PartitionGardener.install_stdlib_extensions! }.not_to raise_error

    if defined?(ActiveSupport::Duration)
      expect(Integer.included_modules).not_to include(described_class)
    else
      expect(2.minutes).to eq(120)
      expect(3.seconds).to eq(3)
    end
  end
end
