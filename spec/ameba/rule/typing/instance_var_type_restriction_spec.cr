require "../../../spec_helper"

module Ameba::Rule::Typing
  subject = InstanceVarTypeRestriction.new
  subject.enabled = true

  it "passes if an instance var has a type restriction" do
    expect_no_issues subject, <<-CRYSTAL
      class Greeter
        @ivar_one : String = "My var"
        @ivar_three : Bool

        def initialize(@ivar_two : Int32)
          @ivar_three = @ivar_two > 10
        end

      end
      CRYSTAL
  end

  it "fails if an instance var at the top level of a class doesn't have a type restriction" do
    expect_issue subject, <<-CRYSTAL
      class Greeter
        @hello = "hello world"
      # ^^^^^^ error: Instance variables should have a type restriction

        @world
      # ^^^^^^ error: Instance variables should have a type restriction

        def initialize(@hello, @world)
        end
      end
      CRYSTAL
  end

  pending "fails if an instance var declared in a method doesn't have a type restriction" do
    expect_issue subject, <<-CRYSTAL
      class Greeter
        def initialize(hello, world)
          @hello = hello
          # ^^^^^ error: Instance variables should have a type restriction

          @world = world
          # ^^^^^ error: Instance variables should have a type restriction
        end
      end
      CRYSTAL
  end
end
