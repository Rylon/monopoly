#!/usr/bin/ruby

require 'pp'
require 'pry'

class Game
	attr_accessor :hits, :board, :players, :num_dice, :die_size, :starting_currency, :available_properties, :chance, :community_chest, :bank_balance, :free_parking_balance, :player_starting_balance, :go_amount, :max_turns_in_jail, :last_roll, :turn, :completed, :num_houses, :num_hotels

	def initialize(opts)
		@hits = {}
		@turn = 0
		@bank_balance = opts[:bank_balance]
		@free_parking_balance = opts[:free_parking_balance] || 0
		@max_turns_in_jail = opts[max_turns_in_jail] || 3
		@last_roll = 0
		@go_amount = opts[:go_amount]
		@board = opts[:layout]
		@initial_board = @board
		@available_properties = @board
		@chance_all = opts[:chance]
		@chance = shuffle(@chance_all)
		@community_chest_all = opts[:community_chest]
		@community_chest = shuffle(@community_chest_all)
		@num_dice = opts[:num_dice]
		@num_houses = opts[:num_houses]
		@num_hotels = opts[:num_hotels]
		@die_size = opts[:die_size]
		@starting_currency = opts[:starting_currency]
		@players = opts[:players]
		@completed = false
		@board.each do |square|
			@hits[square] = 0
		end
		@players.each do |player|
			player.board = @board
			player.currency = opts[:starting_currency]
			player.game = self
		end
		self
	end
	def summary
		puts 'Monopoly summary'
		puts 'Game state: %s' % @completed? 'completed' : 'in progress'
		puts 'Turn number: %d' % @turn
		puts 'Number of active players: %d out of %d' % [ @players.select { |p| ! p.is_out? }.count, @players.length ]
		puts ''
		@players.each do |player|
			puts '[%s] Currency: %d, Properties: %d (%d mortgaged), Houses: %d, Hotels: %d' % [
				player.name,
				player.currency,
				player.properties.count,
				player.properties.select { |p| p.is_mortgaged? }.count,
				player.num_houses, player.num_hotels
			]
			# TODO: There must be a better way to group a player's properties by set!
			puts '- Properties: ' + player.properties.sort_by { |p| p.set }.collect { |p| p.name } * ', '
		end
		true
	end
	def get_all_hits
		@players.inject { |sum, p| sum.merge(p.history) { |k, a_value, b_value| a_value + b_value }	}
	end
	def shuffle(pile)
		pile.shuffle
	end
	def chance
		@chance = @chance_all.shuffle if @chance.length == 0
		@chance.shift
	end
	def pay_player(player, amount)
		if @bank_balance > amount
			@bank_balance = @bank_balance - amount
			player.currency = player.currency + amount
			puts '[%s] Received £%d from bank (balance: £%d, bank balance: £%d)' % [ player.name, amount, player.currency, bank_balance ]
			true
		else
			player.currency = player.currency + bank_balance
			puts '[%s] Unable to receive £%d from bank! Received £%d instead (balance: £%d)' % [ player.name, amount, bank_balance, player.currency ]
			@bank_balance = 0
			false
		end
	end	
	def payout_free_parking(player)
		player.currency = player.currency + @free_parking_balance
		puts '[%s] Landed on free parking! £%d treasure found' % [player.name, @free_parking_balance] unless @free_parking_balance == 0
		@free_parking_balance = 0
	end
	def community_chest
		@community_chest = @community_chest_all.shuffle if @community_chest.length == 0
		@community_chest.shift
	end
	def register_player(player)
		@players << player
	end
	def play(turns = 100000)
		turns.to_i.times do
			@turn = @turn + 1
			puts '- Turn %d begins!' % @turn
			@players.each do |turn|
				if turn.is_out?
					puts '[%s] Is sitting out' % turn.name
					next
				end
					puts '[%s] Go begins on %s (balance: £%d)' % [ turn.name , turn.current_square.name, turn.currency ]

				turn.properties.each do |property|
					case property
					when Station
						if property.is_mortgaged?
							turn.behaviour[:unmortgage_possible].call(self, turn, property) if turn.currency > property.cost
						end
					when Utility
						if property.is_mortgaged?
							turn.behaviour[:unmortgage_possible].call(self, turn, property) if turn.currency > property.cost
						end
					when BasicProperty
						if property.is_mortgaged?
							turn.behaviour[:unmortgage_possible].call(self, turn, property) if turn.currency > property.cost
						else
							if property.set_owned?
								case property.num_houses
								when 0..3
									turn.behaviour[:houses_available].call(self, turn, property) unless property.num_hotels > 0
								when 4
									turn.behaviour[:hotel_available].call(self, turn, property)
								end
							end
						end
					end

				end

				turn.behaviour[:use_jail_card].call(self, turn) if turn.in_jail? and turn.jail_free_cards > 0

				result = turn.roll
				double = (result.uniq.length == 1)

				move_total = result.inject(:+)
				@last_roll = move_total


				puts '[%s] Rolled %s (total: %d)' % [ turn.name, result.join(', '), move_total ]
				puts '[%s] Rolled a double' % turn.name if double

				if turn.in_jail?
					if double
						puts '[%s] Got out of jail! (rolled double)' % turn.name
						turn.in_jail = false
					else
						turn.turns_in_jail = turn.turns_in_jail + 1
						puts '[%s] Is still in jail (turn %d)' % [ turn.name, turn.turns_in_jail ]
						if turn.turns_in_jail >= @max_turns_in_jail
							turn.in_jail = false
							turn.pay_free_parking(50)
							puts '[%s] Got out of jail (paid out)' % turn.name
						else 
							next
						end
					end
				end

				square = turn.move(move_total)

				puts '[%s] Moved to %s' % [ turn.name, square.name ]
				square.action.call(self, square.owner, turn, square)

				puts '[%s] Next throw' % turn.name if double
				redo if double
				puts '[%s] Ended go on %s (balance: £%d)' % [ turn.name, turn.current_square.name, turn.currency ]
			end

			still_in = @players.reject{ |p| p.is_out? }
			if still_in.count == 1
				winner = still_in.first
				puts '[%s] Won the game! Final balance: £%d, Property: %s' % [ winner.name, winner.currency, winner.properties.collect {|p| p.name} ]
				@completed = true
				break
			end
		end
	end
end

class Player
	attr_accessor :hits, :board, :name, :currency, :history, :properties, :in_game, :turns_in_jail, :behaviour, :game, :jail_free_cards
	def initialize(args)
		@history = []
		@in_game = true
		@in_jail = false
		@turns_in_jail = 0
		@jail_free_cards = 0
		@currency = 0
		@game = nil
		@name = args[:name]
		@board = []
		@properties = []
		@behaviour = args[:behaviour]
		self
	end
	def in_jail?
		@in_jail
	end
	def num_houses
		@properties.collect{ |p| p.num_houses }.inject(:+) || 0
	end
	def num_hotels
		@properties.collect{ |p| p.num_hotels }.inject(:+) || 0
	end
	def in_jail=(bool)
		@in_jail = bool
		@turns_in_jail = 0 if bool == false
	end
	def move(n = 1, direction = :forwards)
		n = @board.collect{ |p| p.name }.find_index(n) if n.is_a? String

		case direction
		when :forwards
			go_index = @board.collect{ |p| p.name}.find_index('GO')
			if n >= go_index
				unless in_jail?
					puts '[%s] Passed GO' % @name
					@game.pay_player(self, @game.go_amount)
				end
			end

			(n % @board.length).times {
				@board.push @board.shift
			}
		when :backwards
			n = @board.length - n
			(n % @board.length).times {
				@board.unshift @board.pop
			}
		end

		@history << @board[0].name
		@board[0]
	end
	def current_square
		@board[0]
	end
	def bankrupt(player = nil)
		if player == nil
			puts '[%s] Bankrupted! Giving all assets to bank' % @name
			@properties.each do |property|
				property.owner = nil
				property.is_mortgaged = false
			end

			@properties = []
		else
			puts '[%s] Bankrupted! Giving all assets to %s' % [ @name, player.name ]
			@properties.each { |p| p.owner = player }
			puts '[%s] Transferred properties to %s: %s' % [ @name, player.name, @properties.collect { |p| p.name }.join(', ') ]
			player.properties.concat @properties unless player == nil
			@properties = []
		end
		out
	end
	def money_trouble(amount)
		puts '[%s] Has money trouble and is trying to raise £%d... (balance: £%d)' % [ @name, (amount - @currency), @currency ]
		@behaviour[:money_trouble].call(game, self, amount)
	end
	def pay_bank(amount)
		money_trouble(amount) if @currency < amount

		if @currency < amount then 
			@game.bank_balance = @game.bank_balance + @currency
			puts '[%s] Unable to pay £%d to bank! Paid £%d instead (bank balance: £%d)' % [ @name, amount, @currency, @game.bank_balance ]
			@currency = 0
			bankrupt
		else
			@currency = @currency - amount
			@game.bank_balance = @game.bank_balance + amount
			puts '[%s] Paid £%d to bank (balance: £%d, bank balance: £%d' % [ @name, amount, @currency, @game.bank_balance ]
			true
		end
	end
	def out
		puts '[%s] is out of the game!' % @name
		@in_game = false
	end
	def is_out?
		! @in_game
	end
	def use_jail_card
		if @jail_free_cards > 0
			puts "[%s] Used a 'get out of jail free' card!" % @name
			@in_jail = false
			@turns_in_jail = 0
			@jail_free_cards = @jail_free_cards - 1
		end
	end
	def pay_free_parking(amount)
		money_trouble(amount) if @currency < amount

		if @currency < amount then 
			@game.free_parking_balance = @game.free_parking_balance + @currency
			puts '[%s] Unable to pay £%d to free parking! Paid £%d instead (free parking balance: £%d)' % [ @name, amount, @currency, @game.free_parking_balance ]
			@currency = 0
			bankrupt
		else
			@currency = @currency - amount
			@game.free_parking_balance = @game.free_parking_balance + amount
			puts '[%s] Paid £%d to free parking (balance: £%d, free parking balance: £%d)' % [ @name, amount, @currency, @game.free_parking_balance ]
			true
		end
	end
	def pay(player, amount)
		money_trouble(amount) if @currency < amount

		if @currency < amount then
			player.currency = player.currency + @currency
			puts '[%s] Unable to pay £%d to %s! Paid £%d instead' % [ @name, amount, player.name, @currency ]
			@currency = 0
			bankrupt(player)
		else
			@currency = @currency - amount
			player.currency = player.currency + amount
			puts '[%s] Paid £%d to %s (balance: £%d)' % [ @name, amount, player.name, @currency ]
			true
		end
	end
	def roll
		Array.new(@game.num_dice).collect { Random.rand(1..@game.die_size) }
	end
end

class Square
	attr_accessor :action, :name, :owner
	def initialize(opts)
		@owner = nil
		@name = opts[:name]
		@action = opts[:action] || Proc.new {|game, owner, player, property|}
	end
end

class BasicProperty < Square
	attr_accessor :rent, :house_cost, :hotel_cost, :value, :mortgage_value, :set, :num_houses, :num_hotels, :is_mortgaged
	def initialize(opts)
		@name = opts[:name]
		@owner = nil
		@game = nil
		@cost = @value
		@rent = opts[:rent]
		@house_cost = opts[:house_cost]
		@is_mortgaged = false
		@hotel_cost = opts[:hotel_cost]
		@value = opts[:value]
		@mortgage_value = opts[:mortgage_value]
		@set = opts[:set]
		@num_houses = 0
		@num_hotels = 0
		@action = Proc.new do |game, owner, player, property|
			if owner
				if set_owned?
					rent_to_pay = (property.num_hotels  == 1 ? property.rent[5] : ( property.num_houses == 0 ? (@rent[0] * 2) :  property.rent[property.num_houses] ) )
				else
					rent_to_pay = property.rent[0]
				end
				if owner != player
					if not owner.is_out? and not is_mortgaged?
						puts '[%s] Due to pay £%d rent to %s for landing on %s with %s' % [ player.name, rent_to_pay, owner.name, property.name, ( property.num_hotels == 1 ? 'a hotel' : '%d houses' % property.num_houses) ]
						player.pay(owner, rent_to_pay)
					end
				end
			else
				player.behaviour[:land_on_vacant_property].call(game, player, self)
			end
		end
	end
	def cost
		if is_mortgaged?
			@value * 1.1
		else
			@value
		end
	end
	def set_owned?
		player_basic_properties = @owner.properties.select { |p| p.is_a? BasicProperty }
		board_basic_properties = @owner.game.board.select { |p| p.is_a? BasicProperty }
		player_properties_in_set = player_basic_properties.select { |p| p.set == @set and p.is_mortgaged? == false }
		board_properties_in_set = board_basic_properties.select { |p| p.set == @set }
		(board_properties_in_set - player_properties_in_set).empty?
	end
	def sell_to(player)
		if player.currency < cost then
			puts '[%s] Unable to buy %s! (short of cash by £%d)' % [ player.name, @name, (cost - player.currency) ]
			false
		else
			player.currency = player.currency - cost
			@owner = player
			player.properties << self
			puts '[%s] Purchased %s%s for £%d (balance: £%d)' % [ player.name, @name, (is_mortgaged? ? ' (mortgaged)' : ''), cost, player.currency ]
			true
		end
	end
	def give_to(player)
		puts '[%s] Gave %s to %s' % [ @owner.name, @name, player.name ]
		@owner.properties.delete self
		@owner = player
		player.properties << self
	end
	def mortgage
		unless is_mortgaged?
			puts '[%s] Mortgaged %s for £%d' % [ @owner.name, @name, @mortgage_value ]
			@is_mortgaged = true
			@owner.currency = @owner.currency + @mortgage_value
			@mortgage_value
		end
		self
	end
	def unmortgage
		if is_mortgaged?
			if @owner.currency > cost
				puts '[%s] Unmortgaged %s for £%d' % [ @owner.name, @name, cost ]
				@owner.currency = @owner.currency - cost
				@is_mortgaged = false
			else
				puts '[%s] Unable to unmortgage %s (not enough funds)' % [ @owner.name, @name ]
			end
		else
			puts '[%] Tried to unmortgage a non-mortgaged property (%s)' % [ @owner.name, @name ]
		end
		self
	end
	def is_mortgaged?
		@is_mortgaged
	end
	def add_houses(number)
		housing_value = @house_cost * number
		if @owner.game.num_houses >= number
			if (@num_houses + number) > 4
				puts '[%s] Cannot place more than 4 houses on %s' % [ @owner.name, @name ]
			else
				if @owner.currency < housing_value then
					puts '[%s] Unable to buy %d houses! (short of cash by £%d)' % [ @owner.name, number, (housing_value - @owner.currency) ]
					false
				else
					@owner.currency = @owner.currency - housing_value
					@owner.game.num_houses = @owner.game.num_houses - number
					@num_houses = @num_houses + number
					puts '[%s] Purchased %d houses on %s for £%d (balance: £%d)' % [ @owner.name, number, @name, housing_value, @owner.currency ]
					true
				end
			end
		else
			puts '[%s] Not enough houses left to purchase %d more for %s' % [ @owner.name, number, @name ]
		end
		self
	end
	def sell_houses(number)
		housing_value = (@house_cost / 2) * number
		if number > @num_houses
			puts "[%s] Can't sell %d houses on %s, as there are only %d" % [ @owner.name, number, @name, @num_houses ]
			false
		else
			@num_houses = @num_houses - number
			@owner.game.num_houses = @owner.game.num_houses + number
			@owner.currency = @owner.currency + housing_value
			puts '[%s] Sold %d houses on %s for £%d (%d remaining)' % [ @owner.name, number, @name, housing_value, @num_houses ]
		end
		self
	end
	def add_hotel
		if @num_houses == 4
			if @owner.game.num_houses > 0
				if @owner.currency < @hotel_cost then
					puts '[%s] Unable to buy a hotel! (short of cash by £%d)' % [ @owner.name, (@hotel_cost - @owner.currency) ]
					false
				else
					@owner.currency = @owner.currency - @hotel_cost
					@num_houses, @num_hotels = 0, 1
					@owner.game.num_houses = @owner.game.num_houses + 4
					@owner.game.num_hotels = @owner.game.num_hotels - 1
					puts '[%s] Purchased a hotel on %s for £%d (balance: £%d)' % [ @owner.name, @name, @hotel_cost, @owner.currency ]
					true
				end			
			else
				puts '[%s] Not enough hotels left to purchase %d more for %s' % [ @owner.name, number, @name ]
			end
		end
		self
	end
	def sell_hotel
		if @num_hotels < 1
			puts "[%s] Can't sell hotel on %s, as there isn't one!" % [ @owner.name, @name ]
		else
		 	housing_value = (@hotel_cost / 2) 
			@num_hotels = 0
			@owner.game.num_hotels = @owner.game.num_hotels + 1
			@owner.currency = @owner.currency + housing_value
			puts '[%s] Sold hotel on %s for £%d' % [ @owner.name, @name, housing_value ]
			case @owner.game.num_houses
			when 4
				@owner.game.num_houses = @owner.game.num_houses - 4
				@num_houses = 4
				puts '[%s] Devolved %s to %d houses' % [ @owner.name, @name, @num_houses ]
			when 1..3
				sell_houses(4 - @owner.game.num_houses)
				puts '[%s] Devolved %s to %d houses as 4 were not available' % [ @owner.name, @name, @num_houses ]
			when 0
				sell_houses(4)
				puts '[%s] Devolved to undeveloped site as no houses were available' % [ @owner.name, @name, @num_houses ]
			end
		end
		self
	end
end

class CommunityChest < Square
	def initialize(opts)
		@name = opts[:name]
		@action = Proc.new do |game, owner, player, property|
			this_cc = game.community_chest
			puts '[%s] Drew a community chest: %s' % [ player.name, this_cc ]

			case this_cc
			when /It is your birthday/
				game.players.reject { |p| p.name == player.name }.each do |other_player|
					other_player.pay(player, 10)
				end
			when /Old Kent Road/
				player.move('Old Kent Road', :backwards)
			when /take a chance/
			when /Go to jail/
				player.in_jail = true
				player.move('Jail')
				puts '[%s] Got sent to jail!' % player.name
			when /Annuity matures/
				game.pay_player(player, 150)
			when /sale of stock/
				game.pay_player(player, 50)
			when /preference shares/
				game.pay_player(player, 25)
			when /tax refund/
				game.pay_player(player, 20)
			when /insurance premium/
				player.pay_free_parking(50)
			when /Doctor/
				player.pay_free_parking(50)
			when /Bank error/
				game.pay_player(player, 200)
			when /hospital/
				player.pay_free_parking(100)
			when /beauty contest/
				game.pay_player(player, 10)
			when /inherit/
				game.pay_player(player, 100)
			when 'Advance to GO'
				player.move('GO')
			when /jail free/
				player.jail_free_cards = player.jail_free_cards + 1
			end
		end
	end
end

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

class_layout = []

class_layout << Square.new(
	name: 'GO',
	action: Proc.new { |game, owner, player, property|
		game.pay_player(player, 200)
		puts 'Bonus 200 for passing go'
	}
)

class_layout << BasicProperty.new(
	name: 'Old Kent Road',
	rent: [ 2, 10, 30, 90, 160, 250 ],
	house_cost: 50,
	hotel_cost: 50,
	mortgage_value: 30,
	value: 60,
	set: :brown
)

class_layout << CommunityChest.new(
	name: 'Community Chest 1',
)

class_layout << BasicProperty.new(
	name: 'Whitechapel Road',
	rent: [ 4, 20, 60, 180, 320, 450 ],
	house_cost: 50,
	hotel_cost: 50,
	mortgage_value: 30,
	value: 60,
	set: :brown
)

class_layout << Square.new(
	name: 'Income Tax',
	action: Proc.new { |game, owner, player, property|
		player.pay_bank(200)
	}
)

class_layout << Station.new(
	name: "King's Cross Station",
)

class_layout << BasicProperty.new(
	name: 'The Angel Islington',
	rent: [ 6, 30, 90, 270, 400, 550 ],
	house_cost: 50,
	hotel_cost: 50,
	mortgage_value: 50,
	value: 100,
	set: :blue
)

class_layout << Chance.new(
	name: 'Chance 1'
)

class_layout << BasicProperty.new(
	name: 'Euston Road',
	rent: [ 6, 30, 90, 270, 400, 550 ],
	house_cost: 50,
	hotel_cost: 50,
	mortgage_value: 50,
	value: 100,
	set: :blue
)

class_layout << BasicProperty.new(
	name: 'Pentonville Road',
	rent: [ 8, 40, 100, 300, 450, 600 ],
	house_cost: 50,
	hotel_cost: 50,
	mortgage_value: 60,
	value: 120,
	set: :blue
)

class_layout << Square.new(
	name: 'Jail'
)

class_layout << BasicProperty.new(
	name: 'Pall Mall',
	rent: [ 10, 50, 150, 450, 625, 750 ],
	house_cost: 100,
	hotel_cost: 100,
	mortgage_value: 70,
	value: 140,
	set: :pink
)

class_layout << Utility.new(
	name: 'Electric Company'
)

class_layout << BasicProperty.new(
	name: 'Whitehall',
	rent: [ 10, 50, 150, 450, 625, 750 ],
	house_cost: 100,
	hotel_cost: 100,
	mortgage_value: 70,
	value: 140,
	set: :pink
)

class_layout << BasicProperty.new(
	name: 'Northumberland Avenue',
	rent: [ 12, 60, 180, 500, 700, 900 ],
	house_cost: 100,
	hotel_cost: 100,
	mortgage_value: 80,
	value: 160,
	set: :pink
)

class_layout << Station.new(
	name: 'Marylebone Station',
)

class_layout << BasicProperty.new(
	name: 'Bow Street',
	rent: [ 14, 70, 200, 550, 750, 950 ],
	house_cost: 100,
	hotel_cost: 100,
	mortgage_value: 90,
	value: 180,
	set: :orange
)

class_layout << CommunityChest.new(
	name: 'Community Chest 2',
)

class_layout << BasicProperty.new(
	name: 'Marlborough Street',
	rent: [ 14, 70, 200, 550, 750, 950 ],
	house_cost: 100,
	hotel_cost: 100,
	mortgage_value: 90,
	value: 180,
	set: :orange
)

class_layout << BasicProperty.new(
	name: 'Vine Street',
	rent: [ 16, 80, 220, 600, 800, 1000 ],
	house_cost: 100,
	hotel_cost: 100,
	mortgage_value: 100,
	value: 200,
	set: :orange
)

class_layout << Square.new(
	name: 'Free Parking',
	action: Proc.new { |game, owner, player, property|
		game.payout_free_parking(player)
	}
)

class_layout << BasicProperty.new(
	name: 'Strand',
	rent: [ 18, 90, 250, 700, 875, 1050 ],
	house_cost: 150,
	hotel_cost: 150,
	mortgage_value: 110,
	value: 220,
	set: :red
)

class_layout << Chance.new(
	name: 'Chance 2'
)

class_layout << BasicProperty.new(
	name: 'Fleet Street',
	rent: [ 18, 90, 250, 700, 875, 1050 ],
	house_cost: 150,
	hotel_cost: 150,
	mortgage_value: 110,
	value: 220,
	set: :red
)

class_layout << BasicProperty.new(
	name: 'Trafalgar Square',
	rent: [ 20, 100, 300, 750, 925, 1100 ],
	house_cost: 150,
	hotel_cost: 150,
	mortgage_value: 120,
	value: 240,
	set: :red
)

class_layout << Station.new(
	name: 'Fenchurch St Station',
)

class_layout << BasicProperty.new(
	name: 'Leicester Square',
	rent: [ 22, 110, 330, 800, 975, 1150 ],
	house_cost: 150,
	hotel_cost: 150,
	mortgage_value: 130,
	value: 260,
	set: :yellow
)

class_layout << BasicProperty.new(
	name: 'Coventry Street',
	rent: [ 22, 110, 330, 800, 975, 1150 ],
	house_cost: 150,
	hotel_cost: 150,
	mortgage_value: 130,
	value: 260,
	set: :yellow
)

class_layout << Utility.new(
	name: 'Water Works'
)

class_layout << BasicProperty.new(
	name: 'Piccadilly',
	rent: [ 22, 120, 360, 850, 1025, 1200 ],
	house_cost: 150,
	hotel_cost: 150,
	mortgage_value: 140,
	value: 280,
	set: :yellow
)

class_layout << Square.new(
	name: 'Go to Jail',
	action: Proc.new {|game, owner, player, property|
		player.in_jail = true
		player.move('Jail')
		puts '[%s] Got sent to jail!' % player.name
	}
)

class_layout << BasicProperty.new(
	name: 'Regent Street',
	rent: [ 26, 130, 390, 900, 1100, 1275 ],
	house_cost: 200,
	hotel_cost: 200,
	mortgage_value: 150,
	value: 300,
	set: :green
)

class_layout << BasicProperty.new(
	name: 'Oxford Street',
	rent: [ 26, 130, 390, 900, 1100, 1275 ],
	house_cost: 200,
	hotel_cost: 200,
	mortgage_value: 150,
	value: 300,
	set: :green
)

class_layout << CommunityChest.new(
	name: 'Community Chest 3',
)

class_layout << BasicProperty.new(
	name: 'Bond Street',
	rent: [ 28, 150, 450, 1000, 1200, 1400 ],
	house_cost: 200,
	hotel_cost: 200,
	mortgage_value: 160,
	value: 320,
	set: :green
)

class_layout << Station.new(
	name: 'Liverpool St Station',
)

class_layout << Chance.new(
	name: 'Chance 3'
)

class_layout << BasicProperty.new(
	name: 'Park Lane',
	rent: [ 35, 175, 500, 1100, 1300, 1500 ],
	house_cost: 200,
	hotel_cost: 200,
	mortgage_value: 175,
	value: 350,
	set: :purple
)

class_layout << Square.new(
	name: 'Super Tax',
	action: Proc.new {|game, owner, player, property| 
		player.pay_bank(100)
	}
)

class_layout << BasicProperty.new(
	name: 'Mayfair',
	rent: [ 50, 200, 600, 1400, 1700, 2000 ],
	house_cost: 200,
	hotel_cost: 200,
	mortgage_value: 200,
	value: 400,
	set: :purple
)

community_chest = ['Go to jail. Move directly to jail. Do not pass GO. Do not collect £200.', 'Receive interest on 7% preference shares (£25)', 'Pay hospital £100', 'Pay your insurance premium (£50)', 'Advance to GO', 'Income tax refund (collect £20)', 'It is your birthday! (£10 from each player)', 'Go back to Old Kent Road', 'Bank error in your favour (£200)', 'Annuity matures (collect £100)', 'From sale of stock you get £50', 'You have won second prize in a beauty contest (£10)', 'Get out of jail free', 'Pay a £10 fine or take a chance', "Doctor's fee (£50)", 'You inherit £100']

chance = ['Your building loan matures (receive £150)', 'Take a trip to Marylebone Station', 'Go back three spaces', 'Speeding fine (£15)', 'Advance to Mayfair', 'Make general repairs on all of your houses. For each house pay £25, and for each hotel pay £100.', 'Advance to Trafalgar Square', 'You are assessed for street repairs. £40 per house, £115 per hotel.', 'Pay school fees of £150', 'Advance to GO', 'Bank pays you dividend of £50', 'Drunk in charge (£20 fine)', 'Go to jail. Move directly to jail. Do not pass GO. Do not collect £200', 'Advance to Pall Mall', 'Get out of jail free', 'You have won a crossword competition (£100)']

behaviour = {
	land_on_vacant_property: Proc.new { |game, player, property| 
		property.sell_to(player) if player.currency > property.cost
	},
	unmortgage_possible: Proc.new { |game, player, property|
		property.unmortgage if player.currency > property.cost
	},
	houses_available: Proc.new {|game, player, property|
		can_afford = ( player.currency / property.house_cost ).floor
		max_available = 4 - property.num_houses
		to_buy = [ can_afford, max_available ].min
		property.add_houses(to_buy) if to_buy
	},
	hotel_available: Proc.new {|game, player, property|
		property.add_hotel
	},
	money_trouble: Proc.new {|game, player, amount|
		portfolio = player.properties.sort_by { |p| p.mortgage_value }
		while player.currency < amount do
			if portfolio.length > 0
				property = portfolio.shift
				if property.num_hotels == 1
					property = property.sell_hotel
				end
				break if player.currency >= amount

				while property.num_houses > 0
					property = property.sell_houses(1)
					break if player.currency >= amount
				end
				break if player.currency >= amount

				property = property.mortgage
			else
				break
			end
		end
	},
	use_jail_card: Proc.new {|game, player|
		player.use_jail_card if player.jail_free_cards > 0
	}
}

monopoly_players = [
 	Player.new( name: 'James', behaviour: behaviour ),
 	Player.new( name: 'Jody',  behaviour: behaviour ),
 	Player.new( name: 'Ryan',  behaviour: behaviour ),
 	Player.new( name: 'Tine',  behaviour: behaviour )
]

monopoly = Game.new(
	layout: class_layout,
	chance: chance,
	community_chest: community_chest,
	num_dice: 2,
	die_size: 6,
	starting_currency: 1500,
	bank_balance: 12755,
	num_hotels: 12,
	num_houses: 48,
	go_amount: 200,
	max_turns_in_jail: 3,
	players: monopoly_players
)

binding.pry

monopoly.play(ARGV[0])


# sessions = {}
# report = []

# ARGV.each do |dice|
# 	sessions[dice] = Player.new
# 	1000.times {
# 		sessions[dice].move(Random.rand(2..(2 * dice.to_i)))
# 	}
# end

# text = 'Square,' + sessions.keys.join(',') + "\n"

# Player.new.board.each do |square|

# 	text = text + square
# 	sessions.keys.each do |this|
# 		text = text + ',' + ((sessions[this].hits[square].to_f / 1000) * 100.0).to_s
# 	end
# 	text = text + "\n"
# end

# puts text

