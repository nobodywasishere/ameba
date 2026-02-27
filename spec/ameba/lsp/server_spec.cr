require "../../spec_helper"
require "file_utils"

module Ameba::LSP
  extend self

  private def lsp_frame(body : String) : String
    "Content-Length: #{body.bytesize}\r\n\r\n#{body}"
  end

  private def parse_lsp_frames(output : IO::Memory) : Array(JSON::Any)
    payload = output.to_s
    output.clear

    messages = [] of JSON::Any
    cursor = 0

    while header_end = payload.index("\r\n\r\n", cursor)
      header = payload[cursor...header_end]
      content_length = header.lines
        .find(&.starts_with?("Content-Length:"))
        .try(&.split(':', 2).last.strip.to_i)
      break unless content_length

      body_start = header_end + 4
      body = payload.byte_slice(body_start, content_length)
      break unless body

      messages << JSON.parse(body)
      cursor = body_start + content_length
    end

    messages
  end

  private class FakeAnalyzer
    include Ameba::LSP::AnalyzerProvider

    getter calls = [] of {String, String, String?, Path?}

    def analyze(code : String,
                path : String,
                config_path : String | Path? = nil,
                root : Path? = nil,
                cancellation_check : Proc(Nil)? = nil,
                disable_typing_noise_rules = true) : Ameba::LSP::Analyzer::Result
      @calls << {code, path, config_path.try(&.to_s), root}

      source = Ameba::Source.new(code, path)
      Ameba::AtoB.new.test(source)

      diagnostic = Ameba::LSP::Protocol::Diagnostic.new(
        message: "[Ameba/AtoB] A to B",
        range: Ameba::LSP::Protocol::Range.new(
          start: Ameba::LSP::Protocol::Position.new(0, 6),
          end: Ameba::LSP::Protocol::Position.new(0, 7),
        ),
        severity: Ameba::LSP::Protocol::DiagnosticSeverity::Warning,
      )

      Ameba::LSP::Analyzer::Result.new(
        diagnostics: [diagnostic],
        issues: source.issues.dup,
      )
    end
  end

  private class FakeAnalyzerWithDisabledIssue
    include Ameba::LSP::AnalyzerProvider

    def analyze(code : String,
                path : String,
                config_path : String | Path? = nil,
                root : Path? = nil,
                cancellation_check : Proc(Nil)? = nil,
                disable_typing_noise_rules = true) : Ameba::LSP::Analyzer::Result
      source = Ameba::Source.new(code, path)
      source.add_issue(Ameba::ErrorRule.new, location: {1, 1}, message: "disabled")
      Ameba::AtoB.new.test(source)

      diagnostic = Ameba::LSP::Protocol::Diagnostic.new(
        message: "[Ameba/AtoB] A to B",
        range: Ameba::LSP::Protocol::Range.new(
          start: Ameba::LSP::Protocol::Position.new(1, 6),
          end: Ameba::LSP::Protocol::Position.new(1, 7),
        ),
        severity: Ameba::LSP::Protocol::DiagnosticSeverity::Warning,
      )

      Ameba::LSP::Analyzer::Result.new(
        diagnostics: [diagnostic],
        issues: source.issues.dup,
      )
    end
  end

  private class FakeAnalyzerWithAstralDiagnostic
    include Ameba::LSP::AnalyzerProvider

    def analyze(code : String,
                path : String,
                config_path : String | Path? = nil,
                root : Path? = nil,
                cancellation_check : Proc(Nil)? = nil,
                disable_typing_noise_rules = true) : Ameba::LSP::Analyzer::Result
      source = Ameba::Source.new(code, path)
      Ameba::AtoB.new.test(source)

      diagnostic = Ameba::LSP::Protocol::Diagnostic.new(
        message: "[Ameba/AtoB] A to B",
        range: Ameba::LSP::Protocol::Range.new(
          # Character offsets are provided in scalar-value units.
          start: Ameba::LSP::Protocol::Position.new(0, 11),
          end: Ameba::LSP::Protocol::Position.new(0, 12),
        ),
        severity: Ameba::LSP::Protocol::DiagnosticSeverity::Warning,
      )

      Ameba::LSP::Analyzer::Result.new(
        diagnostics: [diagnostic],
        issues: source.issues.dup,
      )
    end
  end

  private class FakeAnalyzerWithCancellationCheck
    include Ameba::LSP::AnalyzerProvider

    getter? cancellation_check_received = false

    def analyze(code : String,
                path : String,
                config_path : String | Path? = nil,
                root : Path? = nil,
                cancellation_check : Proc(Nil)? = nil,
                disable_typing_noise_rules = true) : Ameba::LSP::Analyzer::Result
      @cancellation_check_received = !cancellation_check.nil?
      cancellation_check.try &.call

      Ameba::LSP::Analyzer::Result.new(
        diagnostics: [] of Ameba::LSP::Protocol::Diagnostic,
        issues: [] of Ameba::Issue,
      )
    end
  end

  def self.with_tmpdir(prefix : String, & : Path ->)
    path = Path[Dir.tempdir, "#{prefix}-#{Random::Secure.hex(6)}"]
    Dir.mkdir_p(path)

    begin
      yield path
    ensure
      FileUtils.rm_r(path) if Dir.exists?(path)
    end
  end

  describe Server do
    it "processes stdio-framed initialize/shutdown requests" do
      input = IO::Memory.new(
        lsp_frame(%({"jsonrpc":"2.0","id":1,"method":"initialize","params":{}})) +
        lsp_frame(%({"jsonrpc":"2.0","id":2,"method":"shutdown","params":null})) +
        lsp_frame(%({"jsonrpc":"2.0","method":"exit","params":null}))
      )
      output = IO::Memory.new
      server = Server.new(input, output, FakeAnalyzer.new)

      server.run
      messages = parse_lsp_frames(output)

      messages.size.should eq 2
      messages[0]["id"].as_i.should eq 1
      messages[0]["result"]["capabilities"]["textDocumentSync"].as_i.should eq 2
      messages[0]["result"]["capabilities"]["positionEncoding"].as_s.should eq Protocol::PositionEncoding::UTF16.to_protocol
      messages[1]["id"].as_i.should eq 2
      messages[1]["result"].raw.should be_nil
    end

    it "rejects requests after shutdown" do
      input = IO::Memory.new(
        lsp_frame(%({"jsonrpc":"2.0","id":1,"method":"initialize","params":{}})) +
        lsp_frame(%({"jsonrpc":"2.0","id":2,"method":"shutdown","params":null})) +
        lsp_frame(%({"jsonrpc":"2.0","id":3,"method":"textDocument/codeAction","params":{"textDocument":{"uri":"file:///tmp/a.cr"},"range":{"start":{"line":0,"character":0},"end":{"line":0,"character":0}},"context":{"diagnostics":[]}}})) +
        lsp_frame(%({"jsonrpc":"2.0","method":"exit","params":null}))
      )
      output = IO::Memory.new
      server = Server.new(input, output, FakeAnalyzer.new)

      server.run
      messages = parse_lsp_frames(output)

      messages.size.should eq 3
      messages[2]["id"].as_i.should eq 3
      messages[2]["error"]["code"].as_i.should eq Protocol::ErrorCode::InvalidRequest.value
    end

    it "returns request cancelled for cancelled request ids" do
      input = IO::Memory.new(
        lsp_frame(%({"jsonrpc":"2.0","method":"$/cancelRequest","params":{"id":41}})) +
        lsp_frame(%({"jsonrpc":"2.0","id":41,"method":"initialize","params":{}})) +
        lsp_frame(%({"jsonrpc":"2.0","method":"exit","params":null}))
      )
      output = IO::Memory.new
      server = Server.new(input, output, FakeAnalyzer.new)

      server.run
      messages = parse_lsp_frames(output)

      messages.size.should eq 1
      messages[0]["id"].as_i.should eq 41
      messages[0]["error"]["code"].as_i.should eq Protocol::ErrorCode::RequestCancelled.value
    end

    it "does not cancel numeric request when cancellation id is string" do
      input = IO::Memory.new(
        lsp_frame(%({"jsonrpc":"2.0","method":"$/cancelRequest","params":{"id":"41"}})) +
        lsp_frame(%({"jsonrpc":"2.0","id":41,"method":"initialize","params":{}})) +
        lsp_frame(%({"jsonrpc":"2.0","method":"exit","params":null}))
      )
      output = IO::Memory.new
      server = Server.new(input, output, FakeAnalyzer.new)

      server.run
      messages = parse_lsp_frames(output)

      messages.size.should eq 1
      messages[0]["id"].as_i.should eq 41
      messages[0]["result"]["capabilities"]["positionEncoding"].as_s.should eq Protocol::PositionEncoding::UTF16.to_protocol
    end

    it "does not cancel string request when cancellation id is numeric" do
      input = IO::Memory.new(
        lsp_frame(%({"jsonrpc":"2.0","method":"$/cancelRequest","params":{"id":41}})) +
        lsp_frame(%({"jsonrpc":"2.0","id":"41","method":"initialize","params":{}})) +
        lsp_frame(%({"jsonrpc":"2.0","method":"exit","params":null}))
      )
      output = IO::Memory.new
      server = Server.new(input, output, FakeAnalyzer.new)

      server.run
      messages = parse_lsp_frames(output)

      messages.size.should eq 1
      messages[0]["id"].as_s.should eq "41"
      messages[0]["result"]["capabilities"]["positionEncoding"].as_s.should eq Protocol::PositionEncoding::UTF16.to_protocol
    end

    it "ignores malformed cancelRequest payloads" do
      input = IO::Memory.new(
        lsp_frame(%({"jsonrpc":"2.0","method":"$/cancelRequest","params":{"id":{"bad":true}}})) +
        lsp_frame(%({"jsonrpc":"2.0","id":41,"method":"initialize","params":{}})) +
        lsp_frame(%({"jsonrpc":"2.0","method":"exit","params":null}))
      )
      output = IO::Memory.new
      server = Server.new(input, output, FakeAnalyzer.new)

      server.run
      messages = parse_lsp_frames(output)

      messages.size.should eq 1
      messages[0]["id"].as_i.should eq 41
      messages[0]["result"]["capabilities"]["textDocumentSync"].as_i.should eq 2
    end

    it "ignores notifications after shutdown except exit" do
      analyzer = FakeAnalyzer.new
      input = IO::Memory.new(
        lsp_frame(%({"jsonrpc":"2.0","id":1,"method":"shutdown","params":null})) +
        lsp_frame(%({"jsonrpc":"2.0","method":"textDocument/didOpen","params":{"textDocument":{"uri":"file:///tmp/ignored.cr","languageId":"crystal","version":1,"text":"class A; end\n"}}})) +
        lsp_frame(%({"jsonrpc":"2.0","method":"exit","params":null}))
      )
      output = IO::Memory.new
      server = Server.new(input, output, analyzer)

      server.run
      messages = parse_lsp_frames(output)

      messages.size.should eq 1
      analyzer.calls.should be_empty
    end

    it "returns method not found for unknown requests" do
      input = IO::Memory.new(
        lsp_frame(%({"jsonrpc":"2.0","id":50,"method":"workspace/unknown","params":{}})) +
        lsp_frame(%({"jsonrpc":"2.0","method":"exit","params":null}))
      )
      output = IO::Memory.new
      server = Server.new(input, output, FakeAnalyzer.new)

      server.run
      messages = parse_lsp_frames(output)

      messages.size.should eq 1
      messages[0]["id"].as_i.should eq 50
      messages[0]["error"]["code"].as_i.should eq Protocol::ErrorCode::MethodNotFound.value
    end

    it "returns invalid request when request method is missing" do
      output = IO::Memory.new
      server = Server.new(IO::Memory.new, output, FakeAnalyzer.new)

      server.dispatch(JSON.parse(%({"jsonrpc":"2.0","id":55,"params":{}})))

      message = parse_lsp_frames(output).first
      message["id"].as_i.should eq 55
      message["error"]["code"].as_i.should eq Protocol::ErrorCode::InvalidRequest.value
    end

    it "returns invalid request for non-object payloads" do
      output = IO::Memory.new
      server = Server.new(IO::Memory.new, output, FakeAnalyzer.new)

      server.dispatch(JSON.parse(%(["invalid"])))

      message = parse_lsp_frames(output).first
      message["id"].raw.should be_nil
      message["error"]["code"].as_i.should eq Protocol::ErrorCode::InvalidRequest.value
    end

    it "returns invalid request for object request ids" do
      output = IO::Memory.new
      server = Server.new(IO::Memory.new, output, FakeAnalyzer.new)

      server.dispatch(JSON.parse(%({"jsonrpc":"2.0","id":{"bad":true},"method":"initialize","params":{}})))

      message = parse_lsp_frames(output).first
      message["id"].raw.should be_nil
      message["error"]["code"].as_i.should eq Protocol::ErrorCode::InvalidRequest.value
    end

    it "returns invalid request for array request ids" do
      output = IO::Memory.new
      server = Server.new(IO::Memory.new, output, FakeAnalyzer.new)

      server.dispatch(JSON.parse(%({"jsonrpc":"2.0","id":[1],"method":"initialize","params":{}})))

      message = parse_lsp_frames(output).first
      message["id"].raw.should be_nil
      message["error"]["code"].as_i.should eq Protocol::ErrorCode::InvalidRequest.value
    end

    it "returns invalid params for malformed code action request" do
      output = IO::Memory.new
      server = Server.new(IO::Memory.new, output, FakeAnalyzer.new)

      server.dispatch(JSON.parse(%({"jsonrpc":"2.0","id":51,"method":"textDocument/codeAction","params":{"bad":true}})))

      message = parse_lsp_frames(output).first
      message["id"].as_i.should eq 51
      message["error"]["code"].as_i.should eq Protocol::ErrorCode::InvalidParams.value
    end

    it "returns invalid params for malformed code action resolve request" do
      output = IO::Memory.new
      server = Server.new(IO::Memory.new, output, FakeAnalyzer.new)

      server.dispatch(JSON.parse(%({"jsonrpc":"2.0","id":52,"method":"codeAction/resolve","params":{"bad":true}})))

      message = parse_lsp_frames(output).first
      message["id"].as_i.should eq 52
      message["error"]["code"].as_i.should eq Protocol::ErrorCode::InvalidParams.value
    end

    it "stops processing when a malformed frame is read" do
      invalid_body = %({"jsonrpc":"2.0","id":1,"method":"initialize","params":)
      input = IO::Memory.new(
        lsp_frame(invalid_body) +
        lsp_frame(%({"jsonrpc":"2.0","id":2,"method":"shutdown","params":null}))
      )
      output = IO::Memory.new
      server = Server.new(input, output, FakeAnalyzer.new)

      server.run
      parse_lsp_frames(output).should be_empty
    end

    it "stops processing when a header line is malformed" do
      input = IO::Memory.new(
        "Content-Length 10\r\n\r\n{}\r\n" +
        lsp_frame(%({"jsonrpc":"2.0","id":56,"method":"initialize","params":{}}))
      )
      output = IO::Memory.new
      server = Server.new(input, output, FakeAnalyzer.new)

      server.run
      parse_lsp_frames(output).should be_empty
    end

    it "stops processing when content length header is invalid" do
      input = IO::Memory.new(
        "Content-Length: abc\r\n\r\n" +
        lsp_frame(%({"jsonrpc":"2.0","id":57,"method":"initialize","params":{}}))
      )
      output = IO::Memory.new
      server = Server.new(input, output, FakeAnalyzer.new)

      server.run
      parse_lsp_frames(output).should be_empty
    end

    it "handles didOpen/didChange/didSave/didClose lifecycle" do
      analyzer = FakeAnalyzer.new
      output = IO::Memory.new
      server = Server.new(IO::Memory.new, output, analyzer)

      Ameba::LSP.with_tmpdir("ameba-lsp-server") do |root|
        source_path = root / "src" / "foo.cr"
        uri = "file://#{source_path}"

        Dir.mkdir_p(source_path.parent)
        File.write(root / "shard.yml", "name: sample\nversion: 0.1.0\n")
        File.write(root / Ameba::Config::Loader::FILENAME, "{}")

        server.dispatch(JSON.parse(<<-JSON
          {
            "jsonrpc":"2.0",
            "method":"textDocument/didOpen",
            "params":{
              "textDocument":{
                "uri":"#{uri}",
                "languageId":"crystal",
                "version":1,
                "text":"class A; end\\n"
              }
            }
          }
          JSON
        ))
        messages = parse_lsp_frames(output)
        messages.size.should eq 1
        messages[0]["method"].as_s.should eq Ameba::LSP::Method::PUBLISH_DIAGNOSTICS
        messages[0]["params"]["diagnostics"].as_a.size.should eq 1

        server.dispatch(JSON.parse(<<-JSON
          {
            "jsonrpc":"2.0",
            "method":"textDocument/didChange",
            "params":{
              "textDocument":{"uri":"#{uri}","version":2},
              "contentChanges":[{"text":"class A; end\\n"}]
            }
          }
          JSON
        ))
        parse_lsp_frames(output).first["params"]["diagnostics"].as_a.size.should eq 1

        server.dispatch(JSON.parse(<<-JSON
          {
            "jsonrpc":"2.0",
            "method":"textDocument/didSave",
            "params":{"textDocument":{"uri":"#{uri}"}}
          }
          JSON
        ))
        parse_lsp_frames(output).first["params"]["diagnostics"].as_a.size.should eq 1

        server.dispatch(JSON.parse(<<-JSON
          {
            "jsonrpc":"2.0",
            "method":"textDocument/didClose",
            "params":{"textDocument":{"uri":"#{uri}"}}
          }
          JSON
        ))
        parse_lsp_frames(output).first["params"]["diagnostics"].as_a.should be_empty

        analyzer.calls.first[2].should eq (root / Ameba::Config::Loader::FILENAME).to_s
        analyzer.calls.first[3].should eq root
      end
    end

    it "reanalyzes open documents when workspace .ameba.yml is saved" do
      analyzer = FakeAnalyzer.new
      output = IO::Memory.new
      server = Server.new(IO::Memory.new, output, analyzer)

      Ameba::LSP.with_tmpdir("ameba-lsp-config-save") do |root|
        source_path = root / "src" / "foo.cr"
        source_uri = "file://#{source_path}"
        config_path = root / Ameba::Config::Loader::FILENAME
        config_uri = "file://#{config_path}"

        Dir.mkdir_p(source_path.parent)
        File.write(root / "shard.yml", "name: sample\nversion: 0.1.0\n")
        File.write(config_path, "{}\n")

        server.dispatch(JSON.parse(<<-JSON
          {
            "jsonrpc":"2.0",
            "method":"textDocument/didOpen",
            "params":{
              "textDocument":{
                "uri":"#{source_uri}",
                "languageId":"crystal",
                "version":1,
                "text":"class A; end\\n"
              }
            }
          }
          JSON
        ))
        parse_lsp_frames(output)
        analyzer.calls.size.should eq 1

        server.dispatch(JSON.parse(<<-JSON
          {
            "jsonrpc":"2.0",
            "method":"textDocument/didOpen",
            "params":{
              "textDocument":{
                "uri":"#{config_uri}",
                "languageId":"yaml",
                "version":1,
                "text":"{}\\n"
              }
            }
          }
          JSON
        ))
        parse_lsp_frames(output)
        analyzer.calls.size.should eq 2

        server.dispatch(JSON.parse(<<-JSON
          {
            "jsonrpc":"2.0",
            "method":"textDocument/didSave",
            "params":{"textDocument":{"uri":"#{config_uri}"}}
          }
          JSON
        ))
        parse_lsp_frames(output).size.should eq 1
        analyzer.calls.size.should eq 3
        analyzer.calls.last[1].should eq source_path.to_s
      end
    end

    it "applies ranged didChange updates" do
      analyzer = FakeAnalyzer.new
      output = IO::Memory.new
      server = Server.new(IO::Memory.new, output, analyzer)
      uri = "file:///tmp/sample-range.cr"

      server.dispatch(JSON.parse(<<-JSON
        {
          "jsonrpc":"2.0",
          "method":"textDocument/didOpen",
          "params":{
            "textDocument":{
              "uri":"#{uri}",
              "languageId":"crystal",
              "version":1,
              "text":"class Z; end\\n"
            }
          }
        }
        JSON
      ))
      parse_lsp_frames(output)
      analyzer.calls.last[0].should eq "class Z; end\n"

      server.dispatch(JSON.parse(<<-JSON
        {
          "jsonrpc":"2.0",
          "method":"textDocument/didChange",
          "params":{
            "textDocument":{"uri":"#{uri}","version":2},
            "contentChanges":[
              {
                "range":{
                  "start":{"line":0,"character":6},
                  "end":{"line":0,"character":7}
                },
                "rangeLength":1,
                "text":"A"
              }
            ]
          }
        }
        JSON
      ))
      parse_lsp_frames(output)
      analyzer.calls.last[0].should eq "class A; end\n"

      server.dispatch(JSON.parse(<<-JSON
        {
          "jsonrpc":"2.0",
          "id":23,
          "method":"textDocument/codeAction",
          "params":{
            "textDocument":{"uri":"#{uri}"},
            "range":{"start":{"line":0,"character":6},"end":{"line":0,"character":7}},
            "context":{"diagnostics":[]}
          }
        }
        JSON
      ))
      parse_lsp_frames(output).first["result"].as_a.size.should eq 1
    end

    it "applies utf-8 ranged didChange updates when negotiated" do
      analyzer = FakeAnalyzer.new
      output = IO::Memory.new
      server = Server.new(IO::Memory.new, output, analyzer)
      uri = "file:///tmp/sample-range-utf8.cr"

      server.dispatch(JSON.parse(<<-JSON
        {
          "jsonrpc":"2.0",
          "id":24,
          "method":"initialize",
          "params":{
            "capabilities":{
              "general":{"positionEncodings":["utf-8"]}
            }
          }
        }
        JSON
      ))
      parse_lsp_frames(output)

      server.dispatch(JSON.parse(<<-JSON
        {
          "jsonrpc":"2.0",
          "method":"textDocument/didOpen",
          "params":{
            "textDocument":{
              "uri":"#{uri}",
              "languageId":"crystal",
              "version":1,
              "text":"\\"😀\\"; class Z; end\\n"
            }
          }
        }
        JSON
      ))
      parse_lsp_frames(output)

      server.dispatch(JSON.parse(<<-JSON
        {
          "jsonrpc":"2.0",
          "method":"textDocument/didChange",
          "params":{
            "textDocument":{"uri":"#{uri}","version":2},
            "contentChanges":[
              {
                "range":{
                  "start":{"line":0,"character":14},
                  "end":{"line":0,"character":15}
                },
                "rangeLength":1,
                "text":"A"
              }
            ]
          }
        }
        JSON
      ))
      parse_lsp_frames(output)
      analyzer.calls.last[0].should eq "\"😀\"; class A; end\n"
    end

    it "returns and resolves code actions" do
      analyzer = FakeAnalyzer.new
      output = IO::Memory.new
      server = Server.new(IO::Memory.new, output, analyzer)
      uri = "file:///tmp/sample.cr"

      server.dispatch(JSON.parse(<<-JSON
        {
          "jsonrpc":"2.0",
          "method":"textDocument/didOpen",
          "params":{
            "textDocument":{
              "uri":"#{uri}",
              "languageId":"crystal",
              "version":1,
              "text":"class A; end\\n"
            }
          }
        }
        JSON
      ))
      parse_lsp_frames(output)

      server.dispatch(JSON.parse(<<-JSON
        {
          "jsonrpc":"2.0",
          "id":7,
          "method":"textDocument/codeAction",
          "params":{
            "textDocument":{"uri":"#{uri}"},
            "range":{"start":{"line":0,"character":6},"end":{"line":0,"character":7}},
            "context":{"diagnostics":[]}
          }
        }
        JSON
      ))
      code_action_response = parse_lsp_frames(output).first
      code_actions = code_action_response["result"].as_a
      code_actions.should_not be_empty

      action = code_actions.first
      server.dispatch(JSON.parse(<<-JSON
        {
          "jsonrpc":"2.0",
          "id":8,
          "method":"codeAction/resolve",
          "params":#{action.to_json}
        }
        JSON
      ))

      resolve_response = parse_lsp_frames(output).first
      edits = resolve_response["result"]["edit"]["changes"][uri].as_a
      edits.size.should eq 1
      edits.first["newText"].as_s.should eq "B"
    end

    it "filters code actions by request range and diagnostics" do
      analyzer = FakeAnalyzer.new
      output = IO::Memory.new
      server = Server.new(IO::Memory.new, output, analyzer)
      uri = "file:///tmp/sample-filter.cr"

      server.dispatch(JSON.parse(<<-JSON
        {
          "jsonrpc":"2.0",
          "method":"textDocument/didOpen",
          "params":{
            "textDocument":{
              "uri":"#{uri}",
              "languageId":"crystal",
              "version":1,
              "text":"class A; end\\n"
            }
          }
        }
        JSON
      ))
      diagnostics = parse_lsp_frames(output).first["params"]["diagnostics"].as_a
      diagnostic = diagnostics.first
      mismatched_diagnostic = diagnostic.to_json.sub("[Ameba/AtoB] A to B", "different")

      server.dispatch(JSON.parse(<<-JSON
        {
          "jsonrpc":"2.0",
          "id":32,
          "method":"textDocument/codeAction",
          "params":{
            "textDocument":{"uri":"#{uri}"},
            "range":{"start":{"line":1,"character":0},"end":{"line":1,"character":1}},
            "context":{"diagnostics":[]}
          }
        }
        JSON
      ))
      parse_lsp_frames(output).first["result"].as_a.should be_empty

      server.dispatch(JSON.parse(<<-JSON
        {
          "jsonrpc":"2.0",
          "id":33,
          "method":"textDocument/codeAction",
          "params":{
            "textDocument":{"uri":"#{uri}"},
            "range":{"start":{"line":0,"character":0},"end":{"line":0,"character":10}},
            "context":{
              "diagnostics":[#{mismatched_diagnostic}]
            }
          }
        }
        JSON
      ))
      parse_lsp_frames(output).first["result"].as_a.should be_empty

      server.dispatch(JSON.parse(<<-JSON
        {
          "jsonrpc":"2.0",
          "id":34,
          "method":"textDocument/codeAction",
          "params":{
            "textDocument":{"uri":"#{uri}"},
            "range":{"start":{"line":0,"character":0},"end":{"line":0,"character":10}},
            "context":{"diagnostics":[#{diagnostic.to_json}]}
          }
        }
        JSON
      ))
      parse_lsp_frames(output).first["result"].as_a.size.should eq 1
    end

    it "rejects stale code action resolve requests after document changes" do
      analyzer = FakeAnalyzer.new
      output = IO::Memory.new
      server = Server.new(IO::Memory.new, output, analyzer)
      uri = "file:///tmp/sample-stale.cr"

      server.dispatch(JSON.parse(<<-JSON
        {
          "jsonrpc":"2.0",
          "method":"textDocument/didOpen",
          "params":{
            "textDocument":{
              "uri":"#{uri}",
              "languageId":"crystal",
              "version":1,
              "text":"class A; end\\n"
            }
          }
        }
        JSON
      ))
      parse_lsp_frames(output)

      server.dispatch(JSON.parse(<<-JSON
        {
          "jsonrpc":"2.0",
          "id":30,
          "method":"textDocument/codeAction",
          "params":{
            "textDocument":{"uri":"#{uri}"},
            "range":{"start":{"line":0,"character":0},"end":{"line":0,"character":100}},
            "context":{"diagnostics":[]}
          }
        }
        JSON
      ))
      stale_action = parse_lsp_frames(output).first["result"].as_a.first

      server.dispatch(JSON.parse(<<-JSON
        {
          "jsonrpc":"2.0",
          "method":"textDocument/didChange",
          "params":{
            "textDocument":{"uri":"#{uri}","version":2},
            "contentChanges":[{"text":"class A; end\\n"}]
          }
        }
        JSON
      ))
      parse_lsp_frames(output)

      server.dispatch(JSON.parse(<<-JSON
        {
          "jsonrpc":"2.0",
          "id":31,
          "method":"codeAction/resolve",
          "params":#{stale_action.to_json}
        }
        JSON
      ))

      response = parse_lsp_frames(output).first
      response["result"].raw.should be_nil
    end

    it "resolves code actions with signature data after non-correctable issues" do
      output = IO::Memory.new
      server = Server.new(IO::Memory.new, output, FakeAnalyzerWithDisabledIssue.new)
      uri = "file:///tmp/sample-signature.cr"

      server.dispatch(JSON.parse(<<-JSON
        {
          "jsonrpc":"2.0",
          "method":"textDocument/didOpen",
          "params":{
            "textDocument":{
              "uri":"#{uri}",
              "languageId":"crystal",
              "version":1,
              "text":"# ameba:disable Ameba/ErrorRule\\nclass A; end\\n"
            }
          }
        }
        JSON
      ))
      parse_lsp_frames(output)

      server.dispatch(JSON.parse(<<-JSON
        {
          "jsonrpc":"2.0",
          "id":53,
          "method":"textDocument/codeAction",
          "params":{
            "textDocument":{"uri":"#{uri}"},
            "range":{"start":{"line":1,"character":6},"end":{"line":1,"character":7}},
            "context":{"diagnostics":[]}
          }
        }
        JSON
      ))
      action = parse_lsp_frames(output).first["result"].as_a.first
      action["data"]["signature"]["rule"].as_s.should eq "Ameba/AtoB"

      server.dispatch(JSON.parse(<<-JSON
        {
          "jsonrpc":"2.0",
          "id":54,
          "method":"codeAction/resolve",
          "params":#{action.to_json}
        }
        JSON
      ))

      resolve_response = parse_lsp_frames(output).first
      edits = resolve_response["result"]["edit"]["changes"][uri].as_a
      edits.size.should eq 1
      edits.first["newText"].as_s.should eq "B"
    end

    it "uses utf-16 edit ranges by default" do
      output = IO::Memory.new
      server = Server.new(IO::Memory.new, output, FakeAnalyzer.new)
      uri = "file:///tmp/sample-utf16.cr"

      server.dispatch(JSON.parse(<<-JSON
        {
          "jsonrpc":"2.0",
          "method":"textDocument/didOpen",
          "params":{
            "textDocument":{
              "uri":"#{uri}",
              "languageId":"crystal",
              "version":1,
              "text":"\\"😀\\"; class A; end\\n"
            }
          }
        }
        JSON
      ))
      parse_lsp_frames(output)

      server.dispatch(JSON.parse(<<-JSON
        {
          "jsonrpc":"2.0",
          "id":11,
          "method":"textDocument/codeAction",
          "params":{
            "textDocument":{"uri":"#{uri}"},
            "range":{"start":{"line":0,"character":0},"end":{"line":0,"character":100}},
            "context":{"diagnostics":[]}
          }
        }
        JSON
      ))
      action = parse_lsp_frames(output).first["result"].as_a.first

      server.dispatch(JSON.parse(<<-JSON
        {
          "jsonrpc":"2.0",
          "id":12,
          "method":"codeAction/resolve",
          "params":#{action.to_json}
        }
        JSON
      ))

      edit_range = parse_lsp_frames(output).first["result"]["edit"]["changes"][uri].as_a.first["range"]
      edit_range["start"]["character"].as_i.should eq 12
      edit_range["end"]["character"].as_i.should eq 13
    end

    it "publishes diagnostics using utf-16 columns by default" do
      output = IO::Memory.new
      server = Server.new(IO::Memory.new, output, FakeAnalyzerWithAstralDiagnostic.new)
      uri = "file:///tmp/sample-diagnostic-utf16.cr"

      server.dispatch(JSON.parse(<<-JSON
        {
          "jsonrpc":"2.0",
          "method":"textDocument/didOpen",
          "params":{
            "textDocument":{
              "uri":"#{uri}",
              "languageId":"crystal",
              "version":1,
              "text":"\\"😀\\"; class A; end\\n"
            }
          }
        }
        JSON
      ))

      diagnostics = parse_lsp_frames(output).first["params"]["diagnostics"].as_a
      range = diagnostics.first["range"]
      range["start"]["character"].as_i.should eq 12
      range["end"]["character"].as_i.should eq 13
    end

    it "negotiates utf-8 edit ranges when client requests utf-8" do
      output = IO::Memory.new
      server = Server.new(IO::Memory.new, output, FakeAnalyzer.new)
      uri = "file:///tmp/sample-utf8.cr"

      server.dispatch(JSON.parse(<<-JSON
        {
          "jsonrpc":"2.0",
          "id":20,
          "method":"initialize",
          "params":{
            "capabilities":{
              "general":{"positionEncodings":["utf-8"]}
            }
          }
        }
        JSON
      ))
      initialize_response = parse_lsp_frames(output).first
      initialize_response["result"]["capabilities"]["positionEncoding"].as_s.should eq Protocol::PositionEncoding::UTF8.to_protocol

      server.dispatch(JSON.parse(<<-JSON
        {
          "jsonrpc":"2.0",
          "method":"textDocument/didOpen",
          "params":{
            "textDocument":{
              "uri":"#{uri}",
              "languageId":"crystal",
              "version":1,
              "text":"\\"😀\\"; class A; end\\n"
            }
          }
        }
        JSON
      ))
      parse_lsp_frames(output)

      server.dispatch(JSON.parse(<<-JSON
        {
          "jsonrpc":"2.0",
          "id":21,
          "method":"textDocument/codeAction",
          "params":{
            "textDocument":{"uri":"#{uri}"},
            "range":{"start":{"line":0,"character":0},"end":{"line":0,"character":100}},
            "context":{"diagnostics":[]}
          }
        }
        JSON
      ))
      action = parse_lsp_frames(output).first["result"].as_a.first

      server.dispatch(JSON.parse(<<-JSON
        {
          "jsonrpc":"2.0",
          "id":22,
          "method":"codeAction/resolve",
          "params":#{action.to_json}
        }
        JSON
      ))

      edit_range = parse_lsp_frames(output).first["result"]["edit"]["changes"][uri].as_a.first["range"]
      edit_range["start"]["character"].as_i.should eq 14
      edit_range["end"]["character"].as_i.should eq 15
    end

    it "negotiates utf-32 edit ranges when client requests utf-32" do
      output = IO::Memory.new
      server = Server.new(IO::Memory.new, output, FakeAnalyzer.new)
      uri = "file:///tmp/sample-utf32.cr"

      server.dispatch(JSON.parse(<<-JSON
        {
          "jsonrpc":"2.0",
          "id":40,
          "method":"initialize",
          "params":{
            "capabilities":{
              "general":{"positionEncodings":["utf-32"]}
            }
          }
        }
        JSON
      ))
      initialize_response = parse_lsp_frames(output).first
      initialize_response["result"]["capabilities"]["positionEncoding"].as_s.should eq Protocol::PositionEncoding::UTF32.to_protocol

      server.dispatch(JSON.parse(<<-JSON
        {
          "jsonrpc":"2.0",
          "method":"textDocument/didOpen",
          "params":{
            "textDocument":{
              "uri":"#{uri}",
              "languageId":"crystal",
              "version":1,
              "text":"\\"😀\\"; class A; end\\n"
            }
          }
        }
        JSON
      ))
      parse_lsp_frames(output)

      server.dispatch(JSON.parse(<<-JSON
        {
          "jsonrpc":"2.0",
          "id":41,
          "method":"textDocument/codeAction",
          "params":{
            "textDocument":{"uri":"#{uri}"},
            "range":{"start":{"line":0,"character":6},"end":{"line":0,"character":7}},
            "context":{"diagnostics":[]}
          }
        }
        JSON
      ))
      action = parse_lsp_frames(output).first["result"].as_a.first

      server.dispatch(JSON.parse(<<-JSON
        {
          "jsonrpc":"2.0",
          "id":42,
          "method":"codeAction/resolve",
          "params":#{action.to_json}
        }
        JSON
      ))

      edit_range = parse_lsp_frames(output).first["result"]["edit"]["changes"][uri].as_a.first["range"]
      edit_range["start"]["character"].as_i.should eq 11
      edit_range["end"]["character"].as_i.should eq 12
    end

    it "falls back to utf-16 when client offers unsupported position encodings" do
      output = IO::Memory.new
      server = Server.new(IO::Memory.new, output, FakeAnalyzer.new)

      server.dispatch(JSON.parse(<<-JSON
        {
          "jsonrpc":"2.0",
          "id":44,
          "method":"initialize",
          "params":{
            "capabilities":{
              "general":{"positionEncodings":["utf-7","utf-1"]}
            }
          }
        }
        JSON
      ))

      initialize_response = parse_lsp_frames(output).first
      initialize_response["result"]["capabilities"]["positionEncoding"].as_s.should eq Protocol::PositionEncoding::UTF16.to_protocol
    end

    it "publishes diagnostics using utf-32 columns when negotiated" do
      output = IO::Memory.new
      server = Server.new(IO::Memory.new, output, FakeAnalyzerWithAstralDiagnostic.new)
      uri = "file:///tmp/sample-diagnostic-utf32.cr"

      server.dispatch(JSON.parse(<<-JSON
        {
          "jsonrpc":"2.0",
          "id":43,
          "method":"initialize",
          "params":{
            "capabilities":{
              "general":{"positionEncodings":["utf-32"]}
            }
          }
        }
        JSON
      ))
      parse_lsp_frames(output)

      server.dispatch(JSON.parse(<<-JSON
        {
          "jsonrpc":"2.0",
          "method":"textDocument/didOpen",
          "params":{
            "textDocument":{
              "uri":"#{uri}",
              "languageId":"crystal",
              "version":1,
              "text":"\\"😀\\"; class A; end\\n"
            }
          }
        }
        JSON
      ))

      diagnostics = parse_lsp_frames(output).first["params"]["diagnostics"].as_a
      range = diagnostics.first["range"]
      range["start"]["character"].as_i.should eq 11
      range["end"]["character"].as_i.should eq 12
    end

    it "passes cancellation checks into analyzer for document analysis" do
      analyzer = FakeAnalyzerWithCancellationCheck.new
      output = IO::Memory.new
      server = Server.new(IO::Memory.new, output, analyzer)
      uri = "file:///tmp/sample-cancel-check.cr"

      server.dispatch(JSON.parse(<<-JSON
        {
          "jsonrpc":"2.0",
          "method":"textDocument/didOpen",
          "params":{
            "textDocument":{
              "uri":"#{uri}",
              "languageId":"crystal",
              "version":1,
              "text":"class A; end\\n"
            }
          }
        }
        JSON
      ))

      parse_lsp_frames(output).first["method"].as_s.should eq Ameba::LSP::Method::PUBLISH_DIAGNOSTICS
      analyzer.cancellation_check_received?.should be_true
    end

    it "handles initialize open codeAction resolve and stale resolve end-to-end" do
      analyzer = FakeAnalyzer.new
      output = IO::Memory.new
      server = Server.new(IO::Memory.new, output, analyzer)
      uri = "file:///tmp/e2e-sample.cr"

      server.dispatch(JSON.parse(<<-JSON
        {
          "jsonrpc":"2.0",
          "id":80,
          "method":"#{Ameba::LSP::Method::INITIALIZE}",
          "params":{
            "capabilities":{
              "general":{"positionEncodings":["utf-8"]}
            }
          }
        }
        JSON
      ))
      initialize_response = parse_lsp_frames(output).first
      initialize_response["result"]["capabilities"]["positionEncoding"].as_s.should eq Protocol::PositionEncoding::UTF8.to_protocol

      server.dispatch(JSON.parse(<<-JSON
        {
          "jsonrpc":"2.0",
          "method":"#{Ameba::LSP::Method::DID_OPEN}",
          "params":{
            "textDocument":{
              "uri":"#{uri}",
              "languageId":"crystal",
              "version":1,
              "text":"class A; end\\n"
            }
          }
        }
        JSON
      ))
      publish = parse_lsp_frames(output).first
      publish["method"].as_s.should eq Ameba::LSP::Method::PUBLISH_DIAGNOSTICS

      server.dispatch(JSON.parse(<<-JSON
        {
          "jsonrpc":"2.0",
          "id":81,
          "method":"#{Ameba::LSP::Method::CODE_ACTION}",
          "params":{
            "textDocument":{"uri":"#{uri}"},
            "range":{"start":{"line":0,"character":0},"end":{"line":0,"character":100}},
            "context":{"diagnostics":[]}
          }
        }
        JSON
      ))
      action = parse_lsp_frames(output).first["result"].as_a.first

      server.dispatch(JSON.parse(<<-JSON
        {
          "jsonrpc":"2.0",
          "id":82,
          "method":"#{Ameba::LSP::Method::CODE_ACTION_RESOLVE}",
          "params":#{action.to_json}
        }
        JSON
      ))
      resolve = parse_lsp_frames(output).first
      resolve["result"]["edit"]["changes"][uri].as_a.first["newText"].as_s.should eq "B"

      server.dispatch(JSON.parse(<<-JSON
        {
          "jsonrpc":"2.0",
          "method":"#{Ameba::LSP::Method::DID_CHANGE}",
          "params":{
            "textDocument":{"uri":"#{uri}","version":2},
            "contentChanges":[{"text":"class A; end\\n"}]
          }
        }
        JSON
      ))
      parse_lsp_frames(output)

      server.dispatch(JSON.parse(<<-JSON
        {
          "jsonrpc":"2.0",
          "id":83,
          "method":"#{Ameba::LSP::Method::CODE_ACTION_RESOLVE}",
          "params":#{action.to_json}
        }
        JSON
      ))
      stale_resolve = parse_lsp_frames(output).first
      stale_resolve["result"].raw.should be_nil

      server.dispatch(JSON.parse(<<-JSON
        {
          "jsonrpc":"2.0",
          "id":84,
          "method":"workspace/doesNotExist",
          "params":{}
        }
        JSON
      ))
      method_not_found = parse_lsp_frames(output).first
      method_not_found["error"]["code"].as_i.should eq Protocol::ErrorCode::MethodNotFound.value
    end

    it "resolves code actions when disabled issues precede diagnostics" do
      output = IO::Memory.new
      server = Server.new(IO::Memory.new, output, FakeAnalyzerWithDisabledIssue.new)
      uri = "file:///tmp/sample-disabled.cr"

      server.dispatch(JSON.parse(<<-JSON
        {
          "jsonrpc":"2.0",
          "method":"textDocument/didOpen",
          "params":{
            "textDocument":{
              "uri":"#{uri}",
              "languageId":"crystal",
              "version":1,
              "text":"# ameba:disable Ameba/ErrorRule\\nclass A; end\\n"
            }
          }
        }
        JSON
      ))
      parse_lsp_frames(output)

      server.dispatch(JSON.parse(<<-JSON
        {
          "jsonrpc":"2.0",
          "id":9,
          "method":"textDocument/codeAction",
          "params":{
            "textDocument":{"uri":"#{uri}"},
            "range":{"start":{"line":1,"character":6},"end":{"line":1,"character":7}},
            "context":{"diagnostics":[]}
          }
        }
        JSON
      ))
      code_action_response = parse_lsp_frames(output).first
      code_actions = code_action_response["result"].as_a
      code_actions.size.should eq 1

      action = code_actions.first
      server.dispatch(JSON.parse(<<-JSON
        {
          "jsonrpc":"2.0",
          "id":10,
          "method":"codeAction/resolve",
          "params":#{action.to_json}
        }
        JSON
      ))

      resolve_response = parse_lsp_frames(output).first
      edits = resolve_response["result"]["edit"]["changes"][uri].as_a
      edits.size.should eq 1
      edits.first["newText"].as_s.should eq "B"
    end
  end
end
