require "uri"

module Ameba::LSP::Workspace
  extend self

  SHARD_FILE = "shard.yml"

  # Resolves workspace root and explicit config path for a source file.
  #
  # It finds the closest `shard.yml` by traversing parent directories.
  # If found, `<workspace>/.ameba.yml` is used when present.
  def resolve(path : String | Path) : {Path?, Path?}
    workspace_root = find_root(path)
    return {nil, nil} unless workspace_root

    config_path = workspace_root / Ameba::Config::Loader::FILENAME
    config_path = nil unless File.exists?(config_path)

    {workspace_root, config_path}
  end

  # Returns local path extracted from URI, if possible.
  def path_from_uri(uri : URI) : String
    return uri.to_s unless uri.scheme == "file"

    path = URI.decode(uri.path)

    if host = uri.host
      unless host.empty?
        return path if host == "localhost"
        return "//#{host}#{path}"
      end
    end

    if windows_drive_path?(path)
      return path[1..]
    end

    path
  rescue
    uri.to_s
  end

  private def find_root(path : String | Path) : Path?
    current = Path[path].expand
    current = current.parent if File.file?(current)

    dynasty = current.parents + [current]
    dynasty.reverse_each do |dir|
      return dir if File.exists?(dir / SHARD_FILE)
    end
  end

  private def windows_drive_path?(path : String) : Bool
    path.size >= 4 &&
      path[0] == '/' &&
      path[1].ascii_letter? &&
      path[2] == ':' &&
      path[3] == '/'
  end
end
