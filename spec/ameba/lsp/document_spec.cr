require "../../spec_helper"

module Ameba::LSP
  describe Document do
    it "converts indices to zero-based positions" do
      document = Document.new("file:///tmp/a.cr", "foo\nbar\n")

      document.index_to_position(0).should eq Ameba::LSP::Protocol::Position.new(0, 0)
      document.index_to_position(3).should eq Ameba::LSP::Protocol::Position.new(0, 3)
      document.index_to_position(4).should eq Ameba::LSP::Protocol::Position.new(1, 0)
      document.index_to_position(6).should eq Ameba::LSP::Protocol::Position.new(1, 2)
    end

    it "rebuilds offsets when text is updated" do
      document = Document.new("file:///tmp/a.cr", "a")
      document.update("a\nb", 2)

      document.version.should eq 2
      document.index_to_position(2).should eq Ameba::LSP::Protocol::Position.new(1, 0)
    end

    it "converts character-based indices for multibyte text" do
      document = Document.new("file:///tmp/a.cr", "éa\nZ")

      document.index_to_position(2).should eq Ameba::LSP::Protocol::Position.new(0, 2)
      document.index_to_position(3).should eq Ameba::LSP::Protocol::Position.new(1, 0)
    end

    it "converts astral characters to utf-16 code units by default" do
      document = Document.new("file:///tmp/a.cr", "😀a\nZ")

      document.index_to_position(1).should eq Ameba::LSP::Protocol::Position.new(0, 2)
      document.index_to_position(2).should eq Ameba::LSP::Protocol::Position.new(0, 3)
    end

    it "supports utf-8 and utf-32 position encodings" do
      document = Document.new("file:///tmp/a.cr", "😀a\nZ")

      document.index_to_position(1, Protocol::PositionEncoding::UTF8).should eq Ameba::LSP::Protocol::Position.new(0, 4)
      document.index_to_position(1, Protocol::PositionEncoding::UTF32).should eq Ameba::LSP::Protocol::Position.new(0, 1)
    end

    it "converts positions back to indices across encodings" do
      document = Document.new("file:///tmp/a.cr", "😀a\nZ")

      document.position_to_index(Ameba::LSP::Protocol::Position.new(0, 2)).should eq 1
      document.position_to_index(Ameba::LSP::Protocol::Position.new(0, 4), Protocol::PositionEncoding::UTF8).should eq 1
      document.position_to_index(Ameba::LSP::Protocol::Position.new(0, 1), Protocol::PositionEncoding::UTF32).should eq 1
      document.position_to_index(Ameba::LSP::Protocol::Position.new(0, 1)).should eq 0
    end

    it "applies ranged changes" do
      document = Document.new("file:///tmp/a.cr", "class Z; end\n")
      change = Ameba::LSP::Protocol::TextDocumentContentChangeEvent.new(
        text: "A",
        range: Ameba::LSP::Protocol::Range.new(
          start: Ameba::LSP::Protocol::Position.new(0, 6),
          end: Ameba::LSP::Protocol::Position.new(0, 7),
        ),
      )

      document.apply_change(change)
      document.text.should eq "class A; end\n"
    end

    it "applies utf-8 ranged changes" do
      document = Document.new("file:///tmp/a.cr", "\"😀\"; class Z; end\n")
      change = Ameba::LSP::Protocol::TextDocumentContentChangeEvent.new(
        text: "A",
        range: Ameba::LSP::Protocol::Range.new(
          start: Ameba::LSP::Protocol::Position.new(0, 14),
          end: Ameba::LSP::Protocol::Position.new(0, 15),
        ),
      )

      document.apply_change(change, Protocol::PositionEncoding::UTF8)
      document.text.should eq "\"😀\"; class A; end\n"
    end

    it "applies utf-32 ranged changes and round-trips positions" do
      document = Document.new("file:///tmp/a.cr", "\"😀\"; class Z; end\n")
      change = Ameba::LSP::Protocol::TextDocumentContentChangeEvent.new(
        text: "A",
        range: Ameba::LSP::Protocol::Range.new(
          start: Ameba::LSP::Protocol::Position.new(0, 11),
          end: Ameba::LSP::Protocol::Position.new(0, 12),
        ),
      )

      document.apply_change(change, Protocol::PositionEncoding::UTF32)
      document.text.should eq "\"😀\"; class A; end\n"
      document.index_to_position(2, Protocol::PositionEncoding::UTF32).should eq Ameba::LSP::Protocol::Position.new(0, 2)
      document.position_to_index(Ameba::LSP::Protocol::Position.new(0, 11), Protocol::PositionEncoding::UTF32).should eq 11
    end

    it "extracts path from uri" do
      Document.path_from_uri("file:///tmp/example.cr").should eq "/tmp/example.cr"
    end

    it "keeps non-file uri as path fallback" do
      Document.path_from_uri("untitled:Untitled-1").should eq "untitled:Untitled-1"
    end
  end
end
