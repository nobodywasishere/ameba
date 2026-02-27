require "json"

module Ameba::Rule::Lint
  # Reports compiler semantic errors for the configured semantic entrypoint.
  class Semantic < Base
    properties do
      since_version "1.8.0"
      description "Reports invalid Crystal top-level semantics"
      severity :error
    end

    def test(source) : SemanticContext?
      SemanticContext.for_entrypoint(source.path, source.code)
    rescue ex : Crystal::CodeError
      location = error_location(ex, source.path)
      issue_for location, location, error_message(ex)

      nil
    end

    private def error_location(ex : Crystal::CodeError, fallback_filename : String)
      data = JSON.parse(ex.to_json).as_a.first?

      filename =
        data
          .try(&.["file"]?)
          .try(&.as_s?) ||
          fallback_filename

      line_number =
        data
          .try(&.["line"]?)
          .try(&.as_i?) ||
          1

      column_number =
        data
          .try(&.["column"]?)
          .try(&.as_i?) ||
          1

      Crystal::Location.new(
        filename,
        line_number > 0 ? line_number : 1,
        column_number > 0 ? column_number : 1
      )
    rescue
      Crystal::Location.new(fallback_filename, 1, 1)
    end

    private def error_message(ex : Crystal::CodeError) : String
      ex.message.presence ||
        ex.to_s.lines.first?.try(&.strip).presence ||
        ex.class.name
    end
  end
end
