module Ameba::Rule::Lint
  # Reports unknown explicit type restrictions.
  class UnknownType < Base
    properties do
      since_version "1.8.0"
      description "Reports unknown types in explicit type restrictions"
      severity :error
      analysis_level :primitive_semantic
    end

    MSG = "Unknown type"

    def test(source, context : SemanticContext?)
      return unless context

      AST::SemanticVisitor.new(self, source, context)
    end

    def test(source, node : Crystal::TypeDeclaration, semantic : AST::SemanticVisitor)
      validate_type(source, node.declared_type, semantic)
    end

    def test(source, node : Crystal::UninitializedVar, semantic : AST::SemanticVisitor)
      validate_type(source, node.declared_type, semantic)
    end

    def test(source, node : Crystal::Arg, semantic : AST::SemanticVisitor)
      restriction = node.restriction
      return unless restriction

      validate_type(source, restriction, semantic)
    end

    def test(source, node : Crystal::Def, semantic : AST::SemanticVisitor)
      return_type = node.return_type
      return unless return_type

      validate_type(source, return_type, semantic)
    end

    private def validate_type(source, node : Crystal::ASTNode, semantic : AST::SemanticVisitor) : Nil
      return if pseudo_restriction?(node)

      case node
      when Crystal::Path
        issue_for node, MSG unless semantic.resolve_type?(node)
      when Crystal::Union
        node.types.each { |type| validate_type(source, type, semantic) }
      when Crystal::ProcNotation
        node.inputs.try &.each { |input| validate_type(source, input, semantic) }
        node.output.try { |output| validate_type(source, output, semantic) }
      when Crystal::TypeOf
        issue_for node, MSG unless semantic.resolve_type?(node)
      when Crystal::Generic
        validate_type(source, node.name, semantic)
        node.type_vars.each { |type| validate_type(source, type, semantic) }
        node.named_args.try &.each { |arg| validate_type(source, arg.value, semantic) }
      when Crystal::Metaclass
        validate_type(source, node.name, semantic)
      else
        issue_for node, MSG unless semantic.resolve_type?(node)
      end
    end

    private def pseudo_restriction?(node : Crystal::ASTNode) : Bool
      case node
      when Crystal::Underscore, Crystal::Self
        true
      when Crystal::Path
        node.single?("Self") || node.single?("_")
      else
        false
      end
    end
  end
end
