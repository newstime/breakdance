require 'goliath'
require 'em-synchrony/em-http'
require 'em-http/middleware/json_response'
require 'yajl'
require 'superfreak'

# automatically parse the JSON HTTP response
EM::HttpRequest.use EventMachine::Middleware::JSONResponse

class LineBreakingService < Goliath::API
  # parse query params and auto format JSON response
  use Goliath::Rack::Params
  use Goliath::Rack::Formatters::JSON
  use Goliath::Rack::Render

  def response(env)
    FontProfile
    resp = { }
    [200, {'Content-Type' => 'application/json'}, resp]
  end
end