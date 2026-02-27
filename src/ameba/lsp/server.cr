require "json"

class Ameba::LSP::Server
  private class RequestCancelledError < Exception
  end

  private SUPPORTED_POSITION_ENCODINGS = {
    Ameba::LSP::Protocol::PositionEncoding::UTF8,
    Ameba::LSP::Protocol::PositionEncoding::UTF16,
    Ameba::LSP::Protocol::PositionEncoding::UTF32,
  }

  @documents = {} of String => Ameba::LSP::Document
  @diagnostics_by_uri = {} of String => Array(Ameba::LSP::Protocol::Diagnostic)
  @issues_by_uri = {} of String => Array(Ameba::Issue)
  @shutdown_requested = false
  @exit_requested = false
  @cancelled_request_ids = Set(String).new
  @position_encoding : Ameba::LSP::Protocol::PositionEncoding = Ameba::LSP::Document::DEFAULT_POSITION_ENCODING
  @analyzer : Ameba::LSP::AnalyzerProvider

  def initialize(@input : IO = STDIN, @output : IO = STDOUT, @analyzer : Ameba::LSP::AnalyzerProvider = Ameba::LSP::Analyzer.new)
  end

  def run : Nil
    until @exit_requested
      message = read_message
      break unless message
      dispatch(message)
    end
  end

  # Dispatches a parsed JSON-RPC payload.
  def dispatch(payload : JSON::Any) : Nil
    object = payload.as_h?
    return send_error(JSON::Any.new(nil), Ameba::LSP::Protocol::ErrorCode::InvalidRequest, "Invalid Request") unless object

    method_name = object["method"]?.try(&.as_s?)
    id = object["id"]?
    return send_error(id || JSON::Any.new(nil), Ameba::LSP::Protocol::ErrorCode::InvalidRequest) unless method_name
    if id && !valid_jsonrpc_id?(id)
      return send_error(JSON::Any.new(nil), Ameba::LSP::Protocol::ErrorCode::InvalidRequest)
    end
    method = Ameba::LSP::Method.parse?(method_name)

    if id
      handle_request(id, method_name, method, object["params"]?)
    else
      handle_notification(method, object["params"]?)
    end
  end

  private def handle_request(id : JSON::Any, method_name : String, method : Ameba::LSP::Method::Kind?, params : JSON::Any?) : Nil
    request_id = request_key(id)
    if request_cancelled?(request_id)
      send_error(id, Ameba::LSP::Protocol::ErrorCode::RequestCancelled)
      return
    end

    if @shutdown_requested && method != Ameba::LSP::Method::Kind::Shutdown
      send_error(id, Ameba::LSP::Protocol::ErrorCode::InvalidRequest, "Invalid request: server has been shut down")
      return
    end

    begin
      case method
      when Ameba::LSP::Method::Kind::Initialize
        set_position_encoding(params)
        send_response(id, initialize_result)
      when Ameba::LSP::Method::Kind::Shutdown
        @shutdown_requested = true
        send_response(id, JSON::Any.new(nil))
      when Ameba::LSP::Method::Kind::CodeAction
        handle_code_action(id, request_id, params)
      when Ameba::LSP::Method::Kind::CodeActionResolve
        handle_code_action_resolve(id, request_id, params)
      else
        send_error(id, Ameba::LSP::Protocol::ErrorCode::MethodNotFound, "Method not found: #{method_name}")
      end
    rescue ex : RequestCancelledError
      send_error(id, Ameba::LSP::Protocol::ErrorCode::RequestCancelled, ex.message.presence)
    ensure
      @cancelled_request_ids.delete(request_id)
    end
  end

  private def handle_notification(method : Ameba::LSP::Method::Kind?, params : JSON::Any?) : Nil
    if @shutdown_requested && method != Ameba::LSP::Method::Kind::Exit
      return
    end

    case method
    when Ameba::LSP::Method::Kind::Initialized
      nil
    when Ameba::LSP::Method::Kind::CancelRequest
      cancel_request(params)
    when Ameba::LSP::Method::Kind::Exit
      @exit_requested = true
    when Ameba::LSP::Method::Kind::DidOpen
      did_open(params)
    when Ameba::LSP::Method::Kind::DidChange
      did_change(params)
    when Ameba::LSP::Method::Kind::DidSave
      did_save(params)
    when Ameba::LSP::Method::Kind::DidClose
      did_close(params)
    end
  end

  private def cancel_request(params : JSON::Any?) : Nil
    cancel_params = parse_params(Ameba::LSP::Protocol::CancelParams, params)
    return unless cancel_params
    return unless valid_jsonrpc_id?(cancel_params.id)

    @cancelled_request_ids << request_key(cancel_params.id)
  end

  private def did_open(params : JSON::Any?) : Nil
    open_params = parse_params(Ameba::LSP::Protocol::DidOpenTextDocumentParams, params)
    return unless open_params

    text_document = open_params.text_document
    uri = text_document.uri

    @documents[uri] = Ameba::LSP::Document.new(
      uri,
      text_document.text,
      version: text_document.version,
    )
    analyze_and_publish(uri)
  end

  private def did_change(params : JSON::Any?) : Nil
    change_params = parse_params(Ameba::LSP::Protocol::DidChangeTextDocumentParams, params)
    return unless change_params

    uri = change_params.text_document.uri
    document = @documents[uri]?
    return unless document

    changes = change_params.content_changes
    return if changes.empty?

    changes.each do |change|
      document.apply_change(change, @position_encoding)
    end
    document.version = change_params.text_document.version
    analyze_and_publish(uri)
  end

  private def did_save(params : JSON::Any?) : Nil
    save_params = parse_params(Ameba::LSP::Protocol::DidSaveTextDocumentParams, params)
    return unless save_params

    uri = save_params.text_document.uri
    if text = save_params.text
      @documents[uri]?.try &.update(text)
    end

    if workspace_config_uri?(uri)
      reanalyze_workspace_for_config(uri)
      return
    end

    analyze_and_publish(uri)
  end

  private def did_close(params : JSON::Any?) : Nil
    close_params = parse_params(Ameba::LSP::Protocol::DidCloseTextDocumentParams, params)
    return unless close_params

    uri = close_params.text_document.uri
    @documents.delete(uri)
    @issues_by_uri.delete(uri)
    @diagnostics_by_uri.delete(uri)

    publish_diagnostics(uri, [] of Ameba::LSP::Protocol::Diagnostic)
  end

  private def handle_code_action(id : JSON::Any, request_id : String, params : JSON::Any?) : Nil
    request = parse_params(Ameba::LSP::Protocol::CodeActionParams, params)
    return send_error(id, Ameba::LSP::Protocol::ErrorCode::InvalidParams) unless request

    uri = request.text_document.uri
    document = @documents[uri]?
    return send_response(id, json_any([] of Ameba::LSP::Protocol::CodeAction)) unless document

    diagnostics = @diagnostics_by_uri[uri]? || [] of Ameba::LSP::Protocol::Diagnostic
    issues = @issues_by_uri[uri]? || [] of Ameba::Issue

    result = [] of Ameba::LSP::Protocol::CodeAction
    diagnostic_idx = 0

    requested_diagnostics = request.context.diagnostics

    issues.each do |issue|
      check_request_cancellation(request_id)
      next if issue.disabled?

      diagnostic = diagnostics[diagnostic_idx]?
      diagnostic_idx += 1
      next unless diagnostic
      next unless issue.correctable?
      next unless ranges_intersect?(diagnostic.range, request.range)
      next unless requested_diagnostics.empty? || includes_diagnostic?(requested_diagnostics, diagnostic)

      data = code_action_data(issue, uri, document.version)

      result << Ameba::LSP::Protocol::CodeAction.new(
        title: "Fix #{issue.rule.name}",
        diagnostics: [diagnostic],
        kind: "quickfix",
        is_preferred: true,
        data: data,
      )
    end

    send_response(id, json_any(result))
  end

  private def handle_code_action_resolve(id : JSON::Any, request_id : String, params : JSON::Any?) : Nil
    action = parse_params(Ameba::LSP::Protocol::CodeAction, params)
    return send_error(id, Ameba::LSP::Protocol::ErrorCode::InvalidParams) unless action

    data = action.data.try(&.as_h?)
    uri = data.try(&.["uri"]?).try(&.as_s?)
    version = data.try(&.["version"]?).try(&.as_i64?)
    signature = data.try(&.["signature"]?).try(&.as_h?)
    return send_response(id, JSON::Any.new(nil)) unless uri && signature

    document = @documents[uri]?
    return send_response(id, JSON::Any.new(nil)) unless document
    return send_response(id, JSON::Any.new(nil)) unless document.version == version

    check_request_cancellation(request_id)
    issue = find_issue_by_signature(@issues_by_uri[uri]? || [] of Ameba::Issue, signature)
    return send_response(id, JSON::Any.new(nil)) unless issue && document

    edits = Ameba::LSP::CodeActions.edits_for(issue, document.text)
    text_edits = edits.map do |edit|
      Ameba::LSP::Protocol::TextEdit.new(
        range: Ameba::LSP::Protocol::Range.new(
          start: document.index_to_position(edit.begin_pos, @position_encoding),
          end: document.index_to_position(edit.end_pos, @position_encoding),
        ),
        new_text: edit.replacement,
      )
    end

    resolved_action = Ameba::LSP::Protocol::CodeAction.new(
      title: action.title,
      diagnostics: action.diagnostics,
      kind: action.kind,
      is_preferred: action.is_preferred,
      data: action.data,
      edit: Ameba::LSP::Protocol::WorkspaceEdit.new(changes: {uri => text_edits}),
    )

    send_response(id, json_any(resolved_action))
  end

  private def request_key(id : JSON::Any) : String
    id.to_json
  end

  private def workspace_config_uri?(uri : String) : Bool
    parsed = URI.parse(uri)
    path = Ameba::LSP::Workspace.path_from_uri(parsed)

    Path[path].basename == Ameba::Config::Loader::FILENAME
  rescue
    false
  end

  private def reanalyze_workspace_for_config(config_uri : String) : Nil
    config_document = @documents[config_uri]?
    config_path = config_document.try(&.path)
    return unless config_path

    @documents.each do |uri, document|
      next if uri == config_uri

      workspace_root, workspace_config = Ameba::LSP::Workspace.resolve(document.path)
      next unless workspace_root && workspace_config
      next unless workspace_config == Path[config_path]

      analyze_and_publish(uri)
    end
  end

  private def valid_jsonrpc_id?(id : JSON::Any) : Bool
    !id.as_s?.nil? || !id.as_i64?.nil? || id.raw.nil?
  end

  private def request_cancelled?(request_id : String) : Bool
    @cancelled_request_ids.includes?(request_id)
  end

  private def check_request_cancellation(request_id : String) : Nil
    return unless request_cancelled?(request_id)

    raise RequestCancelledError.new("Request cancelled")
  end

  private def code_action_data(issue : Ameba::Issue, uri : String, version : Int64?) : JSON::Any
    JSON::Any.new({
      "uri"       => JSON::Any.new(uri),
      "version"   => JSON::Any.new(version),
      "signature" => issue_signature(issue),
    } of String => JSON::Any)
  end

  private def issue_signature(issue : Ameba::Issue) : JSON::Any
    location = issue.location
    end_location = issue.end_location

    JSON::Any.new({
      "rule"      => JSON::Any.new(issue.rule.name),
      "message"   => JSON::Any.new(issue.message),
      "line"      => JSON::Any.new(location.try(&.line_number.to_i64)),
      "column"    => JSON::Any.new(location.try(&.column_number.to_i64)),
      "endLine"   => JSON::Any.new(end_location.try(&.line_number.to_i64)),
      "endColumn" => JSON::Any.new(end_location.try(&.column_number.to_i64)),
    } of String => JSON::Any)
  end

  private def find_issue_by_signature(issues : Array(Ameba::Issue), signature : Hash(String, JSON::Any)) : Ameba::Issue?
    expected_rule = signature["rule"]?.try(&.as_s?)
    expected_message = signature["message"]?.try(&.as_s?)
    return unless expected_rule && expected_message

    expected_line = signature["line"]?
    expected_column = signature["column"]?
    expected_end_line = signature["endLine"]?
    expected_end_column = signature["endColumn"]?

    issues.find do |issue|
      next false unless issue.rule.name == expected_rule
      next false unless issue.message == expected_message

      location = issue.location
      end_location = issue.end_location

      signature_int_matches?(expected_line, location.try(&.line_number)) &&
        signature_int_matches?(expected_column, location.try(&.column_number)) &&
        signature_int_matches?(expected_end_line, end_location.try(&.line_number)) &&
        signature_int_matches?(expected_end_column, end_location.try(&.column_number))
    end
  end

  private def signature_int_matches?(value : JSON::Any?, issue_value : Int32?) : Bool
    return issue_value.nil? unless value
    return issue_value.nil? if value.raw.nil?

    issue_value == value.as_i?
  end

  private def analyze_and_publish(uri : String) : Nil
    document = @documents[uri]?
    return unless document

    expected_document = document
    expected_version = document.version

    workspace_root, config_path = Ameba::LSP::Workspace.resolve(document.path)
    result = @analyzer.analyze(
      document.text,
      document.path,
      config_path: config_path,
      root: workspace_root,
      cancellation_check: -> do
        current_document = @documents[uri]?
        if current_document != expected_document || current_document.try(&.version) != expected_version
          raise RequestCancelledError.new("Request cancelled")
        end
      end,
    )
    latest_document = @documents[uri]?
    return unless latest_document == expected_document
    return unless latest_document.try(&.version) == expected_version

    diagnostics = encode_diagnostics(document, result.diagnostics)

    @diagnostics_by_uri[uri] = diagnostics
    @issues_by_uri[uri] = result.issues

    publish_diagnostics(uri, diagnostics)
  rescue
    @diagnostics_by_uri[uri] = [] of Ameba::LSP::Protocol::Diagnostic
    @issues_by_uri[uri] = [] of Ameba::Issue
    publish_diagnostics(uri, [] of Ameba::LSP::Protocol::Diagnostic)
  end

  private def initialize_result : JSON::Any
    JSON.parse(
      %({"capabilities":{"textDocumentSync":2,"codeActionProvider":{"resolveProvider":true},"positionEncoding":"#{@position_encoding.to_protocol}"}})
    )
  end

  private def set_position_encoding(params : JSON::Any?) : Nil
    @position_encoding = Ameba::LSP::Document::DEFAULT_POSITION_ENCODING
    offered = offered_position_encodings(params)
    return unless offered

    @position_encoding = offered.compact_map { |value| Ameba::LSP::Protocol::PositionEncoding.from_protocol?(value) }
      .find(&.in?(SUPPORTED_POSITION_ENCODINGS)) || Ameba::LSP::Document::DEFAULT_POSITION_ENCODING
  end

  private def offered_position_encodings(params : JSON::Any?) : Array(String)?
    object = params.try &.as_h?
    capabilities = object.try(&.["capabilities"]?).try(&.as_h?)
    return unless capabilities

    if from_general = capabilities["general"]?
      if encodings = from_general.as_h?
           .try(&.["positionEncodings"]?)
           .try(&.as_a?)
        result = encodings.compact_map(&.as_s?)
        return result unless result.empty?
      end
    end

    if offset_encoding = capabilities["offsetEncoding"]?
      case
      when values = offset_encoding.as_a?
        result = values.compact_map(&.as_s?)
        return result unless result.empty?
      when value = offset_encoding.as_s?
        return [value]
      end
    end
  end

  private def encode_diagnostics(document : Ameba::LSP::Document, diagnostics : Array(Ameba::LSP::Protocol::Diagnostic)) : Array(Ameba::LSP::Protocol::Diagnostic)
    diagnostics.map do |diagnostic|
      range = diagnostic.range

      Ameba::LSP::Protocol::Diagnostic.new(
        message: diagnostic.message,
        severity: diagnostic.severity,
        range: Ameba::LSP::Protocol::Range.new(
          start: encode_position(document, range.start),
          end: encode_position(document, range.end),
        ),
      )
    end
  end

  private def encode_position(document : Ameba::LSP::Document, position : Ameba::LSP::Protocol::Position) : Ameba::LSP::Protocol::Position
    Ameba::LSP::Protocol::Position.new(
      line: position.line,
      character: document.convert_lsp_character(position.line, position.character, @position_encoding),
    )
  end

  private def publish_diagnostics(uri : String, diagnostics : Array(Ameba::LSP::Protocol::Diagnostic)) : Nil
    send_notification(
      Ameba::LSP::Method::PUBLISH_DIAGNOSTICS,
      json_any(Ameba::LSP::Protocol::PublishDiagnosticsParams.new(uri: uri, diagnostics: diagnostics)),
    )
  end

  private def send_response(id : JSON::Any, result : JSON::Any) : Nil
    body = String.build do |io|
      JSON.build(io) do |json|
        json.object do
          json.field "jsonrpc", "2.0"
          json.field "id" { id.to_json(json) }
          json.field "result" { result.to_json(json) }
        end
      end
    end

    write_frame(body)
  end

  private def send_error(id : JSON::Any, code : Ameba::LSP::Protocol::ErrorCode, message : String? = nil) : Nil
    error_message = message || code.default_message

    body = String.build do |io|
      JSON.build(io) do |json|
        json.object do
          json.field "jsonrpc", "2.0"
          json.field "id" { id.to_json(json) }
          json.field "error" do
            json.object do
              json.field "code", code.value
              json.field "message", error_message
            end
          end
        end
      end
    end

    write_frame(body)
  end

  private def send_notification(method : String, params : JSON::Any?) : Nil
    body = String.build do |io|
      JSON.build(io) do |json|
        json.object do
          json.field "jsonrpc", "2.0"
          json.field "method", method
          json.field "params" do
            if params
              params.to_json(json)
            else
              json.null
            end
          end
        end
      end
    end

    write_frame(body)
  end

  private def write_frame(body : String) : Nil
    @output << "Content-Length: " << body.bytesize << "\r\n\r\n" << body
    @output.flush
  end

  private def read_message : JSON::Any?
    headers = {} of String => String

    loop do
      line = @input.gets || return

      line = line.rstrip
      break if line.empty?

      separator_idx = line.index(':')
      return unless separator_idx

      key = line.byte_slice(0, separator_idx)
      value = line.byte_slice(separator_idx + 1, line.bytesize - separator_idx - 1) || ""
      return unless key

      headers[key.downcase] = value.lstrip
    end

    size = headers["content-length"]?.try(&.to_i?)
    return unless size
    return if size < 0

    JSON.parse(@input.read_string(size))
  rescue JSON::ParseException | IO::EOFError
    nil
  end

  private def parse_params(klass : T.class, params : JSON::Any?) : T? forall T
    return unless params
    klass.from_json(params.to_json)
  rescue
    nil
  end

  private def ranges_intersect?(lhs : Ameba::LSP::Protocol::Range, rhs : Ameba::LSP::Protocol::Range) : Bool
    range_start_before?(lhs, rhs.end) && range_start_before?(rhs, lhs.end)
  end

  private def range_start_before?(range : Ameba::LSP::Protocol::Range, position : Ameba::LSP::Protocol::Position) : Bool
    start = range.start
    start.line < position.line || (start.line == position.line && start.character < position.character)
  end

  private def includes_diagnostic?(diagnostics : Array(Ameba::LSP::Protocol::Diagnostic), target : Ameba::LSP::Protocol::Diagnostic) : Bool
    diagnostics.any? do |diagnostic|
      same_diagnostic?(diagnostic, target)
    end
  end

  private def same_diagnostic?(lhs : Ameba::LSP::Protocol::Diagnostic, rhs : Ameba::LSP::Protocol::Diagnostic) : Bool
    lhs.message == rhs.message &&
      lhs.severity == rhs.severity &&
      lhs.range == rhs.range
  end

  private def json_any(value) : JSON::Any
    JSON.parse(value.to_json)
  end
end
