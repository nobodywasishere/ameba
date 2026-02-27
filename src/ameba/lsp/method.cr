module Ameba::LSP::Method
  INITIALIZE          = "initialize"
  INITIALIZED         = "initialized"
  SHUTDOWN            = "shutdown"
  EXIT                = "exit"
  CANCEL_REQUEST      = "$/cancelRequest"
  DID_OPEN            = "textDocument/didOpen"
  DID_CHANGE          = "textDocument/didChange"
  DID_SAVE            = "textDocument/didSave"
  DID_CLOSE           = "textDocument/didClose"
  CODE_ACTION         = "textDocument/codeAction"
  CODE_ACTION_RESOLVE = "codeAction/resolve"
  PUBLISH_DIAGNOSTICS = "textDocument/publishDiagnostics"

  enum Kind
    Initialize
    Initialized
    Shutdown
    Exit
    CancelRequest
    DidOpen
    DidChange
    DidSave
    DidClose
    CodeAction
    CodeActionResolve
    PublishDiagnostics
  end

  METHOD_KINDS = {
    INITIALIZE          => Kind::Initialize,
    INITIALIZED         => Kind::Initialized,
    SHUTDOWN            => Kind::Shutdown,
    EXIT                => Kind::Exit,
    CANCEL_REQUEST      => Kind::CancelRequest,
    DID_OPEN            => Kind::DidOpen,
    DID_CHANGE          => Kind::DidChange,
    DID_SAVE            => Kind::DidSave,
    DID_CLOSE           => Kind::DidClose,
    CODE_ACTION         => Kind::CodeAction,
    CODE_ACTION_RESOLVE => Kind::CodeActionResolve,
    PUBLISH_DIAGNOSTICS => Kind::PublishDiagnostics,
  }

  def self.parse?(value : String) : Kind?
    METHOD_KINDS[value]?
  end
end
