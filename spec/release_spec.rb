require "spec_helper"
require "open3"
require "tmpdir"
require_relative "../usr/lib/release_version_check"

RSpec.describe ReleaseVersionCheck do
  let(:bootstrap) do
    <<~RUBY
      require_relative "usr/lib/release_version_check"
      module ReleaseVersionCheck
        def self.warn_if_already_released(**); end
      end
      Kernel.prepend(Module.new do
        def system(*command)
          puts "EXEC:\#{command.last}"
          true
        end

        def `(command)
          ""
        end
      end)
      load "usr/bin/release.rb"
    RUBY
  end

  describe ".changelog_notes_for" do
    def write_changelog(content)
      path = File.join(Dir.mktmpdir, "CHANGELOG.md")
      File.write(path, content)
      path
    end

    it "returns the body under the matching version heading until the next heading" do
      path = write_changelog(<<~MD)
        # CHANGELOG

        ## Unreleased

        ## 0.3.9 (2026-11-13)

        - First
        - Second

        ## 0.3.8 (2026-11-05)

        - Older
      MD

      expect(described_class.changelog_notes_for("0.3.9", path: path)).to eq("- First\n- Second\n")
    end

    it "accepts bracketed Keep a Changelog headings" do
      path = write_changelog(<<~MD)
        ## [1.2.3] - 2026-11-13

        - Notes
      MD

      expect(described_class.changelog_notes_for("1.2.3", path: path)).to eq("- Notes\n")
    end

    it "returns nil when the version heading is missing or the section has no body" do
      path = write_changelog(<<~MD)
        ## 0.3.9 (2026-11-13)

        ## 0.3.8 (2026-11-05)

        - Older
      MD

      expect(described_class.changelog_notes_for("9.9.9", path: path)).to be_nil
      expect(described_class.changelog_notes_for("0.3.9", path: path)).to be_nil
    end
  end

  it "refuses to publish when standard input ends without an answer" do
    output, error, status = Open3.capture3(Gem.ruby, "-e", bootstrap, stdin_data: "")

    aggregate_failures do
      expect(status.exitstatus).to eq(1), error
      expect(output).not_to include("EXEC:gem push")
    end
  end

  it "accepts the displayed default after an explicit Enter" do
    output, error, status = Open3.capture3(Gem.ruby, "-e", bootstrap, stdin_data: "\n")

    aggregate_failures do
      expect(status).to be_success, error
      expect(output).to include("EXEC:gem push")
      expect(output).to include("EXEC:gh release create")
      expect(output).to include("--notes-file tmp/github-release-notes.md")
      expect(output).not_to include("--generate-notes")
    end
  end
end
