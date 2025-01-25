module Ameba::Rule::Lint
  class UnknownType < Base
    properties do
      since_version "1.7.0"
      description "Reports unknown types"
      severity :error
    end

    MSG = "Unknown type"

    @[YAML::Field(ignore: true)]
    property! context : SemanticContext?

    def test(source, context : SemanticContext?)
      return unless @context = context

      AST::NodeVisitor.new self, source
    end

    def test(source, node : Crystal::TypeDeclaration)
      return if context.program.lookup_type?(node.declared_type)

      issue_for node.declared_type, MSG
    end

    def test(source, node : Crystal::Arg)
      return if (restriction = node.restriction).nil? || context.program.lookup_type?(restriction)

      issue_for restriction, MSG
    rescue ex
      if restriction
        issue_for restriction, ex.to_s
      else
        issue_for node, ex.to_s
      end
    end
  end
end
