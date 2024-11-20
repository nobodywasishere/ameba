require "../../../spec_helper"

module Ameba
  subject = Rule::Naming::KeywordNames.new

  describe Rule::Naming::KeywordNames do
    it "passes if names aren't keywords" do
      expect_no_issues subject, <<-CRYSTAL
        class Greeting
          @@default_greeting = "Hello world"

          def initialize(@custom_greeting = nil)
          end

          def initialize(int_greeting : Int32)
            @custom_greeting = int_greeting.to_s
          end

          def print_greeting
            greeting = @custom_greeting || @@default_greeting
            puts greeting
          end

          macro hello
            puts "meow meow"
          end
        end
        CRYSTAL
    end

    it "reports variable name" do
      expect_issue subject, <<-CRYSTAL
        begin
          begin : String = "hello world"
        # ^^^^^ error: Variable name should not be a keyword
        end
        CRYSTAL
    end

    it "reports instance variable name" do
      expect_issue subject, <<-CRYSTAL
        class Greeting
          @return : String = "I'll be back"
        # ^^^^^^^ error: Variable name should not be a keyword
        end
        CRYSTAL
    end

    it "reports class variable name" do
      expect_issue subject, <<-CRYSTAL
        class Greeting
          @@return : String = "I'll be back"
        # ^^^^^^^^ error: Variable name should not be a keyword
        end
        CRYSTAL
    end

    it "reports method parameter names with multiple parameters" do
      expect_issue subject, <<-CRYSTAL
        class Location
          def stuff(do : String? = nil, type : String? = nil)
                  # ^ error: Parameter name should not be a keyword
                                      # ^ error: Parameter name should not be a keyword
          end
        end
        CRYSTAL
    end

    it "reports method parameter names with multiple instance variables" do
      expect_issue subject, <<-CRYSTAL
        class Location
          def at(@begin = nil, @end = nil)
               # ^ error: Variable name should not be a keyword
                             # ^ error: Variable name should not be a keyword
          end
        end
        CRYSTAL
    end

    it "reports block parameter name" do
      expect_issue subject, <<-CRYSTAL
        class Location
          def at(&do : String -> String)
                # ^ error: Block parameter name should not be a keyword
          end
        end
        CRYSTAL
    end

    pending "reports macro name" do
      expect_issue subject, <<-CRYSTAL
        class Location
          macro do
              # ^ error: Macro name should not be a keyword
          end
        end
        CRYSTAL
    end

    pending "reports macro parameter name" do
      expect_issue subject, <<-CRYSTAL
        class Location
          macro hello(do)
                    # ^ error: Parameter should not be a keyword
          end
        end
        CRYSTAL
    end
  end
end
