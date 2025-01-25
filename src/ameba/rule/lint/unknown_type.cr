module Ameba::Rule::Lint
  class UnknownType < Base
    properties do
      since_version "1.7.0"
      description "Reports unknown types"
      severity :error
    end

    MSG = "Unknown type"

    def test(source, context : SemanticContext?)
      return if context.nil?

      AST::SemanticVisitor.new self, source, context
    end

    def test(source, node : Crystal::TypeDeclaration, current_type : Crystal::Type)
      return if current_type.lookup_type?(node.declared_type)

      validate_type(source, node.declared_type, current_type)
    end

    def test(source, node : Crystal::Arg, current_type : Crystal::Type)
      return if (restriction = node.restriction).nil?

      validate_type(source, restriction, current_type)
    end

    private def validate_type(source, node : Crystal::ASTNode, current_type : Crystal::Type) : Nil
      case node
      when Crystal::Path
        return if current_type.lookup_type?(node)

        issue_for node, MSG
      when Crystal::Union
        node.types.each do |type|
          validate_type(source, type, current_type)
        end
      when Crystal::ProcNotation
        node.inputs.try &.each { |i| validate_type(source, i, current_type) }
        node.output.try { |i| validate_type(source, i, current_type) }
      when Crystal::TypeOf
        node.expressions.each do |type|
          validate_type(source, type, current_type)
        end
      when Crystal::Generic
        validate_type(source, node.name, current_type)

        node.type_vars.each do |type|
          validate_type(source, type, current_type)
        end

        node.named_args.try &.each do |arg|
          validate_type(source, arg.value, current_type)
        end
      when Crystal::Underscore, Crystal::Self
        # Okay
      else
        issue_for node, "TODO: #{node.class}"
      end
    end
  end
end
