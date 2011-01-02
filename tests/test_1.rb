require 'test/unit'
require 'rumble'

class Tests < Test::Unit::TestCase
	def setup
		@config = Rumble::Configuration.new
		@list = Rumble::MailingList.new('test@example.com', @config)
	end
	def test_config
		@config.smtpauthmethod = "CRAM-MD5"
		assert @config.smtpauthmethod.kind_of?(Symbol)
	end
	def test_list
		assert @list.respond_to?(:send_message)
		assert @list.respond_to?(:members)
		assert @list.respond_to?(:subscribe)
		assert @list.respond_to?(:unsubscribe)
	end
end
