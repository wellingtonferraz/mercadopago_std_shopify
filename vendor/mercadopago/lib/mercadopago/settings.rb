require 'yaml'
require 'logger'
require_relative 'active_rest/lib/active_rest'

module MercadoPago
  module Settings

    # Default Configuration
    @@config = { 
        base_url: "https://api.mercadopago.com",
        CLIENT_ID:      "",
        CLIENT_SECRET:  "",
        ACCESS_TOKEN:   "", 
        notification_url:   "", 
        sandbox_mode: true,
        proxy_addr: "",
        proxy_port: ""
    }
    
    def self.configuration
      result = Hash.new
      @@config.map{|k, v| (result[k] = v) if @@config[k] != ""}
      return result
    end

    @valid_config_keys = @@config.keys

    # Configure using hash
    def self.configure(opts = {})
      opts.each {|k,v| @@config[k.to_sym] = v if @valid_config_keys.include? k.to_sym}
    end

    # Configure through yaml file
    def self.configure_with(path_to_yaml_file)
      begin
        config = YAML::load(IO.read(path_to_yaml_file))
      rescue Errno::ENOENT
        log(:warning, "YAML configuration file couldn't be found. Using defaults."); return
      rescue Psych::SyntaxError
        log(:warning, "YAML configuration file contains invalid syntax. Using defaults."); return
      end
      configure(config)
    end
    
    def self.try_to_get_token
      
      uri = URI(@@config[:base_url] + "/oauth/token")
      
      puts "URI: #{uri}"
      
      params = {grant_type: 'client_credentials',
                client_id: @@config[:CLIENT_ID], 
                client_secret: @@config[:CLIENT_SECRET]} 
                
      https = Net::HTTP.new(uri.host, uri.port)

      
      proxy, response = nil, nil
       
      if @@config[:proxy_addr].to_s != "" 
        ActiveREST::RESTClient.config do
          set_http_param :proxy_addr, @@config[:proxy_addr]
          set_http_param :proxy_port, @@config[:proxy_port]
        end
        
        proxy = Net::HTTP::Proxy(@@config[:proxy_addr], @@config[:proxy_port].to_i)
        
        https = proxy.new(uri.host, uri.port) 
        
      end
      
      p "PROXY: #{@@config[:proxy_port]}"
      p "HTTPS: #{https.instance_variable_get("@proxy_address")}" 
      
      https.use_ssl = true 
      https.ca_file = File.dirname(__FILE__) + '/ca-bundle.crt'
         
      req = Net::HTTP::Post.new(uri.path, initheader = {'Content-Type' =>'application/json'}) 
      req.set_form_data(params)
      
      response = https.request(req)
       
      return response.is_a?(Net::HTTPSuccess) ? response.body : nil 
    end

    # Method missing overwrite to allow call to keys in @config as a method
    def self.method_missing(method, *args, &block)
      has_equal_operator = (method[-1] == '=')
      value = (has_equal_operator ? @@config[method[0..-2].to_sym] : @@config[method.to_sym]) rescue nil
      
      if value
        if has_equal_operator
          @@config[method[0..-2].to_sym] = args[0] 
          response = try_to_get_token
          
          if response
            file = File.open(File.expand_path(__dir__) + "/token", "w+")
            file.puts(JSON.parse(response)["access_token"])
            file.close
          end
          
          @@config[:ACCESS_TOKEN]  = JSON.parse(response)["access_token"] if response
        else
          return value
        end
      end

    end

  end
end
 