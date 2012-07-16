require "open-uri"
require "fileutils"
require "logger"
require "erb"

class RubygemsProxy
  attr_reader :env

  def self.call(env)
    new(env).run
  end

  def initialize(env)
    @env = env
    logger.level = Logger::INFO
  end

  def run
    logger.info "#{env["REQUEST_METHOD"]} #{env["PATH_INFO"]}"

    case env["PATH_INFO"]
    when "/"
      [200, {"Content-Type" => "text/html"}, [erb(:index)]]
    else
      [200, {"Content-Type" => "application/octet-stream"}, [contents]]
    end
  rescue Exception => e
    logger.info "Exception caught!!! -> #{e}\n#{e.backtrace.join("\n")}"
    [200, {"Content-Type" => "text/html"}, [erb(404)]]
  end

  private
  def erb(view)
    ERB.new(template(view)).result(binding)
  end

  def server_url
    env["rack.url_scheme"] + "://" + File.join(env["SERVER_NAME"], env["PATH_INFO"])
  end

  def rubygems_url(gemname)
    "http://rubygems.org/gems/%s" % Rack::Utils.escape(gemname)
  end

  def gem_url(name, version)
    File.join(server_url, "gems", Rack::Utils.escape("#{name}-#{version}.gem"))
  end

  def gem_list
    Dir[File.dirname(__FILE__) + "/public/gems/**/*.gem"]
  end

  def grouped_gems
    gem_list.inject({}) do |buffer, file|
      basename = File.basename(file)
      parts = basename.gsub(/\.gem/, "").split("-")
      version = parts.pop
      name = parts.join("-")

      buffer[name] ||= []
      buffer[name] << version
      buffer
    end
  end

  def template(name)
    @templates ||= {}
    @templates[name] ||= File.read(File.dirname(__FILE__) + "/views/#{name}.erb")
  end

  def root_dir
    File.expand_path "..", __FILE__
  end

  def logger
    @logger ||= Logger.new("#{root_dir}/tmp/server.log", 10, 1024000)
  end

  def cache_dir
    "#{root_dir}/public"
  end
  
  SPEC_CACHE_EXPIRY = 900  # seconds after originally fetching the specs
  def contents
    if File.directory?(filepath)
      logger.info "Is a dir, returning 404: #{filepath}"
      erb(404)
    elsif cached? && !specs?
      logger.info "Read from cache: #{filepath}"
      open(filepath).read
    elsif cached? && specs? && (Time.now - File.ctime(filepath) < SPEC_CACHE_EXPIRY)
      # if fetched within 15 minutes - produce cached version; otherwise fetch again and overwrite
      open(filepath).read
    else
      logger.info "Read from interwebz: #{url} <--- #{ specs? || gem_file? ? "is" : "NOT"} a gem or spec"
      # pass the Host header to correctly access the rubygems site
      open(url).read.tap { |content| save(content) if gem_file? || specs? }
    end
  end

  def save(contents)
    FileUtils.mkdir_p File.dirname(filepath)
    File.open(filepath, "wb") {|handler| handler << contents}
  end

  def specs?
    env["PATH_INFO"] =~ /specs\..+\.gz$/
  end
  
  def gem_file?
    env["PATH_INFO"] =~ /\.gem\Z/
  end


  def cached?
    File.file?(filepath)
  end

  def filepath
    if specs?
      File.join(cache_dir, "specs", env["PATH_INFO"])
    else
      File.join(cache_dir, env["PATH_INFO"])
    end
  end

  def url
    # connect directly to the IP address
    File.join("http://production.cf.rubygems.org", env["PATH_INFO"])
  end
end

