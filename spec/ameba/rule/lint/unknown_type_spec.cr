require "../../../spec_helper"

module Ameba::Rule::Lint
  describe UnknownType do
    subject = UnknownType.new

    it "passes for known restrictions in declarations and signatures" do
      expect_no_issues subject, <<-CRYSTAL, semantic: true
        value : Int32 = 1

        def greet(name : String) : String
          name
        end

        callback : String -> Int32
        callback = ->(name : String) { name.size }
        CRYSTAL
    end

    it "reports unknown types in declarations, args, returns, and proc notation" do
      expect_issue subject, <<-CRYSTAL, semantic: true
        value : UnknownInt = 1
              # ^^^^^^^^^^ error: Unknown type

        def greet(name : UserName)
                       # ^^^^^^^^ error: Unknown type
          name.to_s
        end

        def fetch : MissingReturn
                  # ^^^^^^^^^^^^^ error: Unknown type
          1
        end

        callback : String -> MissingProcType
                           # ^^^^^^^^^^^^^^^ error: Unknown type
        CRYSTAL
    end

    it "allows pseudo restrictions" do
      expect_no_issues subject, <<-CRYSTAL, semantic: true
        class User
          def passthrough(value : _)
            value
          end

          def itself : Self
            self
          end
        end
        CRYSTAL
    end

    it "is silent without semantic context" do
      expect_no_issues subject, <<-CRYSTAL
        value : UnknownInt = 1
        CRYSTAL
    end
  end
end
