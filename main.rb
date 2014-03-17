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

    width         = (params['width'] || 284).to_i
    limit         = (params['limit'] || 100).to_i

    html = params["html"]
    doc = Nokogiri::HTML(html)
    elements = doc.css("body > *")

    line_streamer = LineStreamer.new(elements, width: width, font_profiles_path: FONT_PROFILES_PATH)
    html = line_streamer.take(limit).html_safe

    # TODO: Return Bool If Overflow Activated
    # TODO: Return Overflow HTML
    # TODO: Use Height and Overflow Buffer instead of Limit for caclulating what
    # to take

    resp = {
      html: html
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
