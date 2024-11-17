require "../../spec_helper"
require "file_utils"

CONFIG_PATH = Path[Dir.tempdir] / Ameba::Config::FILENAME

module Ameba
  private def with_formatter(&)
    io = IO::Memory.new
    formatter = Formatter::TODOFormatter.new(io, CONFIG_PATH)

    yield formatter, io
  end

  private def create_todo
    with_formatter do |formatter|
      source = Source.new "a = 1", "source.cr"
      source.add_issue DummyRule.new, {1, 2}, "message"

      formatter.finished([source])

      File.exists?(CONFIG_PATH) ? File.read(CONFIG_PATH) : ""
    end
  end

  describe Formatter::TODOFormatter do
    ::Spec.after_each do
      FileUtils.rm_rf(CONFIG_PATH)
    end

    context "problems not found" do
      it "does not create file" do
        with_formatter do |formatter|
          file = formatter.finished [Source.new ""]
          file.should be_nil
        end
      end

      it "reports a message saying file is not created" do
        with_formatter do |formatter, io|
          formatter.finished [Source.new ""]
          io.to_s.should contain "No issues found. File is not generated"
        end
      end
    end

    context "problems found" do
      it "prints a message saying file is created" do
        with_formatter do |formatter, io|
          s = Source.new "a = 1", "source.cr"
          s.add_issue DummyRule.new, {1, 2}, "message"
          formatter.finished([s])
          io.to_s.should contain "Created #{CONFIG_PATH}"
        end
      end

      it "creates a valid YAML document" do
        YAML.parse(create_todo).should_not be_nil
      end

      it "creates a todo with header" do
        create_todo.should contain "# This configuration file was generated by"
      end

      it "creates a todo with UTC time" do
        create_todo.should match /\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2} UTC/
      end

      it "creates a todo with version" do
        create_todo.should contain "Ameba version #{VERSION}"
      end

      it "creates a todo with a rule name" do
        create_todo.should contain "DummyRule"
      end

      it "creates a todo with severity" do
        create_todo.should contain "Convention"
      end

      it "creates a todo with problems count" do
        create_todo.should contain "Problems found: 1"
      end

      it "creates a todo with run details" do
        create_todo.should contain "Run `ameba --only #{DummyRule.rule_name}`"
      end

      it "excludes source from this rule" do
        create_todo.should contain "Excluded:\n  - source.cr"
      end

      context "with multiple issues" do
        it "does generate todo file" do
          with_formatter do |formatter|
            s1 = Source.new "a = 1", "source1.cr"
            s2 = Source.new "a = 1", "source2.cr"
            s1.add_issue DummyRule.new, {1, 2}, "message1"
            s1.add_issue NamedRule.new, {1, 2}, "message1"
            s1.add_issue DummyRule.new, {2, 2}, "message1"
            s2.add_issue DummyRule.new, {2, 2}, "message2"

            formatter.finished([s1, s2])

            content = File.read(CONFIG_PATH)
            content.should contain <<-CONTENT
              # Problems found: 3
              # Run `ameba --only Ameba/DummyRule` for details
              Ameba/DummyRule:
                Description: Dummy rule that does nothing.
                Dummy: true
                Excluded:
                - source1.cr
                - source2.cr
                Enabled: true
                Severity: Convention
              CONTENT
          end
        end
      end

      context "when invalid syntax" do
        it "does generate todo file" do
          with_formatter do |formatter|
            s = Source.new "def invalid_syntax"
            s.add_issue Rule::Lint::Syntax.new, {1, 2}, "message"

            file = formatter.finished [s]
            file.should be_nil
          end
        end

        it "prints an error message" do
          with_formatter do |formatter, io|
            s = Source.new "def invalid_syntax"
            s.add_issue Rule::Lint::Syntax.new, {1, 2}, "message"

            formatter.finished [s]
            io.to_s.should contain "Unable to generate TODO file"
            io.to_s.should contain "Please fix syntax issues"
          end
        end
      end
    end
  end
end
