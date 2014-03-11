require 'goliath'
require 'em-synchrony/em-http'
require 'em-http/middleware/json_response'
require 'yajl'
require 'superbreak'
require 'nokogiri'

# automatically parse the JSON HTTP response
EM::HttpRequest.use EventMachine::Middleware::JSONResponse

class LineBreakingService < Goliath::API
  # parse query params and auto format JSON response
  use Goliath::Rack::Params
  use Goliath::Rack::Formatters::JSON
  use Goliath::Rack::Render

  def response(env)
    #FontProfile
    logger.info "Processing Request #{params}"

    width         = params[:width] || 284
    limit         = params[:limit] || 100

    html = params["html"]
    doc = Nokogiri::HTML(html)
    elements = doc.css("body > *")

    line_streamer = LineStreamer.new(elements, width: width)
    html = line_streamer.take(limit).html_safe

    resp = {
      html: html
    }
    [200, {'Content-Type' => 'application/json'}, resp]
  end
end
