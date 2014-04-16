require 'crawdad'
require 'crawdad/html_tokenizer'

class ParagraphLinePrinter

  attr_reader :lines, :line_count

  def initialize(paragraph, column_width, font_profiles, options = {})
    @paragraph    = paragraph
    @column_width = column_width
    @font_profiles = font_profiles

    @text = @paragraph.text # Just text for now.
    @remaining_text = @text

    # ## Construct Link Map
    #
    # The link map note where links span, along with link attributes.
    # 1. Get all links from the paragraphs
    # 2. Extract attributes
    # 3. Determine what chracter poisitons they span

    @paragraph_children = @paragraph.children
    @link_map = []

    link_map_current_location = 0
    @paragraph_children.each do |el|
      text = el.text.strip
      text_length = text.length
      attributes = el.attributes
      if el.name == 'a'
        @link_map << [
          link_map_current_location,               # From
          link_map_current_location + text_length, # To
          text,                                    # Text
          attributes                               # Link Attributes
        ]
      end
      link_map_current_location += text_length
    end

    @index = 0
    @character_index = 0
    @classes = @paragraph['class'].to_s.split(' ')
    @continued = @classes.include?('continued') # Indicates if paragraph has already been opened.

    width = options[:width] || 284
    tolorence = options[:tolerence] || 10

    if @continued
      indent = 0
    else
      indent = options[:indent] || 40
    end

    stream = Crawdad::HtmlTokenizer.new(FontProfile2.get('minion', font_profiles_path: options[:font_profiles_path])).paragraph(@text, :hyphenation => true, indent: indent)
    para = Crawdad::Paragraph.new(stream, :width => width)
    @lines = para.lines(tolorence)
    @line_count = @lines.count
  end

  def make_stream(children)
    stream = children.map do |child|
      if child.text?
        child.text.chars
      else
        [
          {
            push: {
              tag_name: child.name,
              attributes: child.attributes
            }
          },
          make_stream(child.children),
          {
            pop: {
              tag_name: child.name
            }
          }
        ]
      end
    end
  end

  def next_character
    i = @index
    while i < @stream_length
      value = @stream[i+=1]
      return value if value.is_a? String
    end
  end

  def print(total_lines_to_print, output)
    lines = []

    while lines.count < total_lines_to_print
      line = get_next_line
      break unless line.present?
      lines << line
    end

    classes = ["typeset"]
    if @continued
      classes << "continued"
    else
      @continued = true
    end

    unless exhasusted?
      classes << "broken"
    end

    if classes.any?
      output.write "<p class=\"#{classes.join(' ')}\">#{lines.join}</p>"
    else
      output.write "<p>#{lines.join}</p>"
    end

    lines.count
  end

  # True if lines remain to be printed.
  def exhasusted?
    @index >= @lines.count
  end

  # Returns the remaining html
  def remaining_html
    if @index == 0
      @paragraph.to_html
    else
      "<p class=\"continued\">#{@remaining_text}</p>"
    end
  end

  def get_next_line
    return nil if exhasusted?

    stringio = StringIO.new

    tokens, breakpoint = @lines[@index]

    stringio.write("<span class=\"line\">")

    # skip over glue and penalties at the beginning of each line

    tokens.shift until Crawdad::Tokens::Box === tokens.first

    tokens.each do |token|
      case token
      when Crawdad::Tokens::Box
        @remaining_text.lstrip!

        # Need to force UTF encoding. Content coming out of Crawdad is ASCII
        # 8-bit encoded, need to look into fixing this so we don't need to do
        # the conversion here to avoid encoding exception in the sub.
        utf_encoded_token_content = token.content.force_encoding(Encoding::UTF_8)
        @remaining_text.sub!(/^#{Regexp.quote(utf_encoded_token_content)}/, '') # Strip word

        stringio.write(token.content)
      when Crawdad::Tokens::Glue
        @remaining_text.lstrip!
        stringio.write(" ")
      end
    end
    last_token = tokens.last
    if last_token.class == Crawdad::Tokens::Penalty && last_token[:flagged] == 1
      stringio.write("-")
    end
    stringio.write("</span> ")
    @index += 1
    stringio.string
  end

end
