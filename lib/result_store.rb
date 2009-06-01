require 'json'
require 'rest_client'

module MpBuildServer
  class BuildStore
    def initialize(url)
      @url = if url =~ /\/$/
             then url[0..-2]
             else url
             end
    end

    def insert_url
      "#{@url}/builds/create"
    end

    def insert(hash)
      RestClient.post(insert_url, hash.to_json)
    end
  end
end
