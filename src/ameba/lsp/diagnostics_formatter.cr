class Ameba::LSP::DiagnosticsFormatter < Ameba::Formatter::BaseFormatter
  property cancellation_check : Proc(Nil)?
  getter diagnostics = [] of Ameba::LSP::Protocol::Diagnostic

  @mutex = Mutex.new

  def source_finished(source : Ameba::Source) : Nil
    diagnostics = [] of Ameba::LSP::Protocol::Diagnostic

    source.issues.each do |issue|
      next if issue.disabled?

      cancellation_check.try &.call

      diagnostics << Ameba::LSP::Protocol::Diagnostic.new(
        message: "[#{issue.rule.name}] #{issue.message}",
        range: range_for(issue),
        severity: convert_severity(issue.rule.severity),
      )
    end

    @mutex.synchronize do
      @diagnostics.concat(diagnostics)
    end
  end

  private def convert_severity(severity : Ameba::Severity) : Ameba::LSP::Protocol::DiagnosticSeverity
    case severity
    in .error?
      Ameba::LSP::Protocol::DiagnosticSeverity::Error
    in .warning?
      Ameba::LSP::Protocol::DiagnosticSeverity::Warning
    in .convention?
      Ameba::LSP::Protocol::DiagnosticSeverity::Information
    end
  end

  private def range_for(issue : Ameba::Issue) : Ameba::LSP::Protocol::Range
    start_line = (issue.location.try(&.line_number.to_u32) || 1_u32) - 1
    start_char = (issue.location.try(&.column_number.to_u32) || 1_u32) - 1

    end_line = (issue.end_location.try(&.line_number.to_u32) || issue.location.try(&.line_number.to_u32) || 1_u32) - 1
    end_char = issue.end_location.try(&.column_number.to_u32) ||
               issue.location.try(&.column_number.to_u32) ||
               1_u32

    Ameba::LSP::Protocol::Range.new(
      start: Ameba::LSP::Protocol::Position.new(line: start_line, character: start_char),
      end: Ameba::LSP::Protocol::Position.new(line: end_line, character: end_char),
    )
  end
end
