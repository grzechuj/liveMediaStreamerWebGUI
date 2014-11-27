#
#  RUBYMIXER - A management ruby interface for MIXER
#  Copyright (C) 2013  Fundació i2CAT, Internet i Innovació digital a Catalunya
#
#  This file is part of thin RUBYMIXER.
#
#  This program is free software: you can redistribute it and/or modify
#  it under the terms of the GNU General Public License as published by
#  the Free Software Foundation, either version 3 of the License, or
#  (at your option) any later version.
#
#  This program is distributed in the hope that it will be useful,
#  but WITHOUT ANY WARRANTY; without even the implied warranty of
#  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#  GNU General Public License for more details.
#
#  You should have received a copy of the GNU General Public License
#  along with this program.  If not, see <http://www.gnu.org/licenses/>.
#
#  Authors:  Gerard Castillo <gerard.castillo@i2cat.net>,
#            Marc Palau <marc.palau@i2cat.net>
#
require 'socket'
require 'rest_client'

module RMixer
  class UltraGridRC

    attr_reader :uv_video_cmd_priority_list
    attr_reader :uv_audio_cmd_priority_list
    attr_reader :hash_response
    attr_reader :rtspPort
    attr_reader :controlPort
    def initialize()
      @uv_video_cmd_priority_list = [#"uv -t decklink:0:8 -c libavcodec:codec=H.264 -s embedded --audio-codec u-law",
        #"uv -t decklink:0:9 -c libavcodec:codec=H.264 -s embedded --audio-codec u-law",
        "uv -t decklink:0:8 -c libavcodec:codec=H.264",
        "uv -t decklink:0:9 -c libavcodec:codec=H.264",
        #"uv -t v4l2:fmt=YUYV:size=640x480 -c libavcodec:codec=H.264", #TODO ADD FLAG IF V4L2ACTIVE TO CHECK WHEN MANUAL PARAMS SETTING REQUEST
        "uv -t testcard:1920:1080:25:UYVY -c libavcodec:codec=H.264",
        "uv -t testcard:640:480:25:UYVY -c libavcodec:codec=H.264"]

      @uv_audio_cmd_priority_list = ["uv -s alsa --audio-codec u-law"] #future work: to check available alsa inputs and dynamically create the list

      @hash_response

      @rtspPort = 8548
      @controlPort = 8546
    end

    #TODO IMPLEMENT DISTINGUISHING.... (CHID, TYPE, PID, THRD...)

    def uv_check_and_tx(ip, port, type, timeStampFrequency, channels)
      case type
      when "audio"
        uv_audio_check_and_tx(ip, port, timeStampFrequency, channels)
      when "video"
        uv_video_check_and_tx(ip, port)
      else
        puts "no suitable input medium selected... check your request..."
      end
    end

    def uv_video_check_and_tx(ip, port)
      if ip.eql?""
        ip="127.0.0.1"
      end

      ip_mixer = local_ip

      puts "\nTrying to set-up VIDEO and transmit from #{ip} to #{ip_mixer} to mixer port #{port}\n"

      #first check uv availability (machine and ultragrid inside machine). Then proper configuration
      #1.- check decklink (fullHD, then HD)
      #2.- check v4l2
      #3.- check testcard
      #set working cmd by array (@uv_cmd) index
      @controlPort = @controlPort.to_i + 100
      begin
        response = RestClient.post "http://#{ip}/ultragrid/gui/check", :mode => 'local', :cmd => "uv -t testcard:640:480:15:UYVY -c libavcodec:codec=H.264 -P#{port}"
      rescue SignalException => e
        raise e
      rescue Exception => e
        puts "No connection to UltraGrid's machine or selected port in use! Please check far-end UltraGrid."
        return false
      end

      @uv_video_cmd_priority_list.each { |cmd|
        replyCmd = "#{cmd} --control-port #{@controlPort} #{ip_mixer} -P#{port}"
        puts replyCmd
        begin
          response = RestClient.post "http://#{ip}/ultragrid/gui/check", :mode => 'local', :cmd => replyCmd
        rescue SignalException => e
          raise e
        rescue Exception => e
          puts "No connection to UltraGrid's machine!"
          return false
        end

        @hash_response = JSON.parse(response, :symbolize_names => true)

        if @hash_response[:checked_local]
          break if uv_run(ip,replyCmd)
        end
      }

      hresponse = getUltraGridParams(ip)
      @hash_response = hresponse if !response.empty?
      if @hash_response[:uv_running]
        return true
      end

      return false
    end

    #TODO ADD AUDIO EMBEDDED OR ALSA IF DECKLINK VIDEO
    def uv_audio_check_and_tx(ip, port, timeStampFrequency, channels)
      if ip.eql?""
        ip="127.0.0.1"
      end

      ip_mixer = local_ip

      puts "\nTrying to set-up AUDIO and transmit from #{ip} to #{ip_mixer} to mixer port #{port}\n"

      #first check uv availability (machine and ultragrid inside machine). Then proper configuration
      #1.- check decklink (fullHD, then HD)
      #2.- check v4l2
      #3.- check testcard
      #set working cmd by array (@uv_cmd) index
      @controlPort = @controlPort.to_i + 100
      begin
        #TODO HERE CHECK IF DECKLINK!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
        response = RestClient.post "http://#{ip}/ultragrid/gui/check", :mode => 'local', :cmd => "uv -s alsa --audio-codec u-law -P#{port}"
      rescue SignalException => e
        raise e
      rescue Exception => e
        puts "No connection to UltraGrid's machine or selected port in use! Please check far-end UltraGrid."
        return false
      end

      @uv_audio_cmd_priority_list.each { |cmd|
        replyCmd = "#{cmd} --control-port #{@controlPort} #{ip_mixer} -P44440:44440:#{port}:#{port}"
        puts replyCmd
        begin
          response = RestClient.post "http://#{ip}/ultragrid/gui/check", :mode => 'local', :cmd => replyCmd
        rescue SignalException => e
          raise e
        rescue Exception => e
          puts "No connection to UltraGrid's machine!"
          return false
        end

        @hash_response = JSON.parse(response, :symbolize_names => true)

        if @hash_response[:checked_local]
          break if uv_run(ip,replyCmd)
        end
      }

      hresponse = getUltraGridParams(ip)
      @hash_response = hresponse if !response.empty?
      if @hash_response[:uv_running]
        return true
      end

      return false
    end

    def set_controlport(ip)
      puts "setting port #{@controlPort} with following configuration:"
      begin
        response = RestClient.post "http://#{ip}/ultragrid/gui/set_controlport", :port => @controlPort
      rescue SignalException => e
        raise e
      rescue Exception => e
        puts "No connection to UltraGrid's machine or selected port in use! Please check far-end UltraGrid."
        return false
      end
      return true
    end

    def uv_run(ip, cmd)
      sleep 1
      puts "running ultragrid with following configuration:"

      @rtspPort = @rtspPort.to_i + 100

      cmd << " --rtsp-server=port:#{@rtspPort}"
      puts cmd

      #execute cmd
      begin
        response = RestClient.post "http://#{ip}/ultragrid/gui/run_uv_cmd", :cmd => cmd
      rescue SignalException => e
        raise e
      rescue Exception => e
        puts "No connection to UltraGrid's machine or selected port in use! Please check far-end UltraGrid."
        return false
      end
      @hash_response = JSON.parse(response, :symbolize_names => true)
      if @hash_response[:uv_running]
        puts "RUNNING!"
        return true
      end
      return false
    end

    def local_ip
      UDPSocket.open {|s| s.connect("64.233.187.99", 1); s.addr.last}
    end

    def getUltraGridParams(ip)
      puts "getting original ultragrid channel params from: #{ip}"
      begin
        response = RestClient.get "http://#{ip}/ultragrid/gui/state"
      rescue SignalException => e
        raise e
      rescue Exception => e
        puts "No connection to UltraGrid's machine or selected port in use! Please check far-end UltraGrid."
        return {}
      end
      hash_response = JSON.parse(response, :symbolize_names => true)
      if hash_response[:uv_running]
        puts "RUNNING!"
        return hash_response
      end
      return {}
    end

    def set_vbcc(ip, vbcc)
      puts "setting config to #{ip} with vbcc: #{vbcc}"
      begin
        response = RestClient.post "http://#{ip}/ultragrid/gui/set_vbcc", :mode => vbcc
      rescue SignalException => e
        raise e
      rescue Exception => e
        puts "No connection to UltraGrid's machine or selected port in use! Please check far-end UltraGrid."
        return {}
      end
      hash_response = JSON.parse(response, :symbolize_names => true)
      if hash_response[:result]
        return clean_and_set_hash_response(hash_response[:curr_stream_config])
      end
      return {}
    end

    def set_size(ip, size)
      puts "setting config to #{ip} with size: #{size}"
      begin
        response = RestClient.post "http://#{ip}/ultragrid/gui/set_size", :value => size
      rescue SignalException => e
        raise e
      rescue Exception => e
        puts "No connection to UltraGrid's machine or selected port in use! Please check far-end UltraGrid."
        return {}
      end
      hash_response = JSON.parse(response, :symbolize_names => true)
      if hash_response[:result]
        return clean_and_set_hash_response(hash_response[:curr_stream_config])
      end
      return {}
    end

    def set_fps(ip, fps)
      puts "setting config to #{ip} with fps: #{fps}"
      begin
        response = RestClient.post "http://#{ip}/ultragrid/gui/set_fps", :value => fps
      rescue SignalException => e
        raise e
      rescue Exception => e
        puts "No connection to UltraGrid's machine or selected port in use! Please check far-end UltraGrid."
        return {}
      end
      hash_response = JSON.parse(response, :symbolize_names => true)
      if hash_response[:result]
        return clean_and_set_hash_response(hash_response[:curr_stream_config])
      end
      return {}
    end

    def set_br(ip, br)
      puts "setting config to #{ip} with bitrate: #{br}"
      begin
        response = RestClient.post "http://#{ip}/ultragrid/gui/set_br", :value => br
      rescue SignalException => e
        raise e
      rescue Exception => e
        puts "No connection to UltraGrid's machine or selected port in use! Please check far-end UltraGrid."
        return {}
      end
      hash_response = JSON.parse(response, :symbolize_names => true)
      if hash_response[:result]
        return clean_and_set_hash_response(hash_response[:curr_stream_config])
      end
      return {}
    end

    def clean_and_set_hash_response(hash_response)
      hash_response[:curr_size] = hash_response[:curr_size].chomp
      hash_response[:curr_fps] = hash_response[:curr_fps].chomp
      hash_response[:curr_br] = hash_response[:curr_br].chomp

      case hash_response[:curr_size]
      when "H"
        hash_response[:curr_size_value] = hash_response[:o_size]
      when "M"
        height = hash_response[:o_size].split('x')[1]
        width = hash_response[:o_size].split('x')[0]
        heightM = height.to_i / 2
        widthM = width.to_i / 2
        hash_response[:curr_size_value] = "#{widthM}x#{heightM}"
      when "L"
        height = hash_response[:o_size].split('x')[1]
        width = hash_response[:o_size].split('x')[0]
        heightL = height.to_i / 4
        widthL = width.to_i / 4
        hash_response[:curr_size_value] = "#{widthL}x#{heightL}"
      else
        puts "error when applying current stream size config"
      end

      case hash_response[:curr_fps]
      when "H"
        hash_response[:curr_fps_value] = hash_response[:o_fps].to_f.round(2)
      when "M"
        fpsM = 20 #(hash_response[:o_fps].to_f / 2).round(2)
        hash_response[:curr_fps_value] = "#{fpsM}"
      when "L"
        fpsL = 15 #(hash_response[:o_fps].to_f / 4).round(2)
        hash_response[:curr_fps_value] = "#{fpsL}"
      else
        puts "error when applying current stream size config"
      end

      case hash_response[:curr_br]
      when "H"
        hash_response[:curr_br_value] = hash_response[:o_br].to_f.round(2)
      when "M"
        brM = 1500 #(hash_response[:o_br].to_f / 2).round(2)
        hash_response[:curr_br_value] = "#{brM}"
      when "L"
        brL = 600  #(hash_response[:o_br].to_f / 4).round(2)
        hash_response[:curr_br_value] = "#{brL}"
      else
        puts "error when applying current stream size config"
      end

      puts hash_response
      return hash_response
    end

  end

end

#TODO MANAGE PORTS FROM SAME IP (RTSP SERVER, AND AUDIO vs VIDEO DISTINGUISHING - FOR DECKLINK TOO -...)
#TODO SO, manage LIST OF IP used and its usage to (video, audio, another video, another audio...?...)
