require "rubygems"
require 'tempfile'
require "rexml/document"
require "rexml/xpath"
require "json"
require "open4"

require "result_store"

class MpBuilder
  include REXML

  BASE_DIR          = File.dirname(__FILE__) + "/.."
  MP_SVN_URL        = "http://svn.macosforge.org/repository/macports/trunk/dports"
  PORTNAME_RE       = Regexp.new '^/trunk/dports/[^_][^/]*/([^/]+)'
  DATE_FORMAT       = "%Y-%m-%d %H:%M:%S"
  LOG_TAIL_LINES    = 4096

  attr_reader :result_store

  def initialize(settings)
    @settings = settings
    @result_store = MpBuildServer::BuildStore.new(@settings[:buildstore])
  end

  def basedir
    @settings[:basedir] || BASE_DIR
  end

  def workdir
    @settings[:workdir] || Dir.pwd
  end

  def logdir
    @settings[:logdir] || basedir + "/log"
  end

  def logfile
    @logfile ||= File.open("#{logdir}/#{@settings[:logfile]}", "w+")
  end

  def mpabdir
    @settings[:mpab_dir]
  end

  def poll_interval
    @settings[:poll_interval]
  end

  def run
    start_rev    = @settings[:start_revision] || svn_find_latest_revision
    continuously = @settings[:continuously]

    build start_rev, poll_interval, continuously

    trace "run finished"
    logfile.close
  end

  def trace(messages)
    messages.each do |message|
      logentry = "[#{Time.now.strftime(DATE_FORMAT)}] #{message}"
      $stdout.puts logentry if @settings[:verbose]
      logfile.puts logentry if logfile
    end
  end

  def svn_log(from_revision, head_revision)
    cmd = ["svn", "log", MP_SVN_URL, "--xml", "-v", "-r", "#{from_revision}:#{head_revision}"].join(" ")
    trace cmd
    `#{cmd}`
  end

  def svn_find_latest_revision
    cmd = ["svn", "info", MP_SVN_URL].join(" ")
    result = `#{cmd}`
    md = result.match(/Last Changed Rev: (\d+)/)
    if md then md[1].to_i else nil end
  end

  def extract_paths(log_xml)
    doc = REXML::Document.new log_xml
    XPath.match(doc, "//path[@action=\"M\" or @action=\"A\"]").map do |elem|
      [elem.text, elem.parent.parent.attribute("revision").value]
    end
  end

  def portname_from_path(path)
    path.match(PORTNAME_RE)[1]
  end

  def filter_ports(updates)
    portname_revisions = updates.select { |update| update[0] =~ PORTNAME_RE }.map { |update| [portname_from_path(update[0]), update[1]] }
    portname_revisions.inject(Hash.new { |hash, key| hash[key] = "" }) { |mem, obj|
      portname = obj[0]
      revision = obj[1]
      next(mem) if mem[portname].index(revision)
      if mem[portname].length > 0
        mem[portname] << ","
      end
      mem[portname] << revision
      mem
    }
  end

  def save_portlist(ports)
    tempfile = Tempfile.new("mpbuilder")
    ports.each do |port, revision|
      tempfile.puts port
    end
    tempfile.close
    tempfile.path
  end

  def build_ports(ports_file)
    Dir.chdir(workdir) do
      trace "Refreshing chroot port tree..."
      execute("sh #{mpabdir}/mpsync.sh") || raise("port tree sync failure")
      trace "Building in chroot"
      execute("#{mpabdir}/mpab buildports #{ports_file}")
    end
  end

  def execute(command)
    trace "[execute] #{command.inspect}"
    pid, stdin, stdout, stderr = Open4::popen4(command)
    trace "pid: #{pid}"
    stdin.close

    [ Thread.new {
        while line = stderr.gets
          trace "  stderr: #{line}"
        end
      },
      Thread.new {
        while line = stdout.gets
          trace "  stdout: #{line}"
        end
      } ].each { |thread| thread.join }

    ignored, status = Process::waitpid2 pid
    
    status.exitstatus == 0
  end
  
  def insert(results)
    results.each do |build|
      result_store.insert(build)
    end
  end

  def logfile_to_name(logfile)
    File.basename(/(.+).log/.match(logfile)[1])
  end

  def shorten(log)
    lines = log.split("\n")
    first_line = [lines.size - LOG_TAIL_LINES, 0].max
    lines[first_line..-1].join("\n")
  end

  def find_chroot_port_version
    system("echo /opt/local/bin/port version | mpab shell 2>/dev/null | grep Version: | awk '{print $2}'")
  end

  def read_results(updated_ports)
    logs = Dir["#{workdir}/logs-*"]
    if logs.empty?
      []
    else
      resultdir = logs.sort.last
      builds = []
      [:fail, :success].each { |state|
        Dir[resultdir + "/#{state.to_s}/*.log"].map { |entry|
          [logfile_to_name(entry), shorten(IO.read(entry)) ]
        }.each { |name, log|
          build = {}
          build["name"]       = name
          build["revision"]   = updated_ports[name] || "revision not found"
          build["state"]      = state.to_s
          build["cpu"]        = Config::CONFIG["target_cpu"]
          build["os"]         = "" << `uname -s`.strip! << " " << `uname -r`.strip!
          build["time"]       = Time.now.strftime(DATE_FORMAT)
          build["log"]        = log if state == :fail
          build["ruby_class"] = "Build"
          build["port_version"] = find_chroot_port_version
          builds << build
        }
      }
      logs.each { |dir| FileUtils.rm_r(dir) } unless @settings[:keeplog]
      builds
    end
  end

  def pause(reason)
    trace "#{reason}. Waiting #{poll_interval}s"
    sleep self.poll_interval
  end

  def build(start_revision, poll_interval, continuously)

    from_revision = start_revision.to_i

    begin
      head_revision = svn_find_latest_revision
      if head_revision.nil?
        pause "Failed to retrieve svn HEAD revision" if continuously
        next
      end

      if from_revision > head_revision
        from_revision = head_revision + 1
        pause("No changes in svn") if continuously
        next
      else
        trace "Query svn revisions: #{from_revision}-#{head_revision}"
        changes_xml   = svn_log from_revision, head_revision
        updates       = extract_paths changes_xml
        updated_ports = filter_ports updates
        from_revision = head_revision + 1
      end

      if !updated_ports.empty?
        trace "Port changes found:"
        trace updated_ports.map { |name, rev| "  #{name} (#{rev})" }

        tmpfilepath = save_portlist updated_ports
        exitstatus  = build_ports tmpfilepath
        if exitstatus
          builds = read_results updated_ports
          insert builds
        else
          trace "mpab run exited with error"
        end
      else
        pause "No port changes among svn changes" if continuously
      end
    rescue StandardError => e
      trace "Error caught: #{e.message.inspect}"
      trace e.backtrace.map { |frame| "    #{frame}\n"}
      pause "After error" if continuously
    end while continuously

  end
end
