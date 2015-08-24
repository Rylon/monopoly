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
	def all_sets_owned
		@board.select{ |p| p.is_a? BasicProperty }.select { |p| p.set_owned? }.group_by { |p| p.set }.keys
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
	def active_players
		@players.reject{ |p| p.is_out? }
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
			if active_players.count == 1
				winner = still_in.first
				puts '[%s] Won the game! Final balance: £%d, Property: %s' % [ winner.name, winner.currency, winner.properties.collect {|p| p.name} ]
				@completed = true
				break
			end
		end
	end
end
