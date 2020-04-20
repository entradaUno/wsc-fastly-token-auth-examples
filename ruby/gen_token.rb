#!/usr/bin/env ruby

# This code and all components (c) Copyright 2019-2020, Wowza Media Systems, LLC. All rights reserved.
# This code is licensed pursuant to the BSD 3-Clause License.

require 'optparse'
require 'openssl'

params = Hash.new

parser = OptionParser.new do |parser|

  parser.banner = %Q(
  gen_token: A short script to generate valid authentication tokens for
  Fastly stream targets in Wowza Streaming Cloud.

  To access to a protected stream target, requests must provide
  a parameter block generated by this script, otherwise the request
  will be blocked.

  Any token is tied to a specific stream id and has a limited lifetime.
  Optionally, additional parameters can be factored in, for example the
  client's IP address, or a start time denoting from when on the token is valid.
  See below for supported values. Keep in mind that the stream target
  configuration has to match these optional parameters in some cases.

  Examples:

  # Generate a token that is valid for 1 hour (3600 seconds)
  # and protects the stream id YourStreamId with a secret value of
  # demosecret123abc
  ./gen_token.rb -l 3600 -u YourStreamId -k demosecret123abc
  hdnts=exp=1579792240~hmac=efe1cef703a1951c7e01e49257ae33487adcf80ec91db2d264130fbe0daeb7ed

  # Generate a token that is valid from 1578935505 to 1578935593
  # seconds after 1970-01-01 00:00 UTC (Unix epoch time)
  ./gen_token.rb -s 1578935505 -e 1578935593 -u YourStreamId -k demosecret123abc
  hdnts=st=1578935505~exp=1578935593~hmac=aaf01da130e5554eeb74159e9794c58748bc9f6b5706593775011964612b6d99

  )

  params[:lifetime] = nil
  parser.on('-l', '--lifetime SECONDS', 'Token expires after SECONDS. --lifetime or --end_time is mandatory.') do |lt|
    params[:lifetime] = lt
  end

  params[:end_time] = nil
  parser.on('-e', '--end_time END_TIME', 'Token expiration in Unix Epoch seconds. --end_time overrides --lifetime.') do |et|
    params[:end_time] = et
  end

  params[:stream_id] = nil
  parser.on('-u', '--stream_id STREAMID', 'STREAMID to validate the token against.') do |u|
    params[:stream_id] = u
  end

  params[:secret] = nil
  parser.on('-k', '--key SECRET', 'Secret required to generate the token. Do not share this secret.') do |s|
    params[:secret] = s
  end

  params[:start_time] = nil
  parser.on('-s', '--start_time START_TIME', '(Optional) Start time in Unix Epoch seconds. Use \'now\' for the current time.') do |st|
    params[:start_time] = st == 'now' ? Time.new.getgm : st
  end

  params[:ip] = nil
  parser.on('-i', '--ip IP_ADDRESS', '(Optional) The token is only valid for this IP Address.') do |ip_address|
    params[:ip] = ip_address
  end

  params[:vod_stream_id] = nil
  parser.on('-v', '--vod VOD_STREAM_ID', '(Optional) The token is only valid for this VOD stream.') do |vod_stream_id|
    params[:vod_stream_id] = vod_stream_id
  end

  parser.on('-h', '--help', 'Display this help info') do
    puts parser
    exit
  end
end

parser.parse!

abort 'Error: You must provide a secret.' if params[:secret].nil? or params[:secret].length < 1

params[:start_time] = params[:start_time].nil? ? nil : params[:start_time].to_i
params[:end_time] = params[:end_time].nil? ? nil : params[:end_time].to_i
params[:lifetime] = params[:lifetime].nil? ? nil : params[:lifetime].to_i

unless params[:end_time].nil?
  if !params[:start_time].nil? && params[:start_time] >= params[:end_time]
    abort 'Error: Token start time is equal to or after expiration time.'
  end
else
  unless params[:lifetime].nil?
    if params[:start_time].nil?
      params[:end_time] = Time.new.getgm.to_i + params[:lifetime]
    else
      params[:end_time] = params[:start_time] + params[:lifetime]
    end
  else
    abort 'Error: You must provide an expiration time --end_time or a lifetime --lifetime. See --help for further info.'
  end
end

parts = Array.new
parts << 'ip=%s' % params[:ip] unless params[:ip].nil?
parts << 'st=%s' % params[:start_time] unless params[:start_time].nil?
parts << 'exp=%s' % params[:end_time]
public_parts = parts.join('~')

parts << 'stream_id=%s' % params[:stream_id]
secret = params[:secret].gsub(/\s/, '')
digest = OpenSSL::Digest.new('sha256')
hmac = OpenSSL::HMAC.new(secret, digest)
hmac.update(parts.join('~'))

puts 'hdnts=%s~hmac=%s' % [public_parts, hmac.hexdigest()]
