require "../../../spec_helper"

module Ameba::Rule::Style
  describe MultilineString do
    subject = MultilineString.new

    it "doesn't report if a string is on a single line" do
      expect_no_issues subject, <<-CRYSTAL
        "bar"
        CRYSTAL
    end

    it "doesn't report heredocs" do
      expect_no_issues subject, <<-CRYSTAL
        <<-FOO
          bar
          FOO
        CRYSTAL
    end

    it "reports if there is a multi-line string" do
      expect_issue subject, <<-CRYSTAL
        "
        # ^{} error: Use a heredoc for multi-line strings
          bar
        "
        CRYSTAL
    end
  end
end
