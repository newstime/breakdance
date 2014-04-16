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
    text_dup = @text.dup # Make a duplicate of text for measurements for map

    # Clean up for mapping.
    text_dup.strip!
    text_dup.gsub!(/ +/, ' ')
    text_dup.gsub!("\r", '')
    text_dup.gsub!("\n", '')
    text_dup.gsub!("\t", '')

    text_dup_length = text_dup.length
    @paragraph_children.each do |el|
      el_text = el.text.strip

      el_text.strip!
      el_text.gsub!(/ +/, ' ')
      el_text.gsub!("\r", '')
      el_text.gsub!("\n", '')
      el_text.gsub!("\t", '')

      # Strip space to left, and adjust position.
      text_dup.lstrip!
      link_map_current_location += text_dup_length - text_dup.length
      text_dup_length = text_dup.length

      # Need to force UTF encoding. Content coming out of Crawdad is ASCII
      # 8-bit encoded, need to look into fixing this so we don't need to do
      # the conversion here to avoid encoding exception in the sub.
      utf_encoded_el_text = el_text.force_encoding(Encoding::UTF_8)
      text_dup.sub!(/^#{Regexp.quote(utf_encoded_el_text)}/, '') # Strip word

      text_length = text_dup_length - text_dup.length
      attributes = el.attributes

      if el.name == 'a'
        @link_map << [
          link_map_current_location,                    # From
          link_map_current_location + text_length,      # To
          el_text,                                      # Text
          attributes                                    # Link Attributes
        ]
      end
      text_dup_length = text_dup.length
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
      remaining_text_with_links
      "<p class=\"continued\">#{remaining_text_with_links}</p>"
    end
  end

  # Returns remaining_text with links reapplied.
  def remaining_text_with_links
    line = @remaining_text.dup.lstrip

    line_length = line.length

    # Superimpose links
    inserted_link_offset = 0 # Record offset that should be honered due to inserted links.

    @link_map.each do |from, to, text, attributes|
      if (@character_index <= to) && (from <= @character_index + line_length)
        # Splice in the link.
        begin_splice = [@character_index, from].max - @character_index
        end_splice = [@character_index + line_length, to].min - @character_index

        # If add hyphen, and overlaps the end, swollow hyphen
        if (end_splice == line_length) && add_hyphen
          end_splice += 1
        end

        range = (begin_splice+inserted_link_offset)...(end_splice+inserted_link_offset)
        content = line[range]
        starting_length = line.length
        line[range] = "<a #{attributes.map { |k, v| "#{k}=\"#{v.value}\"" }.join}>#{content}</a>"
        new_length = line.length
        inserted_link_offset += new_length - starting_length
      end
    end

    line
  end

  def get_next_line
    return nil if exhasusted?

    line = ""
    tokens, breakpoint = @lines[@index]

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

        line << token.content
      when Crawdad::Tokens::Glue
        @remaining_text.lstrip!
        line << " "
      end
    end
    last_token = tokens.last
    line_length = line.length

    add_hyphen = false
    if last_token.class == Crawdad::Tokens::Penalty && last_token[:flagged] == 1
      line << "-"
      add_hyphen = true
    end

    # Superimpose links
    inserted_link_offset = 0 # Record offset that should be honered due to inserted links.

    @link_map.each do |from, to, text, attributes|
      if (@character_index <= to) && (from <= @character_index + line_length)
        # Splice in the link.
        begin_splice = [@character_index, from].max - @character_index
        end_splice = [@character_index + line_length, to].min - @character_index

        # If add hyphen, and overlaps the end, swollow hyphen
        if (end_splice == line_length) && add_hyphen
          end_splice += 1
        end

        range = (begin_splice+inserted_link_offset)...(end_splice+inserted_link_offset)
        content = line[range]
        starting_length = line.length
        line[range] = "<a #{attributes.map { |k, v| "#{k}=\"#{v.value}\"" }.join}>#{content}</a>"
        new_length = line.length
        inserted_link_offset += new_length - starting_length

      end
    end

    @index += 1

    @character_index += line_length

    @character_index += 1 unless add_hyphen

    "<span class=\"line\">#{line}</span>"
  end

end
