$:.unshift(File.dirname(__FILE__) + "/../lib")
require "rubygems"
gem "rspec" #, "=1.1.4"
require "spec"
require "couch"
require "mpbuilder"

describe "storing a document" do
  before do
    @server = Couch::Server.new("localhost", "5984")
    @db = "test_mpbuilds"
  end
  
  it "save a new one" do
    doc = {"name" => "wget", "revision" => 87624, "status" => "failure"}
    @server.put("/#{@db}/#{rand(1000_000).to_s}", doc.to_json)
  end

  it "translates hash into json" do
    { 
      "status"   => :fail, 
      "duration" => 2345, 
      "port"     => "wget", 
      "log"      => "the log output"
    }.to_json.should == %q[{"duration":2345,"port":"wget","log":"the log output","status":"fail"}]
  end
end
