require 'goliath'
require 'em-synchrony/em-http'
require 'em-http/middleware/json_response'
require 'yajl'
require 'superbreak'
require 'nokogiri'
require 'active_support/all'
require 'debugger'  # Only in development

# automatically parse the JSON HTTP response
EM::HttpRequest.use EventMachine::Middleware::JSONResponse

class LineBreakingService < Goliath::API
  FONT_PROFILES_PATH = File.expand_path('../config/font_profiles', __FILE__)

  # parse query params and auto format JSON response
  use Goliath::Rack::Params
  use Goliath::Rack::Formatters::JSON
  use Goliath::Rack::Render

  def response(env)
    #FontProfile
    logger.info "Processing Request #{params}"

    width              = (params['width'] || 284).to_i
    height             = (params['height'] || '200px').to_i
    line_height        = (params['line_height'] || '20px').to_i
    overflow_reserve   = (params['overflow_reserve'] || '50px').to_i


    # Caluclate limit based on line height

    # Max lines to take without overflow.
    max_lines = height/line_height
    # Number of lines to return if overflowed.
    overflowed_lines = (height-overflow_reserve)/line_height

    #limit         = (params['limit'] || 100).to_i

    html = params["html"]
    doc = Nokogiri::HTML(html)
    paragraphs = doc.css("body > p")

    column_width = LinearMeasure.new("#{width}px")
    font_profile = options[:profile] || FontProfile.get('trykker', font_profiles_path: FONT_PROFILES_PATH)

    options = { width: width, font_profiles_path: FONT_PROFILES_PATH }
    paragraph_line_printers = paragraphs.map { |p| ParagraphLinePrinter.new(p, column_width, font_profile, options) }

    total_lines = paragraph_line_printers.map(&:line_count).inject(:+)

    current_paragraph_line_printer = paragraph_line_printers.shift

    output = StringIO.new

    line_count = nil
    overflowed = nil
    if total_lines > max_lines
      # Run overflow
      line_count = overflowed_lines
      overflowed = true
    else
      # Run exausted
      line_count = max_lines
      overflowed = false
    end

    while line_count > 0
      line_count -= current_paragraph_line_printer.print(line_count, output)

      # Load next paragraph stream if needed.
      if current_paragraph_line_printer.exhasusted?
        current_paragraph_line_printer = paragraph_line_printers.shift
        break unless current_paragraph_line_printer
      end
    end

    overflow_html = ""
    if overflowed
      if current_paragraph_line_printer
        overflow_html << current_paragraph_line_printer.remaining_html
      end
      paragraph_line_printers.each do |lbp|
        overflow_html << lbp.remaining_html
      end
    end

    html = output.string.html_safe

    resp = {
      html: html,
      overflowed: overflowed,
      overflow_html: overflow_html
    }

    if params['callback']
      # JSONP Response
      resp = "#{params['callback']}(#{resp.to_json})"
      [200, {'Content-Type' => 'text/javascript'}, resp]
    else
      # JSON Response
      [200, {'Content-Type' => 'application/json'}, resp]
    end

  end
end
