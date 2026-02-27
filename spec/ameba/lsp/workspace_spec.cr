require "../../spec_helper"
require "file_utils"

module Ameba::LSP
  extend self

  def self.with_tmpdir(prefix : String, & : Path ->)
    path = Path[Dir.tempdir, "#{prefix}-#{Random::Secure.hex(6)}"]
    Dir.mkdir_p(path)

    begin
      yield path
    ensure
      FileUtils.rm_r(path) if Dir.exists?(path)
    end
  end

  describe Workspace do
    it "resolves workspace root and config path using closest shard.yml" do
      Ameba::LSP.with_tmpdir("ameba-lsp-workspace") do |root|
        source_dir = root / "src"
        source_path = source_dir / "foo.cr"
        config_path = root / Ameba::Config::Loader::FILENAME

        Dir.mkdir_p(source_dir)
        File.write(root / "shard.yml", "name: sample\nversion: 0.1.0\n")
        File.write(config_path, "{}")

        resolved_root, resolved_config = Workspace.resolve(source_path)
        resolved_root.should eq root
        resolved_config.should eq config_path
      end
    end

    it "returns nils when no workspace root is found" do
      Ameba::LSP.with_tmpdir("ameba-lsp-noworkspace") do |tmp_root|
        source_path = tmp_root / "foo.cr"
        resolved_root, config = Workspace.resolve(source_path)

        resolved_root.should be_nil
        config.should be_nil
      end
    end

    it "extracts and decodes path from uri" do
      uri = URI.parse("file:///tmp/example%20file.cr")
      Workspace.path_from_uri(uri).should eq "/tmp/example file.cr"
    end

    it "extracts windows drive paths from file uris" do
      uri = URI.parse("file:///C:/Users/margret/example.cr")
      Workspace.path_from_uri(uri).should eq "C:/Users/margret/example.cr"
    end

    it "extracts UNC paths from file uris with host" do
      uri = URI.parse("file://server/share/example.cr")
      Workspace.path_from_uri(uri).should eq "//server/share/example.cr"
    end

    it "returns non-file uris unchanged" do
      uri = URI.parse("untitled:Untitled-1")
      Workspace.path_from_uri(uri).should eq "untitled:Untitled-1"
    end
  end
end
