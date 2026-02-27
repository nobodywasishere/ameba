require "json"
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

module Ameba
  class SemanticContext
    getter program : Crystal::Program
    getter node : Crystal::ASTNode
    getter entrypoint : String

    def self.for_entrypoint(entrypoint : String, code : String) : SemanticContext
      Environment.configure!

      source = Crystal::Compiler::Source.new(entrypoint, code)
      result = semantic([source])

      new(result.program, result.node, entrypoint)
    end

    def self.primitive_context(code : String, path = "source.cr") : SemanticContext
      Environment.configure!

      source = Ameba::Source.new(code, path)
      node = source.ast

      dev_null = File.open(File::NULL, "w")

      program = Crystal::Program.new
      program.color = false
      program.wants_doc = false
      program.stdout = dev_null
      program.filename = source.path

      location = Crystal::Location.new(source.path, 1, 1)
      node = Crystal::Expressions.new([
        Crystal::Require.new("prelude").at(location),
        node,
      ] of Crystal::ASTNode)

      node = program.normalize(node)
      root, _ = program.top_level_semantic(node)

      new(program, root, source.path)
    ensure
      dev_null.try &.close
    end

    private def self.semantic(sources : Array(Crystal::Compiler::Source)) : Crystal::Compiler::Result
      compiler = Crystal::Compiler.new
      compiler.no_codegen = true
      compiler.no_cleanup = true
      compiler.color = false
      compiler.wants_doc = false

      dev_null = File.open(File::NULL, "w")
      compiler.stdout = dev_null
      compiler.stderr = dev_null

      compiler.top_level_semantic(sources)
    ensure
      dev_null.try &.close
    end

    def initialize(@program, @node, @entrypoint)
    end
  end
end
