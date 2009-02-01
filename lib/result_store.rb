require 'json'
require 'rest_client'

module MpBuildServer
  class BuildStore
    def initialize(url)
      @url = url
    end

    def insert(hash)
      RestClient.post @url, hash.to_json
    end
  end
end
