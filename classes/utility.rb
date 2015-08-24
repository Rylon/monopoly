require 'square'

class Utility < Square
	attr_accessor :set
	def initialize(opts)
		@name = opts[:name]
		@set = :utility
		@action = Proc.new do |game, owner, player, property|
			if owner
				rent = game.last_roll * owner.properties.collect { |p| p.is_a? Utility }.count
				player.pay(owner, rent)
			end
		end
	end
end
