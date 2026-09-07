require "../../../spec_helper"

module Ameba::Rule::Performance
  describe JoinAfterMap do
    subject = JoinAfterMap.new

    it "passes if there is no potential performance improvement" do
      expect_no_issues subject, <<-CRYSTAL
        %w[Alice Bob].join(&.upcase)
        %w[Alice Bob].map.join
        %w[Alice Bob].map(1, &.upcase).join
        %w[Alice Bob].map(&.upcase).join(&.itself)
        CRYSTAL
    end

    it "passes for ambiguous and IO join arguments" do
      expect_no_issues subject, <<-CRYSTAL
        %w[Alice Bob].map(&.upcase).join(separator)
        %w[Alice Bob].map(&.upcase).join(STDOUT)
        %w[Alice Bob].map(&.upcase).join(STDOUT, ", ")
        CRYSTAL
    end

    it "reports and autocorrects join without a separator" do
      source = expect_issue subject, <<-CRYSTAL
        %w[Alice Bob].map(&.upcase).join
                    # ^^^^^^^^^^^^^^^^^^ error: Use `join {...}` instead of `map {...}.join`
        %w[Alice Bob].map { |name| name.upcase }.join
                    # ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^ error: Use `join {...}` instead of `map {...}.join`
        CRYSTAL

      expect_correction source, <<-CRYSTAL
        %w[Alice Bob].join(&.upcase)
        %w[Alice Bob].join { |name| name.upcase }
        CRYSTAL
    end

    it "reports and autocorrects literal separators" do
      source = expect_issue subject, <<-CRYSTAL
        %w[Alice Bob].map(&.upcase).join(", ")
                    # ^^^^^^^^^^^^^^^^^^^^^^^^ error: Use `join {...}` instead of `map {...}.join`
        %w[Alice Bob].map { |name| name.upcase }.join('-')
                    # ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^ error: Use `join {...}` instead of `map {...}.join`
        %w[Alice Bob].map(&block).join("/")
                    # ^^^^^^^^^^^^^^^^^^^^^ error: Use `join {...}` instead of `map {...}.join`
        CRYSTAL

      expect_correction source, <<-CRYSTAL
        %w[Alice Bob].join(", ", &.upcase)
        %w[Alice Bob].join('-') { |name| name.upcase }
        %w[Alice Bob].join("/", &block)
        CRYSTAL
    end

    it "reports and autocorrects a named separator" do
      source = expect_issue subject, <<-CRYSTAL
        %w[Alice Bob].map(&.upcase).join(separator: separator)
                    # ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^ error: Use `join {...}` instead of `map {...}.join`
        CRYSTAL

      expect_correction source, <<-CRYSTAL
        %w[Alice Bob].join(separator: separator, &.upcase)
        CRYSTAL
    end

    it "autocorrects a multi-line block" do
      source = expect_issue subject, <<-CRYSTAL
        %w[Alice Bob].map do |name|
                    # ^^^^^^^^^^^^^ error: Use `join {...}` instead of `map {...}.join`
          name.upcase
        end.join(", ")
        CRYSTAL

      expect_correction source, <<-CRYSTAL
        %w[Alice Bob].join(", ") do |name|
          name.upcase
        end
        CRYSTAL
    end

    context "macro" do
      it "doesn't report in macro scope" do
        expect_no_issues subject, <<-CRYSTAL
          {{ %w[Alice Bob].map(&.upcase).join }}
          CRYSTAL
      end
    end
  end
end
