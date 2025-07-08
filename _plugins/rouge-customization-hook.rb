Jekyll::Hooks.register :site, :after_init do |site|
  puts "[*] Customizing rouge"
  require "rouge"

  # Inspired by https://github.com/rouge-ruby/rouge/blob/master/lib/rouge/lexers/escape.rb
  class HighlightedText < Rouge::Lexer
    tag 'highlighted'

    def initialize(*)
      super
    end

    def stream_tokens(input, &output)
      stream = StringScanner.new(input)
      loop do
        if stream.scan(/(.*?)(<!)/m)
          yield Generic::Output, stream[1]
        else
          yield Generic::Output, stream.rest
          return
        end

        if stream.scan(/(.*?)(!>)/m)
          yield Generic::Emph, stream[1]
        else
          yield Generic::Emph, stream.rest
          return
        end
      end
    end
  end
end
