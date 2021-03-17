#!/usr/bin/ruby
require 'mqtt'
require 'logger'
require 'yaml'
require 'ostruct'
require 'json'
require 'date'

def usage
  puts "usage : #{$0} config.yaml"
  exit 1
end

$stdout.sync = true
Dir.chdir(File.dirname($0))
$current_dir = Dir.pwd

$log = Logger.new(STDOUT)
$log.level = Logger::DEBUG

usage if ARGV.size == 0

$conf = OpenStruct.new(YAML.load_file(ARGV[0]))

$conn_opts = {
  remote_host: $conf.mqtt_host,
  client_id: $conf.mqtt_client_id
}

if !$conf.mqtt_port.nil?
  $conn_opts["remote_port"] = $conf.mqtt_port
end

if $conf.mqtt_use_auth == true
  $conn_opts["username"] = $conf.mqtt_username
  $conn_opts["password"] = $conf.mqtt_password
end

def publish_alert_status(c, alert_flag)
  h = {}
  h["alert"] = alert_flag
  h["last_updated_time"] = DateTime.now.iso8601(0)
  h["threshold_rx_packets"] = $conf.threshold_rx_packets
  h["threshold_rx_bps"] = $conf.threshold_rx_bps
  h["threshold_interval"] = $conf.threshold_interval

  $log.info "publish: topic=#{$conf.publish_topic}, message=#{h.to_json}"
  c.publish($conf.publish_topic, h.to_json, true)
end

$last_alert_flag = false

def main_loop
  $log.info "connecting..."
  MQTT::Client.connect($conn_opts) do |c|
    $log.info "connected!"

    publish_alert_status(c, false)

    c.subscribe($conf.subscribe_topic)

    c.get do |topic, message|
      #$log.info "recv: topic=#{topic}, message=#{message}"
      json = OpenStruct.new(JSON.parse(message))

      if json.rx_packets > $conf.threshold_rx_packets
         $rx_packets_t = Time.now if $rx_packets_t.nil?
      else
         $rx_packets_t = nil
      end

      if json.bps > $conf.threshold_rx_bps
         $rx_bps_t = Time.now if $rx_bps_t.nil?
      else
         $rx_bps_t = nil
      end

      alert_flag = false
      if $rx_packets_t.nil? == false && Time.now - $rx_packets_t > $conf.threshold_interval
        alert_flag = true
      end
      if $rx_bps_t.nil? == false && Time.now - $rx_bps_t > $conf.threshold_interval
        alert_flag = true
      end

      if alert_flag != $last_alert_flag
        publish_alert_status(c, alert_flag)
      end

      $last_alert_flag = alert_flag
    end
  end
end

loop do
  begin
    main_loop
  rescue Exception => e
    $log.debug(e.to_s)
  end

  begin
    Thread.kill($watchdog_thread) if $watchdog_thread.nil? == false
    $watchdog_thread = nil
  rescue
  end

  $log.info "waiting 5 seconds..."
  sleep 5
end
