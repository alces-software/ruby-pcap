require 'pcap'
require 'optparse'

def pcaplet_usage()
  $stderr.print <<END
Usage: #{File.basename $0} [ -dnv ] [ -i interface | -r file ]
       #{' ' * File.basename($0).length} [ -c count ] [ -s snaplen ] [ filter ]
Options:
  -n  do not convert address to name
  -d  debug mode
  -v  verbose mode
END
end

module Pcap
  class Pcaplet
    def usage(status, msg = nil)
      $stderr.puts msg if msg
      pcaplet_usage
      exit(status)
    end

    def initialize(args = nil)
      args = args.split(/\s+/) if args
      @device = nil
      @rfile = nil
      @count = -1
      @snaplen = 68
      @log_packets = false
      @duplicated = nil

      opts = OptionParser.new do |opts|
        opts.on('-d') {$DEBUG = true}
        opts.on('-v') {$VERBOSE = true}
        opts.on('-n') {Pcap.convert = false}
        opts.on('-i IFACE') {|s| @device = s}
        opts.on('-r FILE') {|s| @rfile = s}
        opts.on('-c COUNT', OptionParser::DecimalInteger) {|i| @count = i}
        opts.on('-s LEN', OptionParser::DecimalInteger) {|i| @snaplen = i}
        opts.on('-l') { @log_packets = true }
      end
      begin
        opts.parse!(args ? args : ARGV)
      rescue
        usage(1)
      end

      # Explicitly set filter to nil to prevent warning about instance variable
      # being uninitialized; should be set to useful value via `add_filter`.
      @filter = nil

      # check option consistency
      usage(1) if @device && @rfile
      if !@device and !@rfile
        @device = Pcap.lookupdev
      end

      # open
      if @device
        @capture = Capture.open_live(@device, @snaplen)
      elsif @rfile
        if @rfile !~ /\.gz$/
          @capture = Capture.open_offline(@rfile)
        else
          $stdin = IO.popen("gzip -dc < #@rfile", 'r')
          @capture = Capture.open_offline('-')
        end
      end
    end

    attr('capture')

    def add_filter(f)
      if @filter == nil || @filter =~ /^\s*$/  # if empty
        @filter = f
      else
        f = f.source if f.is_a? Filter
        @filter = "( #{@filter} ) and ( #{f} )"
      end
      @capture.setfilter(@filter)
    end

    def each_packet(&block)
      begin
        @duplicated ||= (RUBY_PLATFORM =~ /linux/ && @device == "lo")
        if !@duplicated
          @capture.loop(@count, &block)
        else
          flip = true
          @capture.loop(@count) do |pkt|
            flip = (! flip)
            next if flip

            block.call pkt
          end
        end
      ensure
        # print statistics if live
        if @device && @log_packets
          stat = @capture.stats
          if stat
            $stderr.print("#{stat.recv} packets received by filter\n");
            $stderr.print("#{stat.drop} packets dropped by kernel\n");
          end
        end
      end
    end

    alias :each :each_packet

    def close
      @capture.close
    end
  end
end

Pcaplet = Pcap::Pcaplet
