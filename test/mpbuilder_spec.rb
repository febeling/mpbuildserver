$:.unshift(File.dirname(__FILE__) + "/../lib")
require "rubygems"
gem "rspec"

require "spec"
require "mpbuilder"

describe "MpBuilder with running CouchDB" do
  before do
    options = {
      :database => "test_mpbuilds",
      :server   => "127.0.0.1",
      :port     => "5984"
    }
    @builder = MpBuilder.new(options)
    result_store = mock("result store", :insert => nil)
    @builder.stub!(:result_store).and_return(result_store)
  end

  it "can insert" do
    result = []
    result << {"name" => "wget", "revision" => "87624", "status" => "fail"}
    @builder.insert(result)
  end

  it "mpabdir set via options" do
    builder = MpBuilder.new(:mpab_dir => "mpabpath")
    builder.mpabdir.should == 'mpabpath'
  end

  it "extracting ports and revisions from svn log" do
    @builder.extract_paths(EXAMPLE_SVN_LOG).should == [["/trunk/dports/x11/qt4-x11/Portfile", "42117"],
                                                       ["/trunk/dports/databases/libgda3/Portfile", "42118"]]
  end

  it "can extract a port's name from the portfile path" do
    @builder.portname_from_path("/trunk/dports/databases/libgda3/Portfile").
      should == "libgda3"
    @builder.portname_from_path("/trunk/dports/x11/qt4-x11").
      should == "qt4-x11"
  end

  it "filtering updated ports list collapses multiple revisions for same port and extracts name from path" do
    updates = [["/trunk/dports/x11/qt4-x11/Portfile",       "42117"],
               ["/trunk/dports/databases/libgda3/Portfile", "42118"],
               ["/trunk/dports/databases/libgda3",          "42118"],
               ["/trunk/dports/x11/qt4-x11/Portfile",       "42119"]]
    filtered = @builder.filter_ports(updates)
    filtered.should == {
      "qt4-x11" => "42117,42119",
      "libgda3" => "42118"
    }
  end
  
  it "filters out _resource files" do
    update = ["/trunk/dports/_resources/port1.0/variant_descriptions.conf", "44349"]
    @builder.filter_ports([update]).should == {}
  end
end

describe "MpBuilder sub-process execution using :run" do
  before do
    @builder = MpBuilder.new(:logfile => "/dev/null", :logdir => "")
  end

  it "main success case" do
    @builder.execute("pwd")
  end
end

describe "MpBuilder with result log directory structure" do
  before do
    @builder = MpBuilder.new(:logfile => "/dev/null", 
                             :keeplog => true,
                             :logdir => "test/fixtures/logs")
    @updated_ports = {
      "libxz3" => "123",
      "squid" => "124",
      "ruby" => "126"
    }
  end

  it "understands result structure and adds correct revision" do
    results = @builder.read_results(@updated_ports)
    results.sort! { |a,b| a["name"] <=> b["name"] }
    results.size.should == 3
    results[0]["name"].should     == "libxz3"
    results[0]["revision"].should == "123"
    results[1]["name"].should     == "ruby"
    results[1]["revision"].should == "126"
    results[2]["name"].should     == "squid"
    results[2]["revision"].should == "124"
  end

  it "understands result structure" do
    results = @builder.read_results(@updated_ports)
    results.sort! { |a,b| a["name"] <=> b["name"] }
    results[1]["name"].should == "ruby"
    results[1]["revision"].should == "126"
    results[1]["state"].should == "success"
    results[1]["cpu"].should == "i686"
    results[1]["os"].should_not == nil
    results[1]["time"].should_not == nil
  end

  it "attaches log to fails" do
    results = @builder.read_results(@updated_ports)
    results.sort! { |a,b| a["name"] <=> b["name"] }
    results[2]["name"].should == "squid"
    results[2]["log"].should_not == nil
  end

  it "does not attach log to success" do
    results = @builder.read_results(@updated_ports)
    results.sort! { |a,b| a["name"] <=> b["name"] }
    results[1]["name"].should == "ruby"
    results[1]["state"].should == "success"
    results[1]["log"].should == nil
  end
end

EXAMPLE_SVN_LOG = <<EOT
<?xml version="1.0"?>
<log>
<logentry
   revision="42117">
<author>mcalhoun@macports.org</author>
<date>2008-11-15T19:39:34.535744Z</date>
<paths>
<path
   action="M">/trunk/dports/x11/qt4-x11/Portfile</path>
</paths>
<msg>qt4-x11: ensure that MacPorts compilers are always used
</msg>
</logentry>
<logentry
   revision="42118">
<author>mcalhoun@macports.org</author>
<date>2008-11-15T20:14:29.341662Z</date>
<paths>
<path
   action="M">/trunk/dports/databases/libgda3/Portfile</path>
</paths>
<msg>libgda3: change perl dependency from port:perl5.8 to path:bin/perl (see #16830)
</msg>
</logentry>
</log>
EOT
