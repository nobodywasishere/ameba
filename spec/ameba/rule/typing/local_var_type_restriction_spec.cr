require "../../../spec_helper"

module Ameba::Rule::Typing
  subject = LocalVarTypeRestriction.new

  it "passes if a local variable has a type restriction" do
    expect_no_issues subject, <<-CRYSTAL
      hello : String = "hello world"

      puts hello

      def my_method(_msg)
        msg : Array(String) = _msg.split(".")
      end
      CRYSTAL
  end

  it "fails if a local variable doesn't have a type restriction" do
    expect_issue subject, <<-CRYSTAL
        hello = "hello world"
      # ^^^^^ error: Local variables should have a type restriction
      my_proc.call(nil)
      hello = "hello world"

      puts hello

      def my_method(_msg)
        msg = _msg.split(".")
      # ^^^ error: Local variables should have a type restriction
      end
      CRYSTAL
  end

  it "fails for mulit-assign variables" do
    expect_issue subject, <<-CRYSTAL
        hello, world = "hello", "world"
      # ^^^^^ error: Local variables should have a type restriction
             # ^^^^^ error: Local variables should have a type restriction
      CRYSTAL
  end

  it "pass for mulit-assign variables where they're already assigned" do
    expect_no_issues subject, <<-CRYSTAL
      hello : String = "1"
      world : String = "2"

        hello, world = "hello", "world"
      CRYSTAL
  end
end
