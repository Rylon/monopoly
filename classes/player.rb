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
	def sets_owned
		@properties.select{ |p| p.is_a? BasicProperty }.select { |p| p.set_owned? }.group_by { |p| p.set }.keys
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
