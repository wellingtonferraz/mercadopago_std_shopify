require 'rubygems'
require 'bundler/setup'
require 'sinatra'
require 'httparty'
require 'json'
require 'addressable/uri'
require 'mercadopago' 
require 'pp'


class MercadoPagoStd < Sinatra::Base

  set :bind, '0.0.0.0'

  def initialize(base_path: '')
    @base_path = base_path
    @key = 'GEO8BxYT5ifSOp9Y3ys7wGiwXcNu8h0O'
    
    MercadoPago::Settings.CLIENT_ID     = "5065100305679755"
    MercadoPago::Settings.CLIENT_SECRET = "GEO8BxYT5ifSOp9Y3ys7wGiwXcNu8h0O"
    
    super
  end

  def fields
    @fields ||= request.params.select {|k, v| k.start_with? 'x_'}
  end

  def sign(fields, key=@key)
    Digest::HMAC.hexdigest(fields.sort.join, key, Digest::SHA256)
  end
  
  def process_merchant_order
  end
  
   
  get '/' do
    "Mercado Pago Teste STD Checkout"
  end

  def get_owner_id(client_id)
    owner = HTTParty.get('https://api.mercadolibre.com/applications/'+client_id.to_s) 
    if owner.code.to_i === 200
      owner_id = owner['owner_id']
    end
    owner_id
  end

  def get_secret_key(owner_id, client_id)
    url_internal = 'https://internal.mercadolibre.com/applications/'+client_id.to_s+"?caller.id=" + owner_id.to_s + "&caller.status=ACTIVE&caller.scopes=crud_app"
    puts "====url====" + url_internal

    response_secret_key = HTTParty.get(url_internal)  

    puts "====response_secret_key====" + response_secret_key.to_s    

    if response_secret_key.code.to_i === 200
      secret_key = response_secret_key['secret_key']
    end

    #internal.mercadolibre.com/applications/5065100305679755?caller.id=201657914&caller.status=ACTIVE&caller.scopes=crud_app
    secret_key
  end

  get '/clientSecret/:client_id' do
    client_id = "#{params['client_id']}"
    owner_id = get_owner_id(client_id)
    puts ("owner_id " + owner_id.to_s)
    secret_key = get_secret_key(owner_id, client_id);

    "owner_id " +  secret_key.to_s + "!!"
  end


  post '/' do
    p "-------------------------------------------------------"
    p "Params #{request.params}"
    p "Host #{request.host}"
    
    preference = MercadoPago::Preference.new
    preference.external_reference = fields['x_reference']
    preference.auto_return = 'all'
    preference.back_urls = {
        success: "#{request.host}/callback",
        pending: "#{request.host}/callback",
        failure: "#{request.host}/callback"
    }
    preference.additional_info = {
        x_account_id: fields['x_account_id'],
        x_reference: fields['x_reference'],
        x_currency: fields['x_currency'],
        x_test: fields['x_test'],
        x_amount: fields['x_amount'],
        x_url_complete: fields['x_url_complete']
      }  
    
    item = MercadoPago::Item.new({
      title: fields['x_description'],
      quantity: 1,
      unit_price: fields['x_amount'].to_f
    })
    
    payer = MercadoPago::Payer.new({
        name: fields['x_customer_first_name'],
        surname: fields['x_customer_last_name'],
        email: fields['x_customer_email']
    })
        
    preference.items = [item]
    preference.payer = payer
 
    pp preference.to_json
    
 
    preference.save 
    redirect preference.init_point
  end


  get '/callback' do 
    
    payment = MercadoPago::Payment.load(params[:id])
    action = 'failed'

    case payment['response']['collection']['status']
    when 'approved'
      action = 'completed'
    when 'pending'
      action = 'pending'
    when 'in_process'
      action = 'pending'
    when 'rejected'
      action = 'failed'
    else
      action = 'failed'
    end


    preference = MercadoPago::Preference.load(params['preference_id'])
    
    

    additional_info = JSON.parse preference.additional_info

    ts = Time.now.utc.iso8601

    result = {timestamp: ts}

    payload = {
      'x_account_id'        => additional_info['x_account_id'],
      'x_reference'         => additional_info['x_reference'],
      'x_currency'          => additional_info['x_currency'],
      'x_test'              => additional_info['x_test'],
      'x_amount'            => additional_info['x_amount'],
      'x_result'            => action,
      'x_gateway_reference' => SecureRandom.hex,
      'x_timestamp'         => ts
    }

    payload['x_signature'] = sign(payload)

    redirect_url = Addressable::URI.parse(additional_info['x_url_complete'])
    redirect_url.query_values = payload

    p "Url Posted: #{additional_info['x_url_complete']}"
    p "Json Posted: #{payload.to_json}"

    response = HTTParty.post(additional_info['x_url_complete'], body: payload)

    if response.code == 200
      redirect redirect_url
      # result[:redirect] = redirect_url
    else
      result[:error] = response
    end


  end
  
  get '/ipn' do
    path, query   = env['REQUEST_PATH'], env['QUERY_STRING'] 
    params = query.split('&').map{|q| {q.split('=')[0].to_sym => q.split('=')[1]}}.reduce Hash.new, :merge
    
    notification = MercadoPago::Notification.new(params)  
    
    if params[:topic] == "merchant_order"
      begin
        MercadoPago::MerchantOrder.load(params[:id]) do |merchant_order|
          process_merchant_order(merchant_order)
        end
      rescue
        # if the merchant order doesnt exist
      end
    end
    
  end

  get '/new_payload' do
    x_url_complete = "https://checkout.shopify.com/13084163/checkouts/857771d326e49c2b3e512c93835a7576/offsite_gateway_callback"

    ts = Time.now.utc.iso8601

    result = {timestamp: ts}

    payload = {
      'x_account_id'        => "5065100305679755",
      'x_reference'         => "7987082118",
      'x_currency'          => "BRL",
      'x_test'              => "false",
      'x_amount'            => "76.50",
      'x_result'            => "completed",
      'x_gateway_reference' => SecureRandom.hex,
      'x_timestamp'         => ts
    }

    payload['x_signature'] = sign(payload)

    response = HTTParty.post(x_url_complete, body: payload)

  end

  run! if app_file == $0

end
