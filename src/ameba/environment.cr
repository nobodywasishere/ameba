module Ameba
  module Environment
    extend self

    @@configured = false
    @@mutex = Mutex.new

    # Applies variables returned by `crystal env` to the current process.
    # This is required for compiler APIs to resolve Crystal installation paths.
    def configure! : Nil
      return if @@configured

      @@mutex.synchronize do
        return if @@configured

        crystal_env.each do |key, value|
          ENV[key] = value
        end

        @@configured = true
      end
    end

    private def crystal_env
      output = IO::Memory.new
      error = IO::Memory.new

      status = Process.run("crystal", ["env"], output: output, error: error)
      unless status.success?
        details = error.to_s.presence || output.to_s.presence || "unknown error"
        raise "Unable to read compiler environment via `crystal env`: #{details.strip}"
      end

      output
        .to_s
        .lines(chomp: true)
        .each_with_object({} of String => String) do |line, env|
          next if line.blank?

          key, value = line.split('=', limit: 2)
          next unless key.presence && value

          env[key] = value
        end
    end
  end
end
