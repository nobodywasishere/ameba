module Ameba::Formatter
  # A formatter that creates a todo config.
  # Basically, it takes all issues reported and disables corresponding rules
  # or excludes failed sources from these rules.
  class TODOFormatter < DotFormatter
    def initialize(@output = STDOUT)
    end

    def finished(sources)
      super

      issues = sources.flat_map(&.issues)
      unless issues.any? { |issue| !issue.disabled? }
        @output.puts "No issues found. File is not generated."
        return
      end

      if issues.any?(&.syntax?)
        @output.puts "Unable to generate TODO file. Please fix syntax issues."
        return
      end

      generate_todo_config(issues).tap do |file|
        @output.puts "Created #{file.path}"
      end
    end

    private def generate_todo_config(issues)
      file = File.new(Config::PATH, mode: "w")
      file << header
      rule_issues_map(issues).each do |rule, rule_issues|
        file << "\n# Problems found: #{rule_issues.size}"
        file << "\n# Run `ameba --only #{rule.name}` for details"
        file << rule_todo(rule, rule_issues).gsub("---", "")
      end
      file
    ensure
      file.close if file
    end

    private def rule_issues_map(issues)
      Hash(Rule::Base, Array(Issue)).new.tap do |h|
        issues.each do |issue|
          next if issue.disabled? || issue.rule.is_a?(Rule::Lint::Syntax)
          next if issue.correctable? && config[:autocorrect]?

          (h[issue.rule] ||= Array(Issue).new) << issue
        end
      end
    end

    private def header
      <<-HEADER
        # This configuration file was generated by `ameba --gen-config`
        # on #{Time.utc} using Ameba version #{VERSION}.
        # The point is for the user to remove these configuration records
        # one by one as the reported problems are removed from the code base.

        HEADER
    end

    private def rule_todo(rule, issues)
      rule.excluded = issues
        .compact_map(&.location.try &.filename.try &.to_s)
        .uniq!

      {rule.name => rule}.to_yaml
    end
  end
end
