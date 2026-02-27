require "json"

module Ameba::LSP::Protocol
  # 0-based position within source text.
  record Position,
    line : UInt32,
    character : UInt32 do
    include JSON::Serializable
  end

  # Range within source text represented by start and end positions.
  record Range,
    start : Position,
    end : Position do
    include JSON::Serializable
  end

  enum DiagnosticSeverity
    Error       = 1
    Warning     = 2
    Information = 3
    Hint        = 4
  end

  # LSP diagnostic payload.
  record Diagnostic,
    message : String,
    range : Range,
    severity : DiagnosticSeverity do
    include JSON::Serializable
  end

  # LSP text edit payload.
  record TextEdit,
    range : Range,
    new_text : String do
    include JSON::Serializable

    @[JSON::Field(key: "newText")]
    getter new_text : String
  end

  # LSP workspace edit payload.
  record WorkspaceEdit,
    changes : Hash(String, Array(TextEdit)) do
    include JSON::Serializable
  end

  # LSP text document identifier payload.
  record TextDocumentIdentifier,
    uri : String do
    include JSON::Serializable
  end

  # LSP versioned text document identifier payload.
  record VersionedTextDocumentIdentifier,
    uri : String,
    version : Int64? do
    include JSON::Serializable
  end

  # LSP text document item payload.
  record TextDocumentItem,
    uri : String,
    language_id : String,
    version : Int64,
    text : String do
    include JSON::Serializable

    @[JSON::Field(key: "languageId")]
    getter language_id : String
  end

  # LSP text document content change event payload.
  record TextDocumentContentChangeEvent,
    text : String,
    range : Range? = nil,
    range_length : Int32? = nil do
    include JSON::Serializable

    @[JSON::Field(key: "rangeLength")]
    getter range_length : Int32?
  end

  # LSP publish diagnostics notification params.
  record PublishDiagnosticsParams,
    uri : String,
    diagnostics : Array(Diagnostic) do
    include JSON::Serializable
  end

  # LSP code action payload.
  record CodeAction,
    title : String,
    kind : String? = nil,
    diagnostics : Array(Diagnostic)? = nil,
    edit : WorkspaceEdit? = nil,
    is_preferred : Bool? = nil,
    data : JSON::Any? = nil do
    include JSON::Serializable

    @[JSON::Field(key: "isPreferred")]
    getter is_preferred : Bool?
  end

  # LSP text document didOpen notification params.
  record DidOpenTextDocumentParams,
    text_document : TextDocumentItem do
    include JSON::Serializable

    @[JSON::Field(key: "textDocument")]
    getter text_document : TextDocumentItem
  end

  # LSP text document didChange notification params.
  record DidChangeTextDocumentParams,
    text_document : VersionedTextDocumentIdentifier,
    content_changes : Array(TextDocumentContentChangeEvent) do
    include JSON::Serializable

    @[JSON::Field(key: "textDocument")]
    getter text_document : VersionedTextDocumentIdentifier

    @[JSON::Field(key: "contentChanges")]
    getter content_changes : Array(TextDocumentContentChangeEvent)
  end

  # LSP text document didSave notification params.
  record DidSaveTextDocumentParams,
    text_document : TextDocumentIdentifier,
    text : String? = nil do
    include JSON::Serializable

    @[JSON::Field(key: "textDocument")]
    getter text_document : TextDocumentIdentifier
  end

  # LSP text document didClose notification params.
  record DidCloseTextDocumentParams,
    text_document : TextDocumentIdentifier do
    include JSON::Serializable

    @[JSON::Field(key: "textDocument")]
    getter text_document : TextDocumentIdentifier
  end

  # LSP code action request context.
  record CodeActionContext,
    diagnostics : Array(Diagnostic) = [] of Diagnostic,
    only : Array(String)? = nil,
    trigger_kind : Int32? = nil do
    include JSON::Serializable

    @[JSON::Field(key: "triggerKind")]
    getter trigger_kind : Int32?
  end

  # LSP code action request params.
  record CodeActionParams,
    text_document : TextDocumentIdentifier,
    range : Range,
    context : CodeActionContext do
    include JSON::Serializable

    @[JSON::Field(key: "textDocument")]
    getter text_document : TextDocumentIdentifier
  end

  # LSP cancellation notification params.
  record CancelParams,
    id : JSON::Any do
    include JSON::Serializable
  end

  # LSP initialize request params (partial).
  record InitializeParams,
    root_uri : String? = nil do
    include JSON::Serializable

    @[JSON::Field(key: "rootUri")]
    getter root_uri : String?
  end

  # JSON-RPC request message.
  record RequestMessage,
    method : String,
    id : JSON::Any? = nil,
    params : JSON::Any? = nil do
    include JSON::Serializable
  end

  # JSON-RPC error object.
  record ResponseError,
    code : Int32,
    message : String do
    include JSON::Serializable
  end

  # JSON-RPC response message.
  record ResponseMessage,
    id : JSON::Any,
    result : JSON::Any? = nil,
    error : ResponseError? = nil do
    include JSON::Serializable

    @[JSON::Field(ignore: true)]
    getter jsonrpc = "2.0"
  end

  enum ErrorCode
    ParseError       = -32700
    InvalidRequest   = -32600
    MethodNotFound   = -32601
    InvalidParams    = -32602
    InternalError    = -32603
    RequestCancelled = -32800

    def default_message : String
      case self
      when .parse_error?
        "Parse error"
      when .invalid_request?
        "Invalid Request"
      when .method_not_found?
        "Method not found"
      when .invalid_params?
        "Invalid params"
      when .internal_error?
        "Internal error"
      when .request_cancelled?
        "Request cancelled"
      else
        "Unknown error"
      end
    end
  end

  enum PositionEncoding
    UTF8
    UTF16
    UTF32

    def to_protocol : String
      case self
      when .utf8?
        "utf-8"
      when .utf16?
        "utf-16"
      when .utf32?
        "utf-32"
      else
        raise "Unsupported position encoding: #{self}"
      end
    end

    def self.from_protocol?(value : String) : self?
      case value
      when "utf-8"
        UTF8
      when "utf-16"
        UTF16
      when "utf-32"
        UTF32
      end
    end
  end
end
