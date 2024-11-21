module Ameba::Rule::Typing
  # A rule that disallows local variables without a type declaration.
  #
  # For example, this is considered valid:
  #
  # ```
  # test : String = "hello"
  # hello : Proc(String, String) = ->(a : String) { a + "!" }
  # ```
  #
  # And these are considered invalid:
  #
  # ```
  # a, b = 1, 2
  #
  # test = "hello"
  #
  # hello = ->(a : String) { a + "!" }
  # ```
  #
  # YAML configuration example:
  #
  # ```
  # Typing/LocalVarTypeRestriction:
  #   Enabled: true
  # ```
  class LocalVarTypeRestriction < Base
    properties do
      description "Recommends that local variables have a type restriction"
      enabled false
    end

    MSG = "Local variables should have a type restriction"

    def test(source)
      AST::ScopeVisitor.new self, source
    end

    def test(source, node, scope : AST::Scope)
      return if scope.lib_def?(check_outer_scopes: true)

      scope.variables.each do |var|
        case var.assign_before_reference
        when Crystal::Assign, Crystal::MultiAssign
          issue_for var.node, MSG, prefer_name_location: true
        end
      end
    end
  end
end
