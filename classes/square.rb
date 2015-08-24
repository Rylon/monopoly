class Square
	attr_accessor :action, :name, :owner
	def initialize(opts)
		@owner = nil
		@name = opts[:name]
		@action = opts[:action] || Proc.new {|game, owner, player, property|}
	end
end
