require 'square'

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
		if @owner
			player_basic_properties = @owner.properties.select { |p| p.is_a? BasicProperty }
			board_basic_properties = @owner.game.board.select { |p| p.is_a? BasicProperty }
			player_properties_in_set = player_basic_properties.select { |p| p.set == @set and p.is_mortgaged? == false }
			board_properties_in_set = board_basic_properties.select { |p| p.set == @set }
			(board_properties_in_set - player_properties_in_set).empty?
		else
			false
		end
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
