module Ameba::Rule::Lint
  class NoSemanticInformation < Base
    properties do
      since_version "1.7.0"
      description "Reports types that don't have any semantic information available"
      severity :warning
    end

    MSG = "This type doesn't have any semantic information (double check the ameba entrypoints)"

    def test(source, context : SemanticContext?)
      return if context.nil?

      AST::SemanticVisitor.new self, source, context
    end

    def test(
      source,
      node : Crystal::ClassDef | Crystal::ModuleDef |
             Crystal::LibDef | Crystal::EnumDef,
      current_type : Crystal::Type,
    )
      return if current_type.lookup_type?(node.name)

      issue_for node.name, MSG
    end
  end
end
