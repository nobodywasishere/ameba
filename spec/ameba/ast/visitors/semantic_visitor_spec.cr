require "../../../spec_helper"

module Ameba
  class SemanticProbeRule < Rule::Base
    @[YAML::Field(ignore: true)]
    getter call_contexts = [] of NamedTuple(
      name: String,
      current_type: String,
      self_type: String?,
      in_def: Bool,
      in_macro: Bool,
      typed_name: String?,
      macro_call: Bool,
    )

    properties do
      description "Internal rule to test semantic visitor behavior"
    end

    def test(source, context : SemanticContext?)
      return unless context

      AST::SemanticVisitor.new(self, source, context)
    end

    def test(source, node : Crystal::Call, semantic : AST::SemanticVisitor)
      call_contexts << {
        name:         node.name,
        current_type: semantic.current_type.to_s,
        self_type:    semantic.self_type.try(&.to_s),
        in_def:       semantic.in_def?,
        in_macro:     semantic.in_macro?,
        typed_name:   semantic.typed_local?("name").try(&.to_s),
        macro_call:   semantic.macro_call?(node),
      }
    end
  end
end

module Ameba::AST
  describe SemanticVisitor do
    it "tracks type/self scope through nested module/class/def" do
      source = Source.new <<-CRYSTAL, "source.cr"
        module Outer
          class Inner
            def run(name : String)
              name.upcase
            end
          end
        end
        CRYSTAL
      context = SemanticContext.primitive_context(source.code)
      rule = Ameba::SemanticProbeRule.new

      rule.catch(source, context)

      upcase = rule.call_contexts.find!(&.[:name].==("upcase"))
      upcase[:current_type].should contain "Outer::Inner"
      upcase_self_type = upcase[:self_type].should_not be_nil
      upcase_self_type.should contain "Outer::Inner"
      upcase[:in_def].should be_true
      upcase[:in_macro].should be_false
    end

    it "keeps typed locals available inside nested blocks" do
      source = Source.new <<-CRYSTAL, "source.cr"
        def run(name : String)
          [1].each do |n|
            name.upcase
          end
        end
        CRYSTAL
      context = SemanticContext.primitive_context(source.code)
      rule = Ameba::SemanticProbeRule.new

      rule.catch(source, context)

      upcase = rule.call_contexts.find!(&.[:name].==("upcase"))
      upcase[:typed_name].should eq "String"
    end

    it "does not raise when type resolution is unavailable" do
      source = Source.new <<-CRYSTAL, "source.cr"
        def run(name : MissingType)
          name
        end
        CRYSTAL
      context = SemanticContext.new(Crystal::Program.new, source.ast, source.path)
      rule = Ameba::SemanticProbeRule.new

      rule.catch(source, context)
      source.issues.should be_empty
    end

    it "distinguishes macro calls from method calls" do
      source = Source.new <<-CRYSTAL, "source.cr"
        macro greet(name)
          {{name}}
        end

        def speak
        end

        greet("hi")
        speak
        CRYSTAL
      context = SemanticContext.primitive_context(source.code)
      rule = Ameba::SemanticProbeRule.new

      rule.catch(source, context)

      greet = rule.call_contexts.find!(&.[:name].==("greet"))
      speak = rule.call_contexts.find!(&.[:name].==("speak"))

      greet[:macro_call].should be_true
      speak[:macro_call].should be_false
    end
  end
end
