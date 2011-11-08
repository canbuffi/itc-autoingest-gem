require "itc_autoingest/version"

require 'httparty'
require 'csv'

module ITCAutoingest

  class ITCAutoingest
    include HTTParty

    base_uri 'https://reportingitc.apple.com'

    REPORT_TYPES = ['Sales']
    REPORT_SUB_TYPES = ['Summary', 'Opt-In']
    REPORT_TIMEFRAME = ['Daily', 'Weekly']

    def initialize(username, password, vndnumber)
      @auth = {:USERNAME => username, :PASSWORD => password, :VNDNUMBER => vndnumber }

      REPORT_TIMEFRAME.each { |timeframe|
        REPORT_TYPES.each { |report_type|
          REPORT_SUB_TYPES.each { |report_sub_type|
            (class << self; self; end).class_eval {
              define_method("#{timeframe.downcase}_#{report_type.downcase}_#{report_sub_type.sub('-', '').downcase}_report") { |*args|
                reportdate = (args.length == 0 ? (Time.now - 86400).strftime('%Y%m%d') : args[0])
                responsetype = (args.length < 2 ? nil : args[1])
                self.send('ingest', report_type, timeframe, report_sub_type, reportdate, responsetype)
              }
            }
          }
        }
      }
    end

    private

    def ingest(typeofreport, datetype, reporttype, reportdate, responsetype = :hash)
      query = { :TYPEOFREPORT => typeofreport, :DATETYPE => datetype, :REPORTTYPE => reporttype, :REPORTDATE => reportdate }
      query.merge!(@auth)

      response = self.class.post( '/autoingestion.tft', :query => query )

      if response.code != 200 
        {:error => response.message}
      elsif !response.headers['ERRORMSG'].nil?
        {:error => response.headers['ERRORMSG']}
      else
        report = {}
        report[:filename] = response.headers['filename']
        
        if responsetype == :raw
          report[:report] = raw_response(response)
        elsif responsetype == :hash
          report[:report] = hash_response(response)
        end
        
        return report
      end
    end
    
    def raw_response(response)
      Zlib::GzipReader.new(StringIO.new(response.body)).read
    end

    def hash_response(response)
      raw_data = raw_response(response)

      csv_data = CSV.parse(raw_data, {:col_sep => "\t"})

      headers = csv_data.shift.map {|i| i.to_s }
      string_data = csv_data.map {|row| row.map {|cell| cell.to_s } }
      string_data.map {|row| Hash[*headers.zip(row).flatten] }
    end
  end
end
