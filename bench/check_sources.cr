require "../src/ameba"
require "benchmark"

private def get_files(n)
  Dir["src/**/*.cr"].first(n)
end

private def include_entrypoint(files, entrypoint = "src/cli.cr")
  return [entrypoint] if files.empty?
  return files if files.includes?(entrypoint)

  files.dup.tap do |paths|
    paths[0] = entrypoint
  end
end

puts "== Compare:"
Benchmark.ips do |x|
  [
    1,
    3,
    5,
    10,
    20,
    30,
    40,
  ].each do |n| # ameba:disable Naming/BlockParameterName
    files = include_entrypoint(get_files(n))

    config = Ameba::Config.load
    config.formatter = Ameba::Formatter::BaseFormatter.new
    config.globs = files.to_set
    semantic_config = Ameba::Config.load
    semantic_config.formatter = Ameba::Formatter::BaseFormatter.new
    semantic_config.globs = files.to_set
    semantic_config.analysis = :top_level_semantic
    semantic_config.entrypoints = [files.first]

    s = n == 1 ? "" : "s"
    x.report("#{n} source#{s} (syntax)") { Ameba.run config }
    x.report("#{n} source#{s} (semantic)") { Ameba.run semantic_config }
  end
end

puts "== Measure:"
config = Ameba::Config.load
config.formatter = Ameba::Formatter::BaseFormatter.new
semantic_config = Ameba::Config.load
semantic_config.formatter = Ameba::Formatter::BaseFormatter.new
semantic_config.analysis = :top_level_semantic
semantic_config.entrypoints = ["src/cli.cr"]

puts "Syntax only:"
puts Benchmark.measure { Ameba.run config }
puts "With semantic:"
puts Benchmark.measure { Ameba.run semantic_config }
