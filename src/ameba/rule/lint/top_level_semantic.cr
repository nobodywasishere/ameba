module Ameba::Rule::Lint
  class TopLevelSemantic < Base
    properties do
      since_version "1.7.2"
      description "Reports invalid Crystal top-level semantics"
      severity :error
    end

    def test(source, context : SemanticContext?)
      return
    end

    def test(source) : SemanticContext?
      SemanticContext.for_entrypoint([source])
    rescue ex : Crystal::TypeException
      filename = ex.@filename || source.path

      location = Crystal::Location.new(
        filename: filename,
        line_number: ex.line_number || 0,
        column_number: ex.column_number
      )

      issue_for location, location, ex.message.to_s

      nil
    end
  end
end
