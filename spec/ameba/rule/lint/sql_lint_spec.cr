require "../../../spec_helper"

module Ameba::Rule::Lint
  describe SQLLint do
    subject = SQLLint.new

    it "fails if a SQL query selects via star" do
      expect_issue subject, <<-CRYSTAL


            <<-SQL
              SELECT * FROM users;
            # ^^^^^^^^^^^^^^^^^^^ error: [AM04] ambiguous.column_count: Query produces an unknown number of result columns.
              SQL
        CRYSTAL
    end

    it "supports using $ replacements" do
      expect_no_issues subject, <<-CRYSTAL


            <<-SQL
              SELECT age FROM users
              WHERE name = $1;
              SQL
        CRYSTAL
    end
  end
end
