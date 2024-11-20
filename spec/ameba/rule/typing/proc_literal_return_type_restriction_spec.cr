require "../../../spec_helper"

module Ameba::Rule::Typing
  subject = ProcReturnTypeRestriction.new

  it "passes if a proc literal has a return type" do
    expect_no_issues subject, <<-CRYSTAL
      my_proc = ->(var : Nil) : Nil { puts var }
      my_proc.call(nil)
      CRYSTAL
  end

  it "failes if a proc literal doesn't have a return type" do
    expect_issue subject, <<-CRYSTAL
      my_proc = ->(var : Nil) { puts var }
              # ^^^^^^^^^^^^^^^^^^^^^^^^^^ error: Proc literals require a return type
      my_proc.call(nil)
      CRYSTAL
  end
end
