require "./base_visitor"

module Ameba::AST
  # Traverses parser AST while keeping semantic scope state that can be used by
  # semantic rules.
  class SemanticVisitor < BaseVisitor
    NUMBER_TYPE_NAMES = {
      Crystal::NumberKind::I8   => "Int8",
      Crystal::NumberKind::I16  => "Int16",
      Crystal::NumberKind::I32  => "Int32",
      Crystal::NumberKind::I64  => "Int64",
      Crystal::NumberKind::I128 => "Int128",
      Crystal::NumberKind::U8   => "UInt8",
      Crystal::NumberKind::U16  => "UInt16",
      Crystal::NumberKind::U32  => "UInt32",
      Crystal::NumberKind::U64  => "UInt64",
      Crystal::NumberKind::U128 => "UInt128",
      Crystal::NumberKind::F32  => "Float32",
      Crystal::NumberKind::F64  => "Float64",
    }

    private class Frame
      property current_type : Crystal::Type
      property self_type : Crystal::Type?
      property? in_def : Bool
      property? in_macro : Bool
      getter typed_locals : Hash(String, Crystal::Type)

      def initialize(
        @current_type : Crystal::Type,
        @self_type : Crystal::Type?,
        @in_def : Bool,
        @in_macro : Bool,
        @typed_locals : Hash(String, Crystal::Type),
      )
      end
    end

    getter context : SemanticContext
    getter current_type : Crystal::Type
    getter self_type : Crystal::Type?

    def initialize(@rule, @source, @context : SemanticContext)
      root = @context.program
      @current_type = root
      @self_type = root
      @frames = [Frame.new(
        current_type: root,
        self_type: root,
        in_def: false,
        in_macro: false,
        typed_locals: {} of String => Crystal::Type,
      )]
      super(@rule, @source)
    end

    def in_def? : Bool
      current_frame.in_def?
    end

    def in_macro? : Bool
      current_frame.in_macro?
    end

    # Returns typed local variable type if known in current frame.
    def typed_local?(name : String) : Crystal::Type?
      current_frame.typed_locals[name]?
    end

    # Returns typed local map for current frame.
    def typed_locals : Hash(String, Crystal::Type)
      current_frame.typed_locals
    end

    # Resolves type grammar AST node in current semantic scope.
    def resolve_type?(node : Crystal::ASTNode?) : Crystal::Type?
      return unless node

      current_type.lookup_type?(node, self_type_for_lookup)
    rescue
      nil
    end

    # Returns semantic type for expression when it can be inferred with high
    # confidence.
    def infer_expr_type?(expr : Crystal::ASTNode?) : Crystal::Type?
      return unless expr

      expr.type? || infer_expr_type_fallback(expr)
    rescue
      nil
    end

    # Looks up method definitions on *type*.
    def lookup_methods(type : Crystal::Type, call_name : String) : Array(Crystal::Def)
      type.lookup_defs(call_name)
    rescue
      [] of Crystal::Def
    end

    # Returns method candidates for *call* that match simple arity/name checks.
    def matching_methods(type : Crystal::Type, call : Crystal::Call) : Array(Crystal::Def)
      lookup_methods(type, call.name).select do |a_def|
        method_matches_call?(a_def, call)
      end
    end

    # Returns `true` when *call* resolves as a macro invocation in current
    # scope.
    def macro_call?(call : Crystal::Call) : Bool
      scope = macro_scope_for(call)
      return false unless scope

      scope.lookup_macro(call.name, call.args, call.named_args).is_a?(Crystal::Macro)
    rescue
      false
    end

    def visit(node : Crystal::ClassDef | Crystal::ModuleDef | Crystal::LibDef | Crystal::EnumDef | Crystal::AnnotationDef)
      inspect(node)

      if type = resolve_type?(node.name)
        push_frame(current_type: type, self_type: type.instance_type, inherit_locals: false) do
          node.accept_children(self)
        end
        false
      else
        true
      end
    end

    def visit(node : Crystal::Def)
      inspect(node)

      def_self_type = resolve_def_self_type(node)
      push_frame(
        current_type: current_type,
        self_type: def_self_type,
        in_def: true,
        in_macro: in_macro? || node.macro_def?,
        inherit_locals: false,
      ) do
        remember_arg_types(node.args)
        remember_arg_type(node.block_arg)
        remember_arg_type(node.double_splat)
        node.accept_children(self)
      end

      false
    end

    def visit(node : Crystal::Macro)
      inspect(node)

      push_frame(
        current_type: current_type,
        self_type: self_type,
        in_def: false,
        in_macro: true,
        inherit_locals: false,
      ) do
        node.accept_children(self)
      end

      false
    end

    def visit(node : Crystal::ProcLiteral)
      inspect(node)

      push_frame(
        current_type: current_type,
        self_type: self_type,
        in_def: true,
        in_macro: in_macro?,
        inherit_locals: true,
      ) do
        node.accept_children(self)
      end

      false
    end

    def visit(node : Crystal::Block)
      inspect(node)

      push_frame(
        current_type: current_type,
        self_type: self_type,
        in_def: in_def?,
        in_macro: in_macro?,
        inherit_locals: true,
      ) do
        node.accept_children(self)
      end

      false
    end

    def visit(node : Crystal::TypeDeclaration)
      inspect(node)
      remember_local_type(node.var, node.declared_type)
      true
    end

    def visit(node : Crystal::UninitializedVar)
      inspect(node)
      remember_local_type(node.var, node.declared_type)
      true
    end

    def visit(node : Crystal::Arg)
      inspect(node)
      remember_arg_type(node)
      true
    end

    def visit(node : Crystal::Assign)
      inspect(node)
      true
    end

    def visit(node : Crystal::ASTNode) : Bool
      inspect(node)
      true
    end

    private def inspect(node : Crystal::ASTNode) : Nil
      @rule.test(@source, node, self)
    end

    private def infer_expr_type_fallback(expr : Crystal::ASTNode) : Crystal::Type?
      if type = basic_literal_type(expr)
        return type
      end

      case expr
      when Crystal::Var
        expr.name == "self" ? self_type_for_lookup : typed_local?(expr.name)
      when Crystal::Path
        resolve_type?(expr).try &.metaclass
      when Crystal::ArrayLiteral
        expr.name.try { |name| resolve_type?(name) } || builtin_type("Array")
      when Crystal::HashLiteral
        expr.name.try { |name| resolve_type?(name) } || builtin_type("Hash")
      when Crystal::Cast, Crystal::NilableCast
        resolve_type?(expr.to)
      when Crystal::Call
        infer_call_type(expr)
      end
    end

    private def basic_literal_type(expr : Crystal::ASTNode) : Crystal::Type?
      case expr
      when Crystal::NilLiteral
        builtin_type("Nil")
      when Crystal::BoolLiteral
        builtin_type("Bool")
      when Crystal::CharLiteral
        builtin_type("Char")
      when Crystal::StringLiteral, Crystal::StringInterpolation
        builtin_type("String")
      when Crystal::SymbolLiteral
        builtin_type("Symbol")
      when Crystal::RegexLiteral
        builtin_type("Regex")
      when Crystal::NumberLiteral
        number_type(expr.kind)
      end
    end

    private def infer_call_type(call : Crystal::Call) : Crystal::Type?
      receiver_type = receiver_type_for(call)
      return unless receiver_type

      methods = matching_methods(receiver_type, call)
      return unless methods.size == 1

      return_type = methods.first.return_type
      resolve_type?(return_type)
    end

    private def receiver_type_for(call : Crystal::Call) : Crystal::Type?
      if obj = call.obj
        infer_expr_type?(obj)
      else
        self_type_for_lookup
      end
    end

    private def method_matches_call?(a_def : Crystal::Def, call : Crystal::Call) : Bool
      named_arg_names = call.named_args.try(&.map(&.name).to_set) || Set(String).new
      available_args = a_def.args.reject { |arg| named_arg_names.includes?(arg.external_name) }

      required_positional = available_args.count(&.default_value.nil?)
      max_positional = a_def.splat_index ? Int32::MAX : available_args.size
      positional_count = call.args.size

      return false if positional_count < required_positional || positional_count > max_positional

      if named_args = call.named_args
        accepted = a_def.args.map(&.external_name).to_set
        named_args.each do |arg|
          next if accepted.includes?(arg.name)
          return false unless a_def.double_splat
        end
      end

      true
    end

    private def macro_scope_for(call : Crystal::Call) : Crystal::Type?
      if obj = call.obj
        case obj
        when Crystal::Path
          resolve_type?(obj) || infer_expr_type?(obj)
        else
          infer_expr_type?(obj)
        end
      else
        current_type
      end
    end

    private def resolve_def_self_type(node : Crystal::Def) : Crystal::Type?
      if receiver = node.receiver
        resolve_type?(receiver)
      else
        current_type.instance_type
      end
    rescue
      self_type
    end

    private def remember_arg_types(args : Array(Crystal::Arg)) : Nil
      args.each { |arg| remember_arg_type(arg) }
    end

    private def remember_arg_type(arg : Crystal::Arg?) : Nil
      return unless arg
      return unless restriction = arg.restriction
      return unless type = resolve_type?(restriction)
      return if arg.name == "self"

      current_frame.typed_locals[arg.name] = type
    end

    private def remember_local_type(var_node : Crystal::ASTNode, restriction : Crystal::ASTNode?) : Nil
      return unless restriction
      return unless var = var_node.as?(Crystal::Var)
      return if var.name == "self"
      return unless type = resolve_type?(restriction)

      current_frame.typed_locals[var.name] = type
    end

    private def builtin_type(name : String) : Crystal::Type?
      current_type.lookup_type?(Crystal::Path.global([name]), self_type_for_lookup)
    rescue
      nil
    end

    private def number_type(kind : Crystal::NumberKind) : Crystal::Type?
      builtin_type(number_type_name(kind))
    end

    private def number_type_name(kind : Crystal::NumberKind) : String
      NUMBER_TYPE_NAMES[kind]? || raise "Unsupported number kind: #{kind}"
    end

    private def self_type_for_lookup : Crystal::Type
      self_type || current_type.instance_type
    rescue
      current_type
    end

    private def push_frame(
      *,
      current_type : Crystal::Type,
      self_type : Crystal::Type?,
      in_def : Bool = current_frame.in_def?,
      in_macro : Bool = current_frame.in_macro?,
      inherit_locals : Bool = true,
      & : -> _
    )
      locals = inherit_locals ? current_frame.typed_locals.dup : {} of String => Crystal::Type
      @frames << Frame.new(current_type, self_type, in_def, in_macro, locals)
      sync_scope!

      yield
    ensure
      @frames.pop? if @frames.size > 1
      sync_scope!
    end

    private def current_frame : Frame
      @frames.last
    end

    private def sync_scope! : Nil
      frame = current_frame
      @current_type = frame.current_type
      @self_type = frame.self_type
    end
  end
end
