require "../../spec_helper"

module Ameba::LSP
  describe DiagnosticsFormatter do
    it "converts issues to diagnostics with zero-based ranges" do
      formatter = DiagnosticsFormatter.new
      source = Ameba::Source.new("a = 1\n", "source.cr")
      rule = Ameba::ErrorRule.from_yaml("{ Severity: warning, Message: warn }")
      source.add_issue(rule, {1, 2}, {1, 4}, "warn")

      formatter.source_finished(source)

      diagnostic = formatter.diagnostics.first
      diagnostic.message.should eq "[#{rule.name}] warn"
      diagnostic.severity.should eq Ameba::LSP::Protocol::DiagnosticSeverity::Warning
      diagnostic.range.start.line.should eq 0_u32
      diagnostic.range.start.character.should eq 1_u32
      diagnostic.range.end.line.should eq 0_u32
      diagnostic.range.end.character.should eq 4_u32
    end

    it "checks cancellation between diagnostics" do
      checks = 0
      formatter = DiagnosticsFormatter.new
      formatter.cancellation_check = -> do
        checks += 1
        nil
      end

      source = Ameba::Source.new("a = 1\n", "source.cr")
      source.add_issue(Ameba::ErrorRule.new, {1, 1}, "one")
      source.add_issue(Ameba::ErrorRule.new, {1, 1}, "two")

      formatter.source_finished(source)
      checks.should eq 2
    end
  end
end
