require "llvm/lib_llvm"
require "compiler/crystal/annotatable"
require "compiler/crystal/tools/dependencies"
require "compiler/crystal/compiler"
require "compiler/crystal/config"
require "compiler/crystal/crystal_path"
require "compiler/crystal/error"
require "compiler/crystal/exception"
require "compiler/crystal/formatter"
require "compiler/crystal/loader"
require "compiler/crystal/macros"
require "compiler/crystal/program"
require "compiler/crystal/progress_tracker"
require "compiler/crystal/semantic"
require "compiler/crystal/syntax"
require "compiler/crystal/types"
require "compiler/crystal/syntax/**"
require "compiler/crystal/semantic/**"
require "compiler/crystal/macros/**"
require "compiler/crystal/codegen/**"

module Ameba::Rule::Lint
  class UnknownType < Base
    properties do
      since_version "1.7.0"
      description "Reports unknown types"
      severity :error
    end

    MSG = "Unknown type"

    @[YAML::Field(ignore: true)]
    getter! semantic : Crystal::Compiler::Result

    def test(source)
      node = source.ast
      program = Crystal::Program.new
      program.color = false
      node = program.normalize node

      root, _ = program.top_level_semantic(node)
      @semantic = Crystal::Compiler::Result.new(program, root)

      AST::NodeVisitor.new self, source
    end

    def test(source, node : Crystal::TypeDeclaration)
      return if semantic.program.lookup_type?(node.declared_type)

      issue_for node.declared_type, MSG
    end

    def test(source, node : Crystal::Arg)
      return if (restriction = node.restriction).nil? || semantic.program.lookup_type?(restriction)

      issue_for restriction, MSG
    end
  end
end
