require 'json'

class FontProfile

  def self.get(profile_name, options={})
    font_profiles_path = options[:font_profiles_path]
    path = "#{font_profiles_path}/#{profile_name}_profile.json"
    json = File.read(path)
    JSON.parse(json)
  end

end
