module Rumble

	class UserError < Exception
	end

	class AbstractMailingList
		#attr_accessor :bounceaddress
		def bounceaddress; address.gsub('@', '-bounce@'); end
		attr_reader :address, :replyto, :subjectmangle, :config, :footer, :posting
		def initialize(address, config)
			if !address
				raise UserError, "invalid address"
			end
			@address = address
			@posting = :open
			@config = config
			@smtpoptions = []
			@smtpoptions << config.smtpserver || 'localhost'
			@smtpoptions << config.smtpport || 25
			@smtpoptions << config.smtpserver || 'localhost' # HELO
			if config.smtpusername
				@smtpoptions << config.smtpusername << config.smtppassword << config.smtpauthmethod || :login
			end
		end

		def members
			[]
		end

		def store_message(message)
			#STUB
		end

		def send_message(message)
			validate(message)
			# FIXME: use gurgitate
			if replyto
				message.headers['Reply-To'] = replyto
			end
			if subjectmangle
				message.headers['Subject'] = "[#{address.split('@').first}] " + message.subject.first.contents 
			end
			messagetext = message.to_s

			if footer
				messagetext << "\n" << footer
			end

			Net::SMTP.start(*@smtpoptions) do |smtp|
				members.sort.uniq.each do |member|
					if config.verbose
						$stderr.puts "sending to #{member}"
					end
					smtp.send_message(messagetext, bounceaddress, member)
				end
			end
		end

		def validate(message)
			# fixme and use real validation.
			address = message.headers['From'].first.to_s
			if /<.*>/.match(address)
				address.gsub!(/.*<(.*)>/, '\1')
			end

			if posting != :open
				if !members.include? message.headers.from and !members.include? address
					raise UserError, "Posting not allowed from #{message.headers.from}"
				end
			end
		end

		def create(dir)
			store(dir)
		end

		def store(dir)
			Dir.mkdir(File.join(dir, address)) 
		end

		def my_dir
			File.join(config.datadir, address)
		end
	end

	module FileBasedMailingList
		def store_message(message)
			validate
			File.open(File.join(my_dir, 'stored_messages', Time.now.strftime('%Y%m%dT%H%M%s%Z' + Process.pid.to_s + '.msg')), 'wb') do |f|
				f.write(message)
			end
		end
		def store(dir)
			super
			membersfile = File.join(dir, address, 'members')
			File.open(membersfile + '.tmp', IO::CREAT|IO::WRONLY) do |f|
				f.puts begin
					self.members.join("\n")
				rescue Errno::ENOENT => e
					''	
				end
			end
			FileUtils.cp(membersfile,  membersfile+'-') rescue nil
			FileUtils.mv(membersfile+'.tmp',  membersfile)
		end

		def initialize_from_files
			if File.exists?(File.join(my_dir, 'replyto'))
				@replyto = File.read(File.join(my_dir, 'replyto')).strip
				if @replyto == 'list'
					@replyto = address
				end
			end
			if File.exists?(File.join(my_dir, 'subjectmangle'))
				@subjectmangle = true
			end
			if File.exists?(File.join(my_dir, 'footer'))
				@footer = File.read(File.join(my_dir, 'footer')).strip
			end
			if File.exists?(File.join(my_dir, 'posting'))
				@posting = File.read(File.join(my_dir, 'posting')).strip.intern
			end
		end

		def members
			File.readlines(File.join(my_dir, 'members')).select do |m|
				!m.strip.empty?
			end.map { |m| m.strip }
		end

		def subscribe(address)
			if members.select { |m| m == address }.size == 0
				File.open(File.join(my_dir, 'members'), 'a') do |f|
					f.puts(address.to_str)
				end
			else
				raise UserError, "Already subscribed"
			end
		end

		def unsubscribe(address)
			m = members.select { |m| m != address }
			if m == members
				raise UserError, "Not subscribed"
			else
				LineFile.new(m).write(File.join(my_dir, 'members'))
			end
		end
	end

	class MetaMailingList < AbstractMailingList
		include FileBasedMailingList
		attr_reader :children
		def initialize(address, config)
			super
			initialize_from_files
			@children = []
			File.readlines(File.join(my_dir, 'include')).each do |l|
				@children << config.store.list_for_address(l.strip)
			end 
		end
		def members
			members = []
			children.each do |list|
				list.members.each do |m|
					members << m
				end
			end
			members.sort.uniq
		end
	end

	class MailingList < AbstractMailingList
		include FileBasedMailingList
		def initialize(address, config)
			super
			initialize_from_files
		end

	end
end
