module Ameba::Rule::Naming
  # A rule that enforces variable, method, parameter, and macro names to not be keywords.
  #
  # For example, these variable, method, parameter, and macro names are considered invalid:
  #
  # ```
  # class ClassName
  #   @@return : String = "world"
  #   @next : Bool = false

  #   getter class : Hash(String, String) = {} of String => String

  #   def require(do : Int32)
  #     1 + 2
  #   end
  #
  #   def abstract : Nil
  #     puts "I'm not abstract"
  #   end
  #
  #   def nil(&do : String -> String)
  #   end
  # end
  # ```
  #
  # YAML configuration example:
  #
  # ```
  # Naming/KeywordNames:
  #   Enabled: true
  #   AllowedNames:
  #    - with
  #    - of
  #    - type
  # ```
  class KeywordNames < Base
    properties do
      description "Enforces that variable and method names are not keywords"
      allowed_names %w()
      severity :warning
    end

    MSG = "%s name should not be a keyword"

    # Pulled from https://crystal-lang.org/reference/1.14/crystal_for_rubyists/index.html#crystal-keywords
    KEYWORDS = %w(
      abstract do if nil? select union
      alias else in of self unless
      as elsif include out sizeof until
      as? end instance_sizeof pointerof struct verbatim
      asm ensure is_a? private super when
      begin enum lib protected then while
      break extend macro require true with
      case false module rescue type yield
      class for next responds_to? typeof
      def fun nil return uninitialized
    )

    def test(source, node : Crystal::Var)
      name = node.name.to_s

      return if name == "self" || !KEYWORDS.includes?(name) || allowed_names.includes?(name)

      issue_for node, MSG % {"Variable"}, prefer_name_location: true
    end

    def test(source, node : Crystal::InstanceVar | Crystal::ClassVar)
      name = node.name.to_s.lstrip('@')

      return if !KEYWORDS.includes?(name) || allowed_names.includes?(name)

      issue_for node, MSG % {"Variable"}, prefer_name_location: true
    end

    def test(source, node : Crystal::Def)
      name = node.name.to_s

      if KEYWORDS.includes?(name) && !allowed_names.includes?(name)
        issue_for node, MSG % {"Method"}, prefer_name_location: true
      end

      node.args.each do |arg|
        name = arg.name

        next if !KEYWORDS.includes?(name) || allowed_names.includes?(name)

        issue_for arg, MSG % {"Parameter"}, prefer_name_location: true
      end

      node.block_arg.try do |block_arg|
        name = block_arg.name

        next if !KEYWORDS.includes?(name) || allowed_names.includes?(name)

        issue_for block_arg, MSG % {"Block parameter"}, prefer_name_location: true
      end
    end

    def test(source, node : Crystal::Macro)
      name = node.name.to_s

      if KEYWORDS.includes?(name) && !allowed_names.includes?(name)
        issue_for node, MSG % {"Macro"}, prefer_name_location: true
      end

      node.args.each do |arg|
        name = arg.name

        next if !KEYWORDS.includes?(name) || allowed_names.includes?(name)

        issue_for arg, MSG % {"Parameter"}, prefer_name_location: true
      end
    end
  end
end
