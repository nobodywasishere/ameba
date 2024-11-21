module Ameba::Rule::Typing
  class ClassVarTypeRestriction < Base
    properties do
      description "Recommends that class variables have a type restriction"
      enabled false
    end

    MSG = "Class variables should have a type restriction"

    def test(source, node : Crystal::ClassDef | Crystal::ModuleDef)
      each_cvar_node(node) do |exp|
        case exp
        when Crystal::ClassVar
          issue_for exp, MSG, prefer_name_location: true
        when Crystal::Assign
          case exp.target
          when Crystal::ClassVar
            issue_for exp.target, MSG, prefer_name_location: true
          end
        end
      end
    end

    private def each_cvar_node(node, &)
      case body = node.body
      when Crystal::Assign, Crystal::ClassVar
        yield body
      when Crystal::Expressions
        body.expressions.each do |exp|
          if exp.is_a?(Crystal::Assign) || exp.is_a?(Crystal::ClassVar)
            yield exp
          end
        end
      end
    end
  end
end
