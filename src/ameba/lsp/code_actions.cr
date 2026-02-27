module Ameba::LSP::CodeActions
  extend self

  # Returns source edits that apply correction for a given issue.
  def edits_for(issue : Ameba::Issue, code : String) : Array(Ameba::Source::Rewriter::Edit)
    return [] of Ameba::Source::Rewriter::Edit unless issue.correctable?

    corrector = Ameba::Source::Corrector.new(code)
    issue.correct(corrector)
    corrector.edits
  end
end
