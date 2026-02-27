require "../../spec_helper"

module Ameba::LSP
  describe Analyzer do
    it "returns issues and diagnostics for a source" do
      config = Ameba::Config.load(skip_reading_config: true)
      config.rules.each(&.enabled = false)
      config.update_rule(Ameba::ErrorRule.rule_name, enabled: true)

      source = Ameba::Source.new("a = 1\n", "source.cr")
      result = Analyzer.new.analyze(source, config, disable_typing_noise_rules: false)

      result.issues.size.should eq 1
      result.diagnostics.size.should eq 1
      result.diagnostics.first.message.should eq "[#{Ameba::ErrorRule.rule_name}] This rule always adds an error"
    end

    it "restores config state after analysis" do
      config = Ameba::Config.load(skip_reading_config: true)
      source = Ameba::Source.new("a = 1\n", "source.cr")
      preserved_source = Ameba::Source.new("puts :ok\n", "preserved.cr")
      config.sources = [preserved_source]

      checks = 0
      preserved_check = -> do
        checks += 1
        nil
      end
      config.cancellation_check = preserved_check

      preserved_formatter = Ameba::DummyFormatter.new
      config.formatter = preserved_formatter

      trailing_whitespace_rule = config.rules.find!(&.name.==("Layout/TrailingWhitespace"))
      trailing_whitespace_rule.enabled = true

      Analyzer.new.analyze(source, config)

      config.sources.should eq [preserved_source]
      config.formatter.should be preserved_formatter
      config.cancellation_check.should_not be_nil
      config.cancellation_check.try &.call
      checks.should eq 1
      trailing_whitespace_rule.enabled?.should be_true
    end
  end
end
