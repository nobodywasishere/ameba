# Monkey-patch to stdlib ECR lexer to raise `Crystal::SyntaxException` instead of just `Exception`
class ECR::Lexer
  # ameba:disable Metrics/CyclomaticComplexity
  private def consume_control(is_output, is_escape, suppress_leading)
    start_pos = current_pos
    # ameba:disable Style/WhileTrue
    while true
      case current_char
      when '\0'
        if is_output
          raise Crystal::SyntaxException.new(
            "Unexpected end of file inside <%= ...",
            @line_number - 1, @column_number, ""
          )
        elsif is_escape
          raise Crystal::SyntaxException.new(
            "Unexpected end of file inside <%% ...",
            @line_number - 1, @column_number, ""
          )
        else
          raise Crystal::SyntaxException.new(
            "Unexpected end of file inside <% ...",
            @line_number - 1, @column_number, ""
          )
        end
      when '\n'
        @line_number += 1
        @column_number = 0
      when '-'
        if peek_next_char == '%'
          # We need to peek another char, so we remember
          # where we are, check that, and then go back
          pos = @reader.pos
          column_number = @column_number

          next_char

          is_end = peek_next_char == '>'
          @reader.pos = pos
          @column_number = column_number

          if is_end
            setup_control_token(start_pos, is_escape, suppress_leading, true)

            if current_char != '>'
              raise Crystal::SyntaxException.new(
                "Expecting '>' after '-%'",
                @line_number - 1, @column_number, ""
              )
            end

            next_char
            break
          end
        end
      when '%'
        if peek_next_char == '>'
          setup_control_token(start_pos, is_escape, suppress_leading, false)
          break
        end
      else
        # keep going
      end
      next_char
    end

    if is_escape
      @token.type = :string
    elsif is_output
      @token.type = :output
    else
      @token.type = :control
    end
    @token
  end
end
