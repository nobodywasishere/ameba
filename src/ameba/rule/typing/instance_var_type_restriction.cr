module Ameba::Rule::Typing
  class InstanceVarTypeRestriction < Base
    properties do
      description "Recommends that instance variables have a type restriction"
      enabled true
    end

    MSG = "Instance variables should have a type restriction"

    def test(source, node : Crystal::ClassDef | Crystal::ModuleDef)
      each_ivar_node(node) do |exp|
        case exp
        when Crystal::InstanceVar
          issue_for exp, MSG, prefer_name_location: true
        when Crystal::Assign
          case exp.target
          when Crystal::InstanceVar
            issue_for exp.target, MSG, prefer_name_location: true
          end
        end
      end
    end

    private def each_ivar_node(node, &)
      case body = node.body
      when Crystal::Assign, Crystal::InstanceVar
        yield body
      when Crystal::Expressions
        body.expressions.each do |exp|
          if exp.is_a?(Crystal::Assign) || exp.is_a?(Crystal::InstanceVar)
            yield exp
          end
        end
      end
    end
  end
end
