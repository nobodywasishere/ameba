require "./cmd"

schema = JSON.build(2) do |b|
  b.object do
    b.field("$schema", "http://json-schema.org/draft-07/schema#")
    b.field("title", ".ameba.yml")
    b.field("description", "Configuration rules for the Crystal lang ameba linter")
    b.field("type", "object")
    b.field("additionalProperties", false)

    b.string("properties")
    b.object do
      b.string("Excluded")
      b.object do
        b.field("type", "array")
        b.field("title", "excluded files and paths")
        b.field("description", "an array of wildcards (or paths) to exclude from the source list")

        b.string("items")
        b.object do
          b.field("type", "string")
        end
      end

      b.string("Globs")
      b.object do
        b.field("type", "array")
        b.field("title", "globbed files and paths")
        b.field("description", "an array of wildcards (or paths) to include to the inspection")

        b.string("items")
        b.object do
          b.field("type", "string")
        end
      end

      Ameba::Rule.rules.each do |rule|
        rule.to_json_schema(b)
      end
    end
  end
end

File.write(".ameba.yml.schema.json", schema)
