$:.unshift(File.dirname(__FILE__) + "/../lib")
require "rubygems"
require "spec"
require 'result_store'

describe "storing a build result" do
  before do
    @store = MpBuildServer::BuildStore.new("http://127.0.0.1:3000/builds/create")
    @build = { 
      'name'       => 'test_build', 
      'revision'   => '2345', 
      'state'      => :success, 
      "os"         => 'Darwin 9.6.0',
      'cpu'        => 'i686',
      'time'       => Time.now.strftime("%Y-%m-%d %H:%M:%S"),
      'ruby_class' => 'Build'
    }
  end
  
  it "over REST" do
    RestClient.should_receive(:post).with("http://127.0.0.1:3000/builds/create", @build.to_json)
    @store.insert(@build)
  end
end
