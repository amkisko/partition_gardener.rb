require "spec_helper"

RSpec.describe PartitionGardener::MaintenanceBackend do
  let(:config) do
    {
      table_name: "events",
      maintenance_backend: backend
    }
  end

  describe ".skipped?" do
    context "when backend is pg_partman" do
      let(:backend) { :pg_partman }

      it "skips gardener maintenance" do
        expect(described_class.skipped?(config)).to be(true)
      end
    end

    context "when backend is gardener" do
      let(:backend) { :gardener }

      it "does not skip" do
        expect(described_class.skipped?(config)).to be(false)
      end
    end

    context "when backend is hybrid_layout_only" do
      let(:backend) { :hybrid_layout_only }

      it "does not skip gardener maintenance" do
        expect(described_class.skipped?(config)).to be(false)
      end

      it "is recognized as hybrid" do
        expect(described_class.hybrid?(config)).to be(true)
      end
    end
  end

  describe ".validate!" do
    before do
      allow(described_class).to receive(:partman_parent_configured?).and_return(partman_row)
      PartitionGardener.configuration.strict_maintenance_backend_validation = strict
      PartitionGardener.configuration.notifier = ->(message, **) { notifier << message }
    end

    let(:strict) { false }
    let(:partman_row) { false }
    let(:backend) { :gardener }
    let(:notifier) { [] }

    context "when gardener is registered but partman also owns the parent" do
      let(:partman_row) { true }

      it "notifies by default" do
        described_class.validate!(config)

        expect(notifier).to include(a_string_matching(/pick one maintainer/))
      end

      context "when strict validation is enabled" do
        let(:strict) { true }

        it "raises ValidationError" do
          expect {
            described_class.validate!(config)
          }.to raise_error(described_class::ValidationError, /pick one maintainer/)
        end
      end
    end

    context "when pg_partman is registered without a partman row" do
      let(:backend) { :pg_partman }

      it "notifies by default" do
        described_class.validate!(config)

        expect(notifier).to include(a_string_matching(/partman\.part_config has no row/))
      end

      context "when strict validation is enabled" do
        let(:strict) { true }

        it "raises ValidationError" do
          expect {
            described_class.validate!(config)
          }.to raise_error(described_class::ValidationError, /partman\.part_config has no row/)
        end
      end
    end
  end
end
