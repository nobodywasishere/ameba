require "../../../spec_helper"

module Ameba::Rule::Lint
  describe Semantic do
    subject = Semantic.new

    it "returns semantic context for semantically valid code" do
      source = Source.new <<-CRYSTAL, "source.cr"
        value : Int32 = 1
        CRYSTAL

      context = subject.test(source)
      context.should be_a(SemanticContext)
    end

    it "reports semantic compiler errors" do
      source = Source.new <<-CRYSTAL, "source.cr"
        require "./missing_file"
        CRYSTAL

      subject.catch(source)

      source.should_not be_valid
      source.issues.size.should eq 1
      source.issues.first.rule.should be_a(Semantic)
      source.issues.first.message.should_not be_empty
    end

    it "cannot be disabled inline" do
      source = Source.new <<-CRYSTAL, "source.cr"
        require "./missing_file" # ameba:disable Lint/Semantic
        CRYSTAL

      subject.catch(source)

      source.issues.size.should eq 1
      source.issues.first.enabled?.should be_true
    end
  end
end
