class FontProfile2

  def self.get(profile_name, options={})
    font_profiles_path = options[:font_profiles_path]
    path = "#{font_profiles_path}/#{profile_name}_profile.json"
    json = File.read(path)
    FontProfile2.new(JSON.parse(json), options)
  end

  def initialize(json, options={})
    @json = json
    @font_size = options[:font_size].to_f || 16.0
    @profile_font_size = @json["normal"]["font-size"].to_i
    @scale = @font_size/@profile_font_size
    #@scale = 22.0/16
  end

  def width_of(string)
    width = string.chars.map { |char| @json["normal"]["map"][char.ord.to_s] }.inject(:+) || 0
    (width * @scale).round
  #rescue => e
    #debugger
    #true
  end

end
