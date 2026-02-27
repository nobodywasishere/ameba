module Ameba
  # Controls which analysis pipeline stages should be executed.
  enum Analysis
    Syntax
    PrimitiveSemantic
    TopLevelSemantic
    FullSemantic

    # Creates analysis mode by name.
    #
    # ```
    # Analysis.parse("syntax")             # => Analysis::Syntax
    # Analysis.parse("primitive-semantic") # => Analysis::PrimitiveSemantic
    # Analysis.parse("semantic")           # => Analysis::TopLevelSemantic
    # ```
    def self.parse(name : String)
      value = name.strip.downcase.gsub('-', '_')

      case value
      when "syntax"
        Syntax
      when "primitive", "primitive_semantic", "primitivesemantic"
        PrimitiveSemantic
      when "top_level", "top_level_semantic", "toplevelsemantic", "semantic"
        TopLevelSemantic
      when "full", "full_semantic", "fullsemantic"
        FullSemantic
      else
        raise "Incorrect analysis name #{name}. Try one of: #{values.join(", ")}"
      end
    end

    # Returns `true` if any semantic pipeline should run.
    def semantic?
      self != Syntax
    end

    # Returns `true` if this analysis level can run rules requiring *required*.
    def supports?(required : Analysis) : Bool
      value >= required.value
    end

    # Returns `true` if the selected analysis requires an entrypoint.
    def entrypoint?
      top_level_semantic? || full_semantic?
    end
  end

  # Converter for `YAML.mapping` which converts analysis level enum to and from YAML.
  class AnalysisYamlConverter
    def self.from_yaml(ctx : YAML::ParseContext, node : YAML::Nodes::Node)
      unless node.is_a?(YAML::Nodes::Scalar)
        raise "Analysis level must be a scalar, not #{node.class}"
      end

      case value = node.value
      when String then Analysis.parse(value)
      when Nil    then raise "Missing analysis level"
      else
        raise "Incorrect analysis level: #{value}"
      end
    end

    def self.to_yaml(value : Analysis, yaml : YAML::Nodes::Builder)
      yaml.scalar value
    end
  end
end
