require 'rumble/mailinglist'
require 'gurgitate-mail'
require 'fileutils'
require 'yaml'
require 'net/smtp'

class LineFile
	attr_accessor :array
	def initialize(array)
		@array = array
	end
	def write(file)
		begin
			File.open(file+'.tmp', IO::WRONLY|IO::CREAT) do |f|
				array.each do |e|
					f.puts(e)
				end
			end
			FileUtils.cp(file, file+'-')
			FileUtils.mv(file+'.tmp', file)
		ensure
			File.unlink(file+'.tmp') rescue true
		end
	end
end

module Rumble
	def configure(file)
		Configuration.new(file)
	end

	class Configuration
		attr_accessor :smtpserver, :smtpport, :smtpusername, :smtppassword
		attr_reader :smtpauthmethod
		attr_accessor :datadir, :store
		attr_accessor :verbose
		def initialize
			@datadir = '/var/lib/rumble'
			@smtpserver = 'localhost'
			@smtpport = 25
			@smtpusername = nil
			@smtppassword = nil
			@smtpauthmethod = :none
			@verbose = false
		end
		def smtpauthmethod=(f)
			if Symbol === f
				@smtpauthmethod = f
			else
				@smtpauthmethod = f.intern
			end
		end
	end

	class RumbleAndGurgitate < Gurgitate::Gurgitate
		attr_reader :store
		def initialize(store, io)
			@store = store
			super(io)
		end

		def addresses
			addresses = if !$DELIVERY_ADDRESSES.empty? 
				$DELIVERY_ADDRESSES
			elsif headers['Envelope-To']
				headers['Envelope-To'].first.contents.split(',').map {|e| e.strip }
			else
				o = []
				['To','Cc'].each do |headername|
					if headers[headername]
						headers[headername].each do |h|
							o << h.contents
						end
					end
				end
				o
			end
		end

		def lists
			addresses = self.addresses.map do |address|
				if /<.*>/.match(address)
					address.gsub!(/.*<(.*)>/, '\1')
				end
				address = case address
				when /-request@/
					address.gsub('-request@', '@')
				when /-store@/
					address.gsub('-store@', '@')
				else
					address
				end
			end.sort.uniq

			addresses.map do |address|
				raise "No address found in message" if address.empty?
				store.list_for_address(address)
			end
		end
	end

	class MailingListDirectory
		attr_accessor :lists, :dir, :config
		def initialize(config)
			self.dir = config.datadir
			self.config = config
		end

		def [](address)
			list_for_address(address)
		end

		def newlist(address, listclass = MailingList)
			ml = listclass.new(address.dowmcase, config)
			ml.create(dir)
		end

		def action_for(address, processor)
			address = address.downcase
			if /<.*>/.match(address)
				address.gsub!(/.*<(.*)>/, '\1')
			end
			case address
			when /-request/
				if body =~ /subscribe/
					[:subscribe, headers['From']]
				elsif body =~ /unsubscribe/
					[:unsubscribe, headers['From']]
				else
					raise "unknown command"
				end
			when /-store/
				[:store_message, processor]
			else
				[:send_message, processor]
			end
		end

		def processmessage(io)
			processor = RumbleAndGurgitate.new(self, io)
			begin
				lists = processor.lists
			rescue Errno::ENOENT => e
				puts "No such list could be found"
			else
				processor.addresses.each do |address|
					action = action_for(address,processor)
					if config.verbose
						$stderr.puts "Action: #{action.inspect}"
					end
					lists.each do |list|
						list.send(*action)
					end
				end
			end
		end

		def list_for_address(address)
			address = address.downcase
			klass = File.read(File.join(@dir, address, 'type')).chomp rescue nil
			if !klass or klass.empty?
				klass = MailingList
			else
				klass = self.class.const_get(klass)
			end
			klass.new(address, config)
		end
	end
end
