module Ameba::Rule::Lint
  # Reports calls to methods that can't be found on confidently inferred
  # receiver types.
  class UnknownMethod < Base
    properties do
      since_version "1.8.0"
      description "Reports unknown methods on explicitly inferred receiver types"
      severity :error
      analysis_level :primitive_semantic
    end

    MSG = "Unknown method `%s` for `%s`"

    def test(source, context : SemanticContext?)
      return unless context

      AST::SemanticVisitor.new(self, source, context)
    end

    def test(source, node : Crystal::Call, semantic : AST::SemanticVisitor)
      return if semantic.macro_call?(node)
      return unless receiver_type = receiver_type_for(node, semantic)

      methods = semantic.lookup_methods(receiver_type, node.name)
      if methods.empty?
        issue_for node, MSG % {node.name, receiver_type}
        return
      end

      # A method with this name exists, but the call may still be invalid due to
      # argument shape. This rule intentionally stays silent in this case.
      return unless semantic.matching_methods(receiver_type, node).empty?
    end

    private def receiver_type_for(node : Crystal::Call, semantic : AST::SemanticVisitor) : Crystal::Type?
      if obj = node.obj
        semantic.infer_expr_type?(obj)
      else
        semantic.self_type
      end
    end
  end
end
