require 'rubygems'
require 'bundler/setup'
require 'sinatra'
require 'httparty'
require 'json'
require 'addressable/uri'
require 'mercadopago'


class MercadoPagoStd < Sinatra::Base

  set :bind, '0.0.0.0'

  def initialize(base_path: '')
    @base_path = base_path
    @key = 'GEO8BxYT5ifSOp9Y3ys7wGiwXcNu8h0O'
    super
  end

  def fields
    @fields ||= request.params.select {|k, v| k.start_with? 'x_'}
  end

  def sign(fields, key=@key)
    Digest::HMAC.hexdigest(fields.sort.join, key, Digest::SHA256)
  end

  get '/' do
    "Mercado Pago Teste STD Checkout"
  end

  post '/' do
    p "-------------------------------------------------------"
    p "Params #{request.params}"
    p "Host #{request.host}"
    mp = MercadoPago.new('5065100305679755', 'GEO8BxYT5ifSOp9Y3ys7wGiwXcNu8h0O')
    preference_data = {
      external_reference: fields['x_reference'],
      items: [
        {
          title: fields['x_description'],
          quantity: 1,
          unit_price: fields['x_amount'].to_f
        }
      ],
      payer: {
        name: fields['x_customer_first_name'],
        surname: fields['x_customer_last_name'],
        email: fields['x_customer_email']
      },
      auto_return: 'all',
      back_urls: {
        success: "#{request.host}/callback",
        pending: "#{request.host}/callback",
        failure: "#{request.host}/callback"
      },
      additional_info: {
        x_account_id: fields['x_account_id'],
        x_reference: fields['x_reference'],
        x_currency: fields['x_currency'],
        x_test: fields['x_test'],
        x_amount: fields['x_amount'],
        x_url_complete: fields['x_url_complete']
      }
    }

    preference = mp.create_preference(preference_data)


    redirect preference['response']['init_point']
  end


  get '/callback' do
    mp = MercadoPago.new('5065100305679755', 'GEO8BxYT5ifSOp9Y3ys7wGiwXcNu8h0O')

    payment = mp.get_payment(params['collection_id'])
    action = 'failed'

    p "Payment status in callback: #{payment['response']['collection']['status']}"

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


    preference = mp.get_preference(params['preference_id'])

    additional_info = JSON.parse preference['response']['additional_info']

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
