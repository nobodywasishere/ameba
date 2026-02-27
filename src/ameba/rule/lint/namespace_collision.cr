module Ameba::Rule::Lint
  # Reports ambiguous path references where multiple visible constants can match
  # the same path name.
  class NamespaceCollision < Base
    private record Candidate, full_name : String, kind : String

    properties do
      since_version "1.8.0"
      description "Reports ambiguous path references and namespace collisions"
      severity :error
      analysis_level :top_level_semantic
    end

    MSG                        = "Namespace collision for `%s`: ambiguous reference (%s)"
    SEMANTIC_MSG               = "Namespace collision for `%s`: expected `%s`, but resolved to `%s`"
    SEMANTIC_COLLISION_PATTERN = /^(.+?) is not a ([^,]+), it's a ([^,]+)$/

    def test(source, context : SemanticContext?)
      if context
        AST::SemanticVisitor.new(self, source, context)
      else
        infer_from_semantic_error(source)
      end
    end

    def test(source, node : Crystal::Path, semantic : AST::SemanticVisitor)
      return if node.global?

      candidates = candidates_for(node, semantic)
      return unless candidates.size > 1

      issue_for node, MSG % {path_to_s(node), candidates_to_s(candidates)}
    end

    private def infer_from_semantic_error(source : Source) : Nil
      source.issues.each do |issue|
        next unless issue.rule.is_a?(Semantic)
        next unless match = issue.message.match(SEMANTIC_COLLISION_PATTERN)

        full_name = match[1]
        expected = match[2]
        actual = match[3]
        message = semantic_collision_message(full_name, expected, actual)
        next if duplicate_issue?(source, message, issue.location)

        source.add_issue(self, issue.location, issue.end_location, message)
      end
    end

    private def candidates_for(node : Crystal::Path, semantic : AST::SemanticVisitor) : Array(Candidate)
      names = node.names
      return [] of Candidate if names.empty?

      roots = [] of Crystal::Type
      seen = Set(String).new
      root_name = names.first

      scope_chain(semantic.current_type).each do |scope|
        append_lookup(scope.lookup_name(root_name), roots, seen)

        scope.parents.try &.each do |parent|
          append_lookup(parent.lookup_name(root_name), roots, seen)
        end
      end

      if names.size == 1
        append_lookup(semantic.resolve_type?(node), roots, seen)
      end

      if global_root = semantic.resolve_type?(Crystal::Path.global([root_name]))
        append_lookup(global_root, roots, seen)
      end

      roots
        .compact_map { |root| resolve_nested(root, names[1..-1]) }
        .map { |type| candidate_for(type) }
        .uniq!
    end

    private def scope_chain(type : Crystal::Type) : Array(Crystal::Type)
      chain = [] of Crystal::Type
      current = type

      loop do
        chain << current

        case current
        when Crystal::Program
          break
        when Crystal::NamedType
          current = current.namespace
        else
          break
        end
      end

      unless chain.any?(Crystal::Program)
        chain << type.program
      end

      chain
    end

    private def append_lookup(type : Crystal::Type?, list : Array(Crystal::Type), seen : Set(String)) : Nil
      return unless type

      key = type_key(type)
      return if seen.includes?(key)

      seen << key
      list << type
    end

    private def resolve_nested(root : Crystal::Type, names : Array(String)) : Crystal::Type?
      current : Crystal::Type? = root

      names.each do |name|
        current = current.try(&.lookup_name(name))
        return unless current
      end

      current
    end

    private def candidate_for(type : Crystal::Type) : Candidate
      Candidate.new(type_name(type), type.type_desc)
    end

    private def type_name(type : Crystal::Type) : String
      case type
      when Crystal::NamedType
        type.full_name
      else
        type.to_s
      end
    end

    private def type_key(type : Crystal::Type) : String
      "#{type.class}:#{type_name(type)}"
    end

    private def path_to_s(path : Crystal::Path) : String
      (path.global? ? "::" : "") + path.names.join("::")
    end

    private def candidates_to_s(candidates : Array(Candidate)) : String
      candidates
        .sort_by(&.full_name)
        .map { |candidate| "#{candidate.full_name} (#{candidate.kind})" }
        .join(", ")
    end

    private def semantic_collision_message(full_name : String, expected : String, actual : String) : String
      msg = SEMANTIC_MSG % {full_name, expected, actual}

      if expected == "module" && actual == "annotation"
        leaf = full_name.split("::").last?
        if leaf
          msg += ". Use `::#{leaf}` to reference the top-level constant."
        end
      end

      msg
    end

    private def duplicate_issue?(source : Source, message : String, location : Crystal::Location?) : Bool
      source.issues.any? do |issue|
        issue.rule.is_a?(NamespaceCollision) &&
          issue.message == message &&
          issue.location == location
      end
    end
  end
end
