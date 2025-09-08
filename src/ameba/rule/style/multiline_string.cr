module Ameba::Rule::Style
  # A rule that disallows multi-line strings.
  #
  # YAML configuration example:
  #
  # ```
  # Style/MultilineString:
  #   Enabled: false
  # ```
  class MultilineString < Base
    include AST::Util

    properties do
      since_version "1.7.0"
      description "Disallows multi-line strings"
      enabled false
    end

    MSG = "Use a heredoc for multi-line strings"

    def test(source, node : Crystal::StringLiteral | Crystal::StringInterpolation)
      return unless location = node.location
      return if location.same_line?(node.end_location)

      location_pos = source.pos(location)
      return if source.code[location_pos..(location_pos + 2)]? == "<<-"

      issue_for node, MSG
    end
  end
end
