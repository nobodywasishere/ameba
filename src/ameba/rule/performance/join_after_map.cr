require "./base"

module Ameba::Rule::Performance
  # This rule identifies `join` calls that follow `map` and allocate an
  # intermediate collection.
  #
  # For example, this is considered inefficient:
  #
  # ```
  # %w[Alice Bob].map(&.upcase).join(", ")
  # ```
  #
  # And can be written as this:
  #
  # ```
  # %w[Alice Bob].join(", ", &.upcase)
  # ```
  #
  # YAML configuration example:
  #
  # ```
  # Performance/JoinAfterMap:
  #   Enabled: true
  # ```
  class JoinAfterMap < Base
    include AST::Util

    properties do
      since_version "1.8.0"
      description "Identifies usage of `join` calls that follow `map`"
    end

    MSG = "Use `join {...}` instead of `map {...}.join`"

    def test(source)
      AST::NodeVisitor.new(self, source, skip: :macro)
    end

    def test(source, node : Crystal::Call)
      return unless node.name == "join"
      return if has_block?(node)
      return unless (map = node.obj).is_a?(Crystal::Call)
      return unless map.name == "map" && has_block?(map)
      return if has_arguments?(map)
      return unless correctable_join?(node)

      return unless location = name_location(map)
      return unless map_name_end = name_end_location(map)
      return unless end_location = node.end_location

      issue_for(location, end_location, MSG) do |corrector|
        correct(source, node, map, corrector, location, map_name_end, end_location)
      end
    end

    private def correct(source, node, map, corrector, location, map_name_end, end_location)
      unless has_arguments?(node)
        corrector.replace(location, map_name_end, "join")
        corrector.remove_trailing(node, {{ ".join".size }})
        return
      end

      return unless argument_code = argument_source(source, node)
      return unless map_end = map.end_location

      corrector.replace(location, map_name_end, "join")
      corrector.remove(map_end.adjust(column_number: 1), end_location)

      case
      when block_arg = map.block_arg
        return unless block_arg_location = block_arg.location

        corrector.insert_before(
          block_arg_location.adjust(column_number: -1),
          "#{argument_code}, "
        )
      when block = map.block
        correct_block(corrector, block, map_name_end, argument_code)
      end
    end

    private def correct_block(corrector, block, map_name_end, argument_code)
      case
      when block.end_location
        corrector.insert_after(map_name_end, "(#{argument_code})")
      when block_location = block.location
        corrector.insert_before(block_location, "#{argument_code}, ")
      end
    end

    private def correctable_join?(node)
      args = node.args
      named_args = node.named_args

      return true if args.empty? && (named_args.nil? || named_args.empty?)
      return separator_literal?(args.first) if args.size == 1 && (named_args.nil? || named_args.empty?)

      args.empty? && named_args.try(&.size.== 1) && named_args.try(&.first.name.== "separator")
    end

    private def separator_literal?(node)
      node.is_a?(Crystal::NilLiteral | Crystal::BoolLiteral | Crystal::NumberLiteral |
                 Crystal::CharLiteral | Crystal::StringLiteral | Crystal::StringInterpolation |
                 Crystal::SymbolLiteral)
    end

    private def argument_source(source, node)
      case
      when argument = node.args.first?
        node_source(argument, source.lines)
      when named_argument = node.named_args.try(&.first?)
        value = node_source(named_argument.value, source.lines)
        "#{named_argument.name}: #{value}" if value
      end
    end
  end
end
