require "uri"

class Ameba::LSP::Document
  DEFAULT_POSITION_ENCODING = Ameba::LSP::Protocol::PositionEncoding::UTF16

  getter uri : String
  getter path : String
  getter text : String
  property version : Int64?

  @line_offsets = [0] of Int32

  def initialize(@uri : String, @text : String, @version : Int64? = nil, path : String? = nil)
    @path = path || self.class.path_from_uri(uri)
    rebuild_line_offsets
  end

  def update(text : String, version : Int64? = @version) : Nil
    @text = text
    @version = version
    rebuild_line_offsets
  end

  def apply_change(change : Ameba::LSP::Protocol::TextDocumentContentChangeEvent,
                   position_encoding : String | Ameba::LSP::Protocol::PositionEncoding = DEFAULT_POSITION_ENCODING) : Nil
    if range = change.range
      apply_range_change(range, change.text, position_encoding)
    else
      @text = change.text
      rebuild_line_offsets
    end
  end

  def index_to_position(index : Int32, position_encoding : String | Ameba::LSP::Protocol::PositionEncoding = DEFAULT_POSITION_ENCODING) : Ameba::LSP::Protocol::Position
    index = index.clamp(0, @text.size)

    line_index = (@line_offsets.bsearch_index { |offset| offset > index } || @line_offsets.size) - 1
    line_start = @line_offsets[line_index]
    character = index - line_start

    Ameba::LSP::Protocol::Position.new(
      line: line_index.to_u32,
      character: lsp_character_for(line_index, character, normalize_position_encoding(position_encoding)),
    )
  end

  def position_to_index(position : Ameba::LSP::Protocol::Position,
                        position_encoding : String | Ameba::LSP::Protocol::PositionEncoding = DEFAULT_POSITION_ENCODING) : Int32
    line_index = position.line.to_i
    return @text.size if line_index < 0 || line_index >= @line_offsets.size

    line_start = @line_offsets[line_index]
    line_end = line_end_for(line_index)
    line = @text[line_start...line_end]

    line_start + character_index_for_lsp_units(line, position.character, normalize_position_encoding(position_encoding))
  end

  def self.path_from_uri(uri : String) : String
    parsed = URI.parse(uri)
    Ameba::LSP::Workspace.path_from_uri(parsed)
  rescue
    uri
  end

  private def rebuild_line_offsets : Nil
    @line_offsets = [0] of Int32
    i = 0
    @text.each_char do |char|
      @line_offsets << i + 1 if char == '\n'
      i += 1
    end
  end

  def convert_lsp_character(line : UInt32, character : UInt32, position_encoding : String | Ameba::LSP::Protocol::PositionEncoding = DEFAULT_POSITION_ENCODING) : UInt32
    line_index = line.to_i
    return character if line_index < 0 || line_index >= @line_offsets.size

    line_start = @line_offsets[line_index]
    line_end = line_end_for(line_index)

    character_index = character.to_i.clamp(0, line_end - line_start)
    lsp_character_for(line_index, character_index, normalize_position_encoding(position_encoding))
  end

  private def lsp_character_for(line_index : Int32, character_index : Int32, position_encoding : Ameba::LSP::Protocol::PositionEncoding) : UInt32
    line_start = @line_offsets[line_index]
    prefix_end = line_start + character_index
    prefix = @text[line_start...prefix_end]

    case position_encoding
    when .utf8?
      prefix.bytesize.to_u32
    when .utf32?
      prefix.size.to_u32
    else
      utf16_units(prefix)
    end
  end

  private def line_end_for(line_index : Int32) : Int32
    if next_line_start = @line_offsets[line_index + 1]?
      # Exclude line separator from line content.
      next_line_start - 1
    else
      @text.size
    end
  end

  private def apply_range_change(range : Ameba::LSP::Protocol::Range,
                                 replacement : String,
                                 position_encoding : String | Ameba::LSP::Protocol::PositionEncoding) : Nil
    start_index = position_to_index(range.start, position_encoding)
    end_index = position_to_index(range.end, position_encoding)
    end_index = start_index if end_index < start_index

    @text = String.build do |io|
      io << @text[0...start_index]
      io << replacement
      io << @text[end_index...@text.size]
    end

    rebuild_line_offsets
  end

  private def character_index_for_lsp_units(text : String,
                                            requested_units : UInt32,
                                            position_encoding : Ameba::LSP::Protocol::PositionEncoding) : Int32
    target = requested_units.to_i
    return 0 if target <= 0

    consumed = 0
    character_index = 0

    text.each_char do |char|
      next_consumed = consumed + units_for(char, position_encoding)
      break if next_consumed > target

      consumed = next_consumed
      character_index += 1
    end

    character_index
  end

  private def units_for(char : Char, position_encoding : Ameba::LSP::Protocol::PositionEncoding) : Int32
    case position_encoding
    when .utf8?
      utf8_units(char)
    when .utf32?
      1
    else
      char.ord > 0xFFFF ? 2 : 1
    end
  end

  private def normalize_position_encoding(position_encoding : String | Ameba::LSP::Protocol::PositionEncoding) : Ameba::LSP::Protocol::PositionEncoding
    case position_encoding
    when Ameba::LSP::Protocol::PositionEncoding
      position_encoding
    when String
      Ameba::LSP::Protocol::PositionEncoding.from_protocol?(position_encoding) || DEFAULT_POSITION_ENCODING
    else
      DEFAULT_POSITION_ENCODING
    end
  end

  private def utf8_units(char : Char) : Int32
    case char.ord
    when ..0x7F
      1
    when ..0x7FF
      2
    when ..0xFFFF
      3
    else
      4
    end
  end

  private def utf16_units(text : String) : UInt32
    units = 0_u32
    text.each_char do |char|
      units += char.ord > 0xFFFF ? 2_u32 : 1_u32
    end
    units
  end
end
