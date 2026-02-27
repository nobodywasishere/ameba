require "../../spec_helper"

module Ameba::LSP
  describe CodeActions do
    it "returns edits for a correctable issue" do
      source = Ameba::Source.new("class A; end\n", "source.cr")
      rule = Ameba::AtoB.new
      rule.test(source)

      issue = source.issues.first
      edits = CodeActions.edits_for(issue, source.code)

      edits.size.should eq 1
      edits.first.replacement.should eq "B"
      edits.first.begin_pos.should be < edits.first.end_pos
    end

    it "returns no edits for a non-correctable issue" do
      source = Ameba::Source.new("a = 1\n", "source.cr")
      issue = source.add_issue(Ameba::ErrorRule.new, {1, 1}, "x")

      CodeActions.edits_for(issue, source.code).should be_empty
    end
  end
end
