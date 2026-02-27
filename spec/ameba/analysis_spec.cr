require "../spec_helper"

module Ameba
  describe Analysis do
    describe ".parse" do
      it "parses known levels" do
        Analysis.parse("syntax").should eq Analysis::Syntax
        Analysis.parse("primitive_semantic").should eq Analysis::PrimitiveSemantic
        Analysis.parse("top_level_semantic").should eq Analysis::TopLevelSemantic
        Analysis.parse("full_semantic").should eq Analysis::FullSemantic
      end

      it "accepts `semantic` alias for top-level semantic" do
        Analysis.parse("semantic").should eq Analysis::TopLevelSemantic
      end

      it "raises for unknown levels" do
        expect_raises(Exception, "Incorrect analysis name unknown") do
          Analysis.parse("unknown")
        end
      end
    end

    describe "#entrypoint?" do
      it "is true for entrypoint-based levels" do
        Analysis::TopLevelSemantic.entrypoint?.should be_true
        Analysis::FullSemantic.entrypoint?.should be_true
      end

      it "is false for non-entrypoint levels" do
        Analysis::Syntax.entrypoint?.should be_false
        Analysis::PrimitiveSemantic.entrypoint?.should be_false
      end
    end

    describe "#supports?" do
      it "supports same and lower levels" do
        Analysis::TopLevelSemantic.supports?(Analysis::PrimitiveSemantic).should be_true
        Analysis::TopLevelSemantic.supports?(Analysis::TopLevelSemantic).should be_true
      end

      it "does not support higher levels" do
        Analysis::PrimitiveSemantic.supports?(Analysis::TopLevelSemantic).should be_false
      end
    end
  end
end
