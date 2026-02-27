require "../../../spec_helper"

module Ameba::Rule::Lint
  describe UnknownMethod do
    subject = UnknownMethod.new

    it "reports unknown methods for typed receivers" do
      expect_issue subject, <<-CRYSTAL, semantic: true
        def greet(name : String)
          name.not_a_method
        # ^^^^^^^^^^^^^^^^^ error: Unknown method `not_a_method` for `String`
        end
        CRYSTAL
    end

    it "reports unknown implicit self calls when self type is known" do
      expect_issue subject, <<-CRYSTAL, semantic: true
        class Greeter
          def run
            unknown_call
          # ^^^^^^^^^^^^ error: Unknown method `unknown_call` for `Greeter`
          end
        end
        CRYSTAL
    end

    it "stays silent for untyped receivers" do
      expect_no_issues subject, <<-CRYSTAL, semantic: true
        def greet(name)
          name.not_a_method
        end
        CRYSTAL
    end

    it "does not report macro calls" do
      expect_no_issues subject, <<-CRYSTAL, semantic: true
        macro greet(name)
          {{name}}
        end

        greet("hello")
        CRYSTAL
    end
  end
end
