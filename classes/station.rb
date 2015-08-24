require 'square'

class Station < Square
	attr_accessor :set
	def initialize(opts)
		@name = opts[:name]
		@set = :stations
		@action = Proc.new do |game, owner, player, property|
			if owner
				rent = [ 25, 50, 100, 200 ]
				multiplier = owner.properties.collect { |p| p.is_a? Station }.count
				player.pay(owner, rent[multiplier])
			end
		end
	end
end
