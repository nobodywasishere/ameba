module Ameba::LSP::AnalyzerProvider
  abstract def analyze(code : String,
                       path : String,
                       config_path : String | Path? = nil,
                       root : Path? = nil,
                       cancellation_check : Proc(Nil)? = nil,
                       disable_typing_noise_rules = true) : Ameba::LSP::Analyzer::Result
end

class Ameba::LSP::Analyzer
  include Ameba::LSP::AnalyzerProvider
  # Rules that are too noisy while user is typing.
  RULES_DISABLED_WHILE_TYPING = %w[
    Layout/TrailingBlankLines
    Layout/TrailingWhitespace
    Lint/Formatting
  ]

  record Result,
    diagnostics : Array(Ameba::LSP::Protocol::Diagnostic),
    issues : Array(Ameba::Issue)

  # Analyze a source loaded from in-memory text.
  def analyze(code : String,
              path : String,
              config_path : String | Path? = nil,
              root : Path? = nil,
              cancellation_check : Proc(Nil)? = nil,
              disable_typing_noise_rules = true) : Result
    source = Ameba::Source.new(code, path)
    config = Ameba::Config.load(path: config_path, root: root)

    analyze(
      source,
      config,
      cancellation_check: cancellation_check,
      disable_typing_noise_rules: disable_typing_noise_rules,
    )
  end

  # Analyze a single source with an existing config.
  def analyze(source : Ameba::Source,
              config : Ameba::Config,
              cancellation_check : Proc(Nil)? = nil,
              disable_typing_noise_rules = true) : Result
    formatter = Ameba::LSP::DiagnosticsFormatter.new
    formatter.cancellation_check = cancellation_check

    previous_formatter = config.formatter
    previous_cancellation_check = config.cancellation_check

    config.with_sources_override([source]) do
      config.formatter = formatter
      config.cancellation_check = cancellation_check

      changed_rule_states = [] of {Ameba::Rule::Base, Bool}
      changed_rule_states = disable_typing_noise_rules_in_config(config) if disable_typing_noise_rules

      begin
        Ameba::Runner.new(config).run
      ensure
        restore_rule_states(changed_rule_states)
        config.formatter = previous_formatter
        config.cancellation_check = previous_cancellation_check
      end
    end

    Result.new(
      diagnostics: formatter.diagnostics.dup,
      issues: source.issues.dup,
    )
  end

  private def disable_typing_noise_rules_in_config(config : Ameba::Config) : Array({Ameba::Rule::Base, Bool})
    changed_rule_states = [] of {Ameba::Rule::Base, Bool}

    RULES_DISABLED_WHILE_TYPING.each do |rule_name|
      next unless rule = config.rules.find(&.name.==(rule_name))

      changed_rule_states << {rule, rule.enabled?}
      rule.enabled = false
    end

    changed_rule_states
  end

  private def restore_rule_states(changed_rule_states : Array({Ameba::Rule::Base, Bool})) : Nil
    changed_rule_states.each do |rule, enabled|
      rule.enabled = enabled
    end
  end
end
