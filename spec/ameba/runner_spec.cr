require "../spec_helper"

module Ameba
  private def runner(files = [__FILE__], formatter = DummyFormatter.new)
    config = Config.load
    config.formatter = formatter
    config.globs = files.to_set

    config.update_rule VersionedRule.rule_name, enabled: false
    config.update_rule ErrorRule.rule_name, enabled: false
    config.update_rule PerfRule.rule_name, enabled: false
    config.update_rule AtoAA.rule_name, enabled: false
    config.update_rule AtoB.rule_name, enabled: false
    config.update_rule BtoA.rule_name, enabled: false
    config.update_rule BtoC.rule_name, enabled: false
    config.update_rule CtoA.rule_name, enabled: false
    config.update_rule ClassToModule.rule_name, enabled: false
    config.update_rule ModuleToClass.rule_name, enabled: false

    Runner.new(config)
  end

  describe Runner do
    formatter = DummyFormatter.new
    default_severity = Severity::Convention

    describe "#run" do
      it "returns self" do
        runner.run.should be_a(Runner)
      end

      context "invokes hooks" do
        before_each do
          runner(formatter: formatter).run
        end

        it "calls started callback" do
          formatter.started_sources.should_not be_nil
        end

        it "calls finished callback" do
          formatter.finished_sources.should_not be_nil
        end

        it "calls source_started callback" do
          formatter.started_source.should_not be_nil
        end

        it "calls source_finished callback" do
          formatter.finished_source.should_not be_nil
        end
      end

      it "checks accordingly to the rule #since_version" do
        rules = [VersionedRule.new] of Rule::Base
        source = Source.new path: "source.cr"

        v1_0_0 = SemanticVersion.parse("1.0.0")
        Runner.new(rules, [source], formatter, default_severity, false, v1_0_0).run.success?.should be_true

        v1_5_0 = SemanticVersion.parse("1.5.0")
        Runner.new(rules, [source], formatter, default_severity, false, v1_5_0).run.success?.should be_false

        v1_10_0 = SemanticVersion.parse("1.10.0")
        Runner.new(rules, [source], formatter, default_severity, false, v1_10_0).run.success?.should be_false
      end

      it "skips rules based on severity" do
        rules = [ErrorRule.new] of Rule::Base

        Source.new.tap do |source|
          Runner.new(rules, [source], formatter, :convention).run
          source.issues.size.should eq(1)
        end

        Source.new.tap do |source|
          Runner.new(rules, [source], formatter, :warning).run
          source.issues.should be_empty
        end
      end

      it "skips rule check if source is excluded" do
        path = "source.cr"
        source = Source.new(path: path)

        all_rules = ([] of Rule::Base).tap do |rules|
          rule = ErrorRule.new
          rule.excluded = Set{path}
          rules << rule
        end

        Runner.new(all_rules, [source], formatter, default_severity).run.success?.should be_true
      end

      it "aborts because of an infinite loop" do
        rules = [AtoAA.new] of Rule::Base
        source = Source.new "class A; end", "source.cr"
        message = "Infinite loop in source.cr caused by Ameba/AtoAA"

        expect_raises(Runner::InfiniteCorrectionLoopError, message) do
          Runner.new(rules, [source], formatter, default_severity, autocorrect: true).run
        end
      end

      context "exception in rule" do
        it "raises an exception raised in fiber while running a rule" do
          rule = RaiseRule.new
          rule.should_raise = true
          rules = [rule] of Rule::Base
          source = Source.new path: "source.cr"

          expect_raises(Exception, "something went wrong") do
            Runner.new(rules, [source], formatter, default_severity).run
          end
        end
      end

      context "issues sorting" do
        it "sorts issues by severity, line number, and column number" do
          rules = [
            ErrorRule.from_yaml("{ Severity: convention, Message: foo }"),
            ErrorRule.from_yaml("{ Severity: convention, Message: bar, LineNumber: 2 }"),
            ErrorRule.from_yaml("{ Severity: warning, Message: baz, LineNumber: 2 }"),
            ErrorRule.from_yaml("{ Severity: error, Message: bat, LineNumber: 2 }"),
            ErrorRule.from_yaml("{ Severity: warning, Message: baq }"),
          ] of Rule::Base
          source = Source.new "foo\nbar"

          Runner.new(rules, [source], formatter, default_severity).run
          source.should_not be_valid
          source.issues.map(&.message).should eq %w[foo baq bar baz bat]
        end
      end

      context "invalid syntax" do
        it "reports a syntax error" do
          rules = [Rule::Lint::Syntax.new] of Rule::Base
          source = Source.new "def bad_syntax"

          Runner.new(rules, [source], formatter, default_severity).run
          source.should_not be_valid
          source.issues.first.rule.should be_a Rule::Lint::Syntax
        end

        it "does not run other rules" do
          rules = [Rule::Lint::Syntax.new, Rule::Naming::ConstantNames.new]
          source = Source.new <<-CRYSTAL
            MyBadConstant = 1

            when my_bad_syntax
            CRYSTAL

          Runner.new(rules, [source], formatter, default_severity).run
          source.should_not be_valid
          source.issues.size.should eq 1
        end
      end

      context "semantic stage" do
        it "does not run semantic rules when analysis is syntax-only" do
          rule = SemanticTrackingRule.new
          source = Source.new("value : Int32 = 1\n", "source.cr")

          Runner.new([rule] of Rule::Base, [source], formatter, default_severity).run
          rule.inspected_sources.should be_empty
        end

        it "runs semantic rules in primitive semantic mode without entrypoint" do
          rule = SemanticTrackingRule.new
          source = Source.new("value : Int32 = 1\n", "source.cr")

          Runner
            .new([rule] of Rule::Base, [source], [] of String, formatter, default_severity, false, :primitive_semantic)
            .run

          rule.inspected_sources.should eq ["source.cr"]
        end

        it "runs primitive semantic rules for source with relative requires" do
          base = File.tempname("ameba-semantic")
          Dir.mkdir(base)

          dependency = File.join(base, "dep.cr")
          main = File.join(base, "main.cr")
          File.write(dependency, "class Dep\nend\n")
          source = Source.new("require \"./dep\"\nvalue : Dep = Dep.new\n", main)
          rule = SemanticTrackingRule.new

          Runner
            .new([rule] of Rule::Base, [source], [] of String, formatter, default_severity, false, :primitive_semantic)
            .run

          rule.inspected_sources.should eq [main]
        end

        it "does not run top-level semantic rules in primitive semantic mode" do
          rule = TopLevelSemanticTrackingRule.new
          source = Source.new("value : Int32 = 1\n", "source.cr")

          Runner
            .new([rule] of Rule::Base, [source], [] of String, formatter, default_severity, false, :primitive_semantic)
            .run

          rule.inspected_sources.should be_empty
        end

        it "skips semantic rules when syntax errors are present" do
          rule = SemanticTrackingRule.new
          source = Source.new("def bad_syntax", "source.cr")

          Runner
            .new([rule] of Rule::Base, [source], [source.path], formatter, default_severity, false, :top_level_semantic)
            .run

          source.issues.any?(&.syntax?).should be_true
          rule.inspected_sources.should be_empty
        end

        it "runs semantic rules when top-level semantic mode is enabled" do
          rule = SemanticTrackingRule.new
          source = Source.new("value : Int32 = 1\n", "source.cr")

          Runner
            .new([rule] of Rule::Base, [source], [source.path], formatter, default_severity, false, :top_level_semantic)
            .run

          rule.inspected_sources.should eq ["source.cr"]
        end

        it "reports semantic compiler errors" do
          source = Source.new(%(require "./missing_file"\n), "source.cr")

          Runner
            .new([] of Rule::Base, [source], [source.path], formatter, default_severity, false, :top_level_semantic)
            .run

          source.issues.any? { |issue| issue.rule.is_a?(Rule::Lint::Semantic) }.should be_true
        end

        it "still runs semantic rules when top-level context fails to build" do
          source = Source.new(<<-CRYSTAL, "source.cr")
            module JSON
              module Serializable
                annotation Options
                end
              end
            end

            module Options
            end

            class Foo
              include JSON::Serializable
              include Options
            end
            CRYSTAL

          rules = [Rule::Lint::NamespaceCollision.new] of Rule::Base
          Runner
            .new(rules, [source], [source.path], formatter, default_severity, false, :top_level_semantic)
            .run

          source.issues.any? { |issue| issue.rule.is_a?(Rule::Lint::Semantic) }.should be_true
          source.issues.any? { |issue| issue.rule.is_a?(Rule::Lint::NamespaceCollision) }.should be_true
        end

        it "fails fast when semantic entrypoint source is missing" do
          source = Source.new("value : Int32 = 1\n", "source.cr")

          expect_raises(Exception) do
            Runner
              .new([] of Rule::Base, [source], ["missing.cr"], formatter, default_severity, false, :top_level_semantic)
              .run
          end
        end

        it "fails with a clear message when top-level analysis has no entrypoint" do
          source = Source.new("value : Int32 = 1\n", "source.cr")
          message = "Invalid analysis config: `Entrypoints` must contain exactly one entrypoint for TopLevelSemantic."

          expect_raises(Exception, message) do
            Runner
              .new([] of Rule::Base, [source], [] of String, formatter, default_severity, false, :top_level_semantic)
              .run
          end
        end

        it "runs unneeded-disable checks after semantic rules" do
          source = Source.new(<<-CRYSTAL, "source.cr")
            # ameba:disable Lint/UnknownType
            value : UnknownType = 1
            CRYSTAL
          rules = [Rule::Lint::UnknownType.new, Rule::Lint::UnneededDisableDirective.new] of Rule::Base

          Runner
            .new(rules, [source], [] of String, formatter, default_severity, false, :primitive_semantic)
            .run

          source.issues.any? { |issue| issue.rule.is_a?(Rule::Lint::UnneededDisableDirective) }.should be_false
          source.issues.any? { |issue| issue.rule.is_a?(Rule::Lint::UnknownType) && issue.disabled? }.should be_true
        end

        it "emits one formatter source completion per source in semantic mode" do
          semantic_formatter = CountingFormatter.new
          source = Source.new("value : Int32 = 1\n", "source.cr")

          Runner
            .new([] of Rule::Base, [source], [] of String, semantic_formatter, default_severity, false, :primitive_semantic)
            .run

          semantic_formatter.finished_paths.should eq ["source.cr"]
        end
      end

      context "unneeded disables" do
        it "reports an issue if such disable exists" do
          rules = [Rule::Lint::UnneededDisableDirective.new] of Rule::Base
          source = Source.new <<-CRYSTAL
            a = 1 # ameba:disable LineLength
            CRYSTAL

          Runner.new(rules, [source], formatter, default_severity).run
          source.should_not be_valid
          source.issues.first.rule.should be_a Rule::Lint::UnneededDisableDirective
        end
      end

      pending "handles rules with incompatible autocorrect" do
        rules = [Rule::Performance::MinMaxAfterMap.new, Rule::Style::VerboseBlock.new]
        source = Source.new "list.map { |i| i.size }.max", File.tempname("source", ".cr")

        Runner.new(rules, [source], formatter, default_severity, autocorrect: true).run
        source.code.should eq "list.max_of(&.size)"
      end
    end

    describe "#explain" do
      output = IO::Memory.new

      before_each do
        output.clear
      end

      it "writes nothing if sources are valid" do
        runner = runner(formatter: formatter).run
        runner.explain(Crystal::Location.new("source.cr", 1, 2), output)
        output.to_s.should be_empty
      end

      it "writes the explanation if sources are not valid and location found" do
        rules = [ErrorRule.new] of Rule::Base
        source = Source.new "a = 1", "source.cr"

        runner = Runner.new(rules, [source], formatter, default_severity).run
        runner.explain(Crystal::Location.new("source.cr", 1, 1), output)
        output.to_s.should_not be_empty
      end

      it "writes nothing if sources are not valid and location is not found" do
        rules = [ErrorRule.new] of Rule::Base
        source = Source.new "a = 1", "source.cr"

        runner = Runner.new(rules, [source], formatter, default_severity).run
        runner.explain(Crystal::Location.new("source.cr", 1, 2), output)
        output.to_s.should be_empty
      end
    end

    describe "#success?" do
      it "returns true if runner has not been run" do
        runner.success?.should be_true
      end

      it "returns true if all sources are valid" do
        runner.run.success?.should be_true
      end

      it "returns false if there are invalid sources" do
        rules = Rule.rules.map &.new.as(Rule::Base)
        source = Source.new "WrongConstant = 5"

        Runner.new(rules, [source], formatter, default_severity).run.success?.should be_false
      end

      it "depends on the level of severity" do
        rules = Rule.rules.map &.new.as(Rule::Base)
        source = Source.new "WrongConstant = 5\n"

        Runner.new(rules, [source], formatter, :error).run.success?.should be_true
        Runner.new(rules, [source], formatter, :warning).run.success?.should be_true
        Runner.new(rules, [source], formatter, :convention).run.success?.should be_false
      end

      it "returns false if issue is disabled" do
        rules = [NamedRule.new] of Rule::Base
        source = Source.new <<-CRYSTAL
          def foo
            bar = 1 # ameba:disable #{NamedRule.name}
          end
          CRYSTAL
        source.add_issue NamedRule.new, location: {2, 1},
          message: "Useless assignment"

        Runner
          .new(rules, [source], formatter, default_severity)
          .run.success?.should be_true
      end
    end

    describe "#run with rules autocorrecting each other" do
      context "with two conflicting rules" do
        context "if there is an offense in an inspected file" do
          it "aborts because of an infinite loop" do
            rules = [AtoB.new, BtoA.new]
            source = Source.new "class A; end", "source.cr"
            message = "Infinite loop in source.cr caused by Ameba/AtoB -> Ameba/BtoA"

            expect_raises(Runner::InfiniteCorrectionLoopError, message) do
              Runner.new(rules, [source], formatter, default_severity, autocorrect: true).run
            end
          end
        end

        context "if there are multiple offenses in an inspected file" do
          it "aborts because of an infinite loop" do
            rules = [AtoB.new, BtoA.new]
            source = Source.new <<-CRYSTAL, "source.cr"
              class A; end
              class A_A; end
              CRYSTAL
            message = "Infinite loop in source.cr caused by Ameba/AtoB -> Ameba/BtoA"

            expect_raises(Runner::InfiniteCorrectionLoopError, message) do
              Runner.new(rules, [source], formatter, default_severity, autocorrect: true).run
            end
          end
        end
      end

      context "with two pairs of conflicting rules" do
        it "aborts because of an infinite loop" do
          rules = [ClassToModule.new, ModuleToClass.new, AtoB.new, BtoA.new]
          source = Source.new "class A_A; end", "source.cr"
          message = "Infinite loop in source.cr caused by Ameba/ClassToModule, Ameba/AtoB -> Ameba/ModuleToClass, Ameba/BtoA"

          expect_raises(Runner::InfiniteCorrectionLoopError, message) do
            Runner.new(rules, [source], formatter, default_severity, autocorrect: true).run
          end
        end
      end

      context "with three rule cycle" do
        it "aborts because of an infinite loop" do
          rules = [AtoB.new, BtoC.new, CtoA.new]
          source = Source.new "class A; end", "source.cr"
          message = "Infinite loop in source.cr caused by Ameba/AtoB -> Ameba/BtoC -> Ameba/CtoA"

          expect_raises(Runner::InfiniteCorrectionLoopError, message) do
            Runner.new(rules, [source], formatter, default_severity, autocorrect: true).run
          end
        end
      end
    end
  end
end
