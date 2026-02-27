require "../../../spec_helper"

module Ameba::Rule::Lint
  describe NamespaceCollision do
    subject = NamespaceCollision.new

    it "reports ambiguous unqualified paths with multiple visible candidates" do
      expect_issue subject, <<-CRYSTAL, semantic: true
        module JSON
          module Serializable
            module Options
            end
          end
        end

        module Options
        end

        class Foo
          include JSON::Serializable
          include Options
                # ^^^^^^^ error: Namespace collision for `Options`: ambiguous reference (JSON::Serializable::Options (module), Options (module))
        end
        CRYSTAL
    end

    it "does not report fully-qualified references" do
      expect_no_issues subject, <<-CRYSTAL, semantic: true
        module JSON
          module Serializable
            module Options
            end
          end
        end

        module Options
        end

        class Foo
          include JSON::Serializable
          include ::Options
        end
        CRYSTAL
    end

    it "derives collision issue from semantic include failure without context" do
      source = Source.new <<-CRYSTAL, "source.cr"
        class Foo
        end
        CRYSTAL
      source.add_issue(
        Semantic.new,
        {1, 1},
        "JSON::Serializable::Options is not a module, it's a annotation"
      )

      subject.catch(source, nil)

      source.issues.count(&.rule.is_a?(NamespaceCollision)).should eq 1
      issue = source.issues.find!(&.rule.is_a?(NamespaceCollision))
      issue.message.should contain "Namespace collision for `JSON::Serializable::Options`"
      issue.message.should contain "Use `::Options`"
    end

    it "derives collision issue from semantic record/annotation conflict" do
      source = Source.new("record Link, href : String?\n", "source.cr")
      source.add_issue(
        Semantic.new,
        {1, 1},
        "Link is not a struct, it's a annotation"
      )

      subject.catch(source, nil)

      source.issues.count(&.rule.is_a?(NamespaceCollision)).should eq 1
      issue = source.issues.find!(&.rule.is_a?(NamespaceCollision))
      issue.message.should contain "Namespace collision for `Link`"
      issue.message.should contain "expected `struct`, but resolved to `annotation`"
    end
  end
end
