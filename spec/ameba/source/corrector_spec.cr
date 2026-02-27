require "../../spec_helper"

class Ameba::Source
  describe Corrector do
    it "returns rewrite edits" do
      corrector = Corrector.new("puts(:hello, :world)")
      corrector.replace(5...11, ":hi")
      corrector.insert_before(13...19, "42, ")

      corrector.edits.should eq([
        Rewriter::Edit.new(5, 11, ":hi"),
        Rewriter::Edit.new(13, 13, "42, "),
      ])
    end
  end
end
