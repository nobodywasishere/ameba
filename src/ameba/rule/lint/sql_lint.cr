module Ameba::Rule::Lint
  class SQLLint < Base
    include AST::Util

    properties do
      since_version "1.7.0"
      description "Reports SQL lints via SQLFluff"
      severity :error

      dialect "postgres"
      bin_path nil, as: String?
      config_path nil, as: String?
      fail_on_missing_bin false
    end

    BIN_PATH = Process.find_executable("sqlfluff") rescue nil

    @@mutex = Mutex.new

    def bin_path : String?
      @bin_path || BIN_PATH
    end

    def test(source, node : Crystal::StringInterpolation)
      return unless (code = node_source(node, source.lines)) && code.starts_with?("<<-SQL")
      # Heredocs without interpolation are always size 1
      return unless node.expressions.size == 1
      return unless expr = node.expressions.first?.as?(Crystal::StringLiteral)
      return unless start_location = node.location

      if bin_path = self.bin_path
        violations = lint_expression(bin_path, source.path, expr.value)

        violations.try &.each do |violation|
          issue_for(
            {
              violation.start_line_no + start_location.line_number,
              violation.start_line_pos + node.heredoc_indent,
            },
            {
              violation.end_line_no + start_location.line_number,
              violation.end_line_pos + node.heredoc_indent - 1,
            },
            "[#{violation.code}] #{violation.name}: #{violation.description}",
          )
        end
      elsif fail_on_missing_bin?
        raise RuntimeError.new "Could not find `sqlfluff` executable"
      end
    end

    def lint_expression(
      bin_path : String, path : String, expr : String,
    ) : Array(Violation)?
      result = begin
        # @@mutex.synchronize
        args = %w[lint - --format json --exclude-rules layout.end_of_file]
        args += ["--stdin-filename", path]
        if config_path = self.config_path
          args += ["--config", config_path]
        end
        if dialect = self.dialect
          args += ["--dialect", dialect]
        end

        Process.run(bin_path,
          args: args,
          input: IO::Memory.new(expr),
          output: output = IO::Memory.new,
          error: error = IO::Memory.new
        )

        if error_str = error.to_s.presence
          raise "Failed to execute sqlfluff: #{error_str}"
        end

        output.to_s.presence
      end

      return unless result

      violations = [] of Violation

      pull = JSON::PullParser.new(result)
      pull.read_array do
        pull.read_object do |key|
          case key
          when "violations"
            pull.read_array do
              violations << Violation.new(pull)
            end
          else
            pull.skip
          end
        end
      end

      violations
    end

    protected record Violation,
      name : String,
      code : String,
      warning : Bool,
      description : String,
      start_line_no : Int32,
      start_line_pos : Int32,
      end_line_no : Int32,
      end_line_pos : Int32 do
      def initialize(pull : JSON::PullParser)
        @name = "Unknown"
        @code = "Unknown"
        @warning = false
        @description = "Unknown"
        @start_line_no = 0
        @start_line_pos = 0
        @end_line_no = 0
        @end_line_pos = 0

        pull.read_object do |key|
          case key
          when "name"           then @name = pull.read_string
          when "code"           then @code = pull.read_string
          when "warning"        then @warning = pull.read_bool
          when "description"    then @description = pull.read_string
          when "start_line_no"  then @start_line_no = pull.read_int.to_i32
          when "end_line_no"    then @end_line_no = pull.read_int.to_i32
          when "start_line_pos" then @start_line_pos = pull.read_int.to_i32
          when "end_line_pos"   then @end_line_pos = pull.read_int.to_i32
          else                       pull.skip
          end
        end
      end
    end
  end
end
