require 'square'

class Chance < Square
	def initialize(opts)
		@name = opts[:name]
		@action = Proc.new do |game, owner, player, property|
			this_chance = game.chance
			puts '[%s] Drew a chance: %s' % [ player.name, this_chance ]

			case this_chance
			when /Go to jail/
			when 'Go back three spaces'
				moved_to = player.move(-3)
				puts '[%s] Moved back to %s' % [ player.name, moved_to ]
			when 'Take a trip to Marylebone Station'
				player.move('Marylebone Station')
			when 'Advance to Mayfair'
				player.move('Mayfair')
			when 'Advance to Trafalgar Square'
				player.move('Trafalgar Square')
			when 'Advance to GO'
				player.move('GO')
			when 'Advance to Pall Mall'
				player.move('Pall Mall')
			when /Your building loan matures/
				game.pay_player(player, 100)
			when /Speeding fine/
				player.pay_free_parking(15)
			when /school fees/
				player.pay_free_parking(150)
			when /Bank pays you/
				game.pay_player(player, 50)
			when /Drunk in charge/
				player.pay_free_parking(50)
			when /crossword/
				game.pay_player(player, 100)
			when /general repairs/
				player.pay_free_parking((25 * player.num_houses) + (100 * player.num_hotels))
			when /street repairs/
				player.pay_free_parking((40 * player.num_houses) + (115 * player.num_hotels))
			when /jail free/
				player.jail_free_cards = player.jail_free_cards + 1
			end
		end
	end
end
