extends Node2D

const START_MONEY = 50
const START_INCOME = 48

const TRANSFER_PERIOD = 2
const RENT_RISE_PERIOD = 6
const INCOME_RISE_PERIOD = 8

const BASE_PAWN_INCOME = 5
const BASE_RENT = 1
const BASE_PURCHASE_PRICE = 10

const RENT_INCREMENT = 1
const PURCHASE_PRICE_INCREMENT = 2
const INCOME_INCREMENT = 1


var	bMoney = START_MONEY
var wMoney = START_MONEY
var bIncome = START_INCOME
var wIncome = START_INCOME
	
var pawnIncome = BASE_PAWN_INCOME
var purchaseCost = BASE_PURCHASE_PRICE
var rentCost = BASE_RENT

#0 is unpopulated 
#odd is white, 3 is king
#even is black, 4 is king
var current_board: Dictionary = {}
#in format tile: [is occupied, refrence, color, is king, owner,level, buildingRef]
onready var w_pieces_remaining: int = $W.get_child_count()
onready var b_pieces_remaining: int = $B.get_child_count()

var multijump_mode:= false
var buy_mode = false

var selecting_destination := false
var selected_tile: Vector2
var public_viable_locations:= {}
var trading_cell = null
#contents will be formated {destination: [is_jumping, starting_point, jumped_tile(if applicable)]}

#we can use this as a state machine
var teams = ["black", "white"]
var turn_index: int = 0

onready var white_team = preload("res://Checkers/WhiteTeam.tscn")
onready var black_team = preload("res://Checkers/BlackTeam.tscn")
onready var move_marker = preload("res://Checkers/PossibleMoveMarker.tscn")
onready var white_team_ref =$W
onready var black_team_ref =$B
onready var black_king = preload("res://Checkers/BKing.tscn")
onready var white_king = preload("res://Checkers/WKing.tscn")
onready var white_building = preload("res://Checkers/WBuilding.tscn")
onready var black_building = preload("res://Checkers/BBuilding.tscn")
onready var building_team_ref = $BuildingTeam


func _ready():
	empty_board()
	update_board()
	
	# How to edit checker counter
	var checker = white_team_ref.get_node("WChecker")
	checker.get_node("MoveView").get_node("Counter").get_node("Label").text = "+2"

func empty_board():
	for y in 8:
		for x in 8:
			current_board[Vector2(x, y)] = [false, null, "", false,"",0,null]
#in format is occupied, refrence, color, is king,owner,level

#only seems to be called from the start game methods
func update_board():	
	update_board_group(black_team_ref.get_children(),"black")
	update_board_group(white_team_ref.get_children(),"white")


func update_board_group(group,faction):
	for x in group:
		var position = x.get_position()
		var coord: Vector2 = $Board.world_to_map(position)	
		current_board[coord] = [true, x, faction, x.is_in_group("King"), current_board[coord][4], current_board[coord][5], current_board[coord][6]]
	
#returns true if makes king	
func move_piece(initial_coord: Vector2, destination: Vector2):
	if(current_board[destination][0]): #tile is filled
		return
	else:
		var current_pos = ($Board.map_to_world(initial_coord) + Vector2(32,32))
		var destination_global = ($Board.map_to_world(destination) + Vector2(32,32))
		$Tween.interpolate_property(current_board[initial_coord][1], "position",
		current_pos, destination_global, 1.2,
		Tween.TRANS_QUAD, Tween.EASE_IN_OUT)
		$Tween.start()
		
		handle_leave_income_decrement(initial_coord)
		for x in 4:
			current_board[destination][x] = current_board[initial_coord][x]
		empty_tile(initial_coord)
		handle_arrival_income_increment(destination)
		var team = current_board[destination][2]
		if((team == "white") and (destination.y == 7)):
			current_board[destination][3] = true
			yield($Tween, "tween_completed")
			king_me(destination)
			return true
		if((team == "black") and (destination.y == 0)):
			current_board[destination][3] = true
			yield($Tween, "tween_completed")
			king_me(destination)
			return true
		
	public_viable_locations = {}
	return false
#contents will be formated {destination: [is_jumping, starting_point, jumped_tile(if applicable)]}


func handle_leave_income_decrement(tile):
	var pawnTeam = current_board[tile][2]
	var squareRent = get_tile_rent(tile) #this is 0 if tile is owned by occupant
	if pawnTeam=="white":
		wIncome-= (pawnIncome-squareRent)
	elif pawnTeam=="black":
		bIncome-= (pawnIncome-squareRent)
	
	if current_board[tile][4]!="": #player owned tile
		if pawnTeam=="white":
			bIncome-= squareRent #this value would be 0 if white owned the tile anyway
		if pawnTeam=="black":
			wIncome-= squareRent

func handle_arrival_income_increment(tile):
	var pawnTeam = current_board[tile][2]
	var squareRent = get_tile_rent(tile) #this is 0 if tile is owned by occupant
	if pawnTeam=="white":
		wIncome+= (pawnIncome-squareRent)
	elif pawnTeam=="black":
		bIncome+= (pawnIncome-squareRent)
	if current_board[tile][4]!="": #player owned tile
		if pawnTeam=="white":
			bIncome+= squareRent #this value would be 0 if white owned the tile anyway
		if pawnTeam=="black":
			wIncome+= squareRent

#returns how much rent a tile is currently costing
func get_tile_rent(tile):
	if current_board[tile][4]==current_board[tile][2]: #tile is owned by occupant
		return 0
	var rent = rentCost
	if current_board[tile][4]!="" and current_board[tile][5]!=0:
		rent+= pow(2,current_board[tile][5]-1)
	return rent


func end_turn():
	clear_move_markers()
	turn_index += 1
	
	#TODO: NOTIFY UI OF MONETARY TRANSACTIONS, maybe a signal?
	if turn_index%TRANSFER_PERIOD==0: #rent charging
		bMoney+=bIncome
		wMoney+=wIncome
	if turn_index%RENT_RISE_PERIOD==0: #rent rising
		rentCost += RENT_INCREMENT
		purchaseCost+= PURCHASE_PRICE_INCREMENT
		bIncome-= black_team_ref.get_child_count() * RENT_INCREMENT
		wIncome-= white_team_ref.get_child_count() * RENT_INCREMENT
	if turn_index%INCOME_RISE_PERIOD==0: #income improvement
		pawnIncome+= INCOME_INCREMENT
		bIncome+= black_team_ref.get_child_count() * INCOME_INCREMENT
		wIncome+= white_team_ref.get_child_count() * INCOME_INCREMENT
	if black_team_ref.get_child_count()==0:
		pass #TODO: TRIGGER GAME OVERS
	elif white_team_ref.get_child_count()==0:
		pass
	elif wMoney==0 and bMoney==0:
		pass
	elif wMoney==0:
		pass
	elif bMoney==0:
		pass
	
#called for peaceful movement only
func empty_tile(tile):
	current_board[tile][0] = false
	current_board[tile][1] = null
	current_board[tile][2] = ""
	current_board[tile][3] = false


func _unhandled_input(event):
	if(event.is_action_pressed("click")):
		var world_click_pos = event.position
		var map_cell_pos = $Board.world_to_map(world_click_pos)
		
		if((map_cell_pos.x >= 8) or (map_cell_pos.y >= 8) or (map_cell_pos.x < 0) or (map_cell_pos.y < 0)):#OOB check
			selecting_destination = false
			return
		if((not current_board[map_cell_pos][0]) and (not selecting_destination)):
			return
		
		if not selecting_destination and not multijump_mode and not buy_mode:
			#this seems to go into move preview mode
			selecting_destination = true
			position_move_data(map_cell_pos)
			show_possible_moves()
		elif not multijump_mode:
			selecting_destination = false
			clear_move_markers()
		elif buy_mode:
			pass #TODO: FIGURE OUT WHAT DROPPED INPUTS SHOULD DO FOR BUYMODE
		


func new_game():
	empty_board()
	white_team_ref.queue_free()
	black_team_ref.queue_free()
	building_team_ref.queue_free()
	
	bMoney = START_MONEY
	wMoney = START_MONEY
	bIncome = START_INCOME
	wIncome = START_INCOME
	
	pawnIncome = BASE_PAWN_INCOME
	purchaseCost = BASE_PURCHASE_PRICE
	rentCost = BASE_RENT
	
	var w_instance = white_team.instance()
	white_team_ref = w_instance
	add_child(w_instance)
	
	var b_instance = black_team.instance()
	black_team_ref = b_instance
	add_child(b_instance)
	multijump_mode = false
	selecting_destination = false
	clear_move_markers()
	
	update_board()
	turn_index = 0


func position_move_data(check_position: Vector2):
	var team =   current_board[check_position][2]
	var is_king = current_board[check_position][3]
	
	#we will spawn a marker at each viable location which when clicked will
	#move the piece to that location and delete any jumped tile
	var viable_locations := {}
	#contents will be formated {destination: [is_jumping, starting_point, jumped_tile(if applicable)]}
	var directions_to_check:= []
	
	directions_to_check = [Vector2(1,1), Vector2(-1,1), Vector2(1,-1), Vector2(-1,-1)]
	var direction
	while directions_to_check.size()>0:
		direction = directions_to_check.pop_front()
		var adjacent_data = check_adjacent_for_move(check_position, direction)
		#in format [can_move, can_jump, [tile, adjacent_tile, jump_tile] ]
		
		#move but no jump
		if((adjacent_data[0]) and (not adjacent_data[1])):
			viable_locations[adjacent_data[2][1]] = [false, check_position]
			if is_king:
				#continues along line if king
				var further = Vector2(direction.x + (1 if direction.x>0 else -1),
								direction.y + (1 if direction.y>0 else -1))
				directions_to_check.append(further)
		#jump but no move
		if((adjacent_data[0]) and (adjacent_data[1])):
			viable_locations[adjacent_data[2][2]] = [true, check_position, adjacent_data[2][1]]
	
	public_viable_locations = viable_locations




func search_for_jumps_only(tile):
	var team =   current_board[tile][2]
	var is_king = current_board[tile][3]
	
	var viable_locations := {}
	var directions_to_check:= [Vector2(1,1), Vector2(-1,1), Vector2(1,-1), Vector2(-1,-1)]
	
	
	var direction
	while directions_to_check.size()>0:
		direction = directions_to_check.pop_front()
		var adjacent_data = check_adjacent_for_move(tile, direction)
		#in format [can_move, can_jump, [tile, adjacent_tile, jump_tile]]
		if((adjacent_data[0]) and (adjacent_data[1])):
			viable_locations[adjacent_data[2][2]] = [true, tile, adjacent_data[2][1]]
	
	
	public_viable_locations = viable_locations


func spawn_move_marker(coord):
	#TODO: GET MOVEMENT COST DELTA  HERE, MOVE IT TO A PROPERTY IN MARKER INSTANCE SO IT'LL RENDER
	var world_position: Vector2 = ($Board.map_to_world(coord) + Vector2(32, 32))
	var marker_instance = move_marker.instance()
	marker_instance.set_position(world_position)
	$ViableLocations.add_child(marker_instance)


func show_possible_moves():
	for coord in public_viable_locations:
		spawn_move_marker(coord)


func clear_move_markers():
	for child in $ViableLocations.get_children():
		child.queue_free()


func kill_checker(tile):
	handle_leave_income_decrement(tile)
	current_board[tile][1].queue_free()
	empty_tile(tile)
	b_pieces_remaining = black_team_ref.get_child_count()
	w_pieces_remaining = white_team_ref.get_child_count()


func check_adjacent_for_move(tile: Vector2, vector_direction: Vector2):
	#returns in format [can_move, can_jump, [tile, adjacent_tile, jump_tile]]
	var adjacent_tile: Vector2 = (tile + vector_direction)
	var jump_boost = Vector2(1 if vector_direction.x>0 else -1,1 if vector_direction.y>0 else -1)
	var jump_tile: Vector2 = (tile + (vector_direction)+jump_boost)
	var my_color: String = current_board[tile][2]
	
	if(
		((adjacent_tile.x >= 8) or (adjacent_tile.y >= 8) or (adjacent_tile.x < 0) or (adjacent_tile.y < 0))
	):
		return([false, false]) #the tile is outside of the board; cannot move this way
	
	if(not current_board[adjacent_tile][0]):
		return([true, false, [tile, adjacent_tile]])#the tile is within the board and empty
	
	if(current_board[adjacent_tile][2] == my_color):
		return([false, false])#the tile is filled with a friendly; cannot move this way
	
	if(current_board[adjacent_tile][2] != my_color):
		if(
			((jump_tile.x >= 8) or (jump_tile.y >= 8) or (jump_tile.x < 0) or (jump_tile.y < 0))
		):
			return([false, false]) 
			#the tile is on the edge of the board
		if(not current_board[jump_tile][0]):
			return([true, true, [tile, adjacent_tile, jump_tile]])
			#the tile is filled with an enemy and there isn't a unit behind it; can jump
		else:
			return([false, false])#the tile is filled with a guarded enemy


func king_me(tile):
	var world_pos = ($Board.map_to_world(tile) + Vector2(32,32))
	
	current_board[tile][3] = true
	current_board[tile][1].queue_free()
	
	if(current_board[tile][2] == "black"):
		var king_instance = black_king.instance()
		king_instance.set_position(world_pos)
		black_team_ref.add_child(king_instance)
		current_board[tile][1] = king_instance
		
	if(current_board[tile][2] == "white"):
		var king_instance = white_king.instance()
		king_instance.set_position(world_pos)
		white_team_ref.add_child(king_instance)
		current_board[tile][1] = king_instance

func invalidClick(cell):
	return (
		(not selecting_destination and not multijump_mode) #we have not selected a piece yet
		and
		#tile isnt empty or we didnt select wrong team 
		(not current_board[cell][0] or current_board[cell][2] != teams[turn_index%2]) 
		
		#(not current_board[cell][0] and not selecting_destination and not multijump_mode) #empty cell, non-move mode
		#or (not selecting_destination and not multijump_mode) and (current_board[cell][2] != teams[turn_index%2]) #filled cell,wrong team
	)
func _on_Cursor_accept_pressed(cell):
	if buy_mode or invalidClick(cell):
		return
	
	#first click for movement prediction
	if(not selecting_destination and not multijump_mode):
		selecting_destination = true
		position_move_data(cell)
		show_possible_moves()
		return
	#time to actually move
	elif(selecting_destination or multijump_mode):
		if(public_viable_locations.has(cell)):
			var coord_data = public_viable_locations[cell]
			if(not coord_data[0]):#not jumping
				move_piece(coord_data[1], cell)
				end_turn()
			
			if(coord_data[0]):#jumping
				var kingmaker = move_piece(coord_data[1], cell)
				kill_checker(coord_data[2])
				
				search_for_jumps_only(cell)
				var can_multijump = public_viable_locations.size()!=0 and not kingmaker
				if(not can_multijump):
					multijump_mode = false
					$EndTurn.disabled = true
					end_turn()
				else:
					clear_move_markers()
					multijump_mode = true
					$EndTurn.disabled = false
					show_possible_moves()
					print(public_viable_locations)
		elif not multijump_mode:
			clear_move_markers()
	selecting_destination = false

func _on_EndTurn_pressed():
	end_turn()
	selecting_destination = false
	$EndTurn.disabled = true
	multijump_mode = false


func _on_Cursor_accept_pressed_buymode(cell):
	if not buy_mode or tile_not_for_purchase(cell):
		return
	trading_cell = cell
	if current_board[cell][4]=="":
		pass #TODO: purchase prompt with cost purchaseCost and locked cost field
	else:
		pass #TODO: purchase prompt with editable cost field
		
func tile_not_for_purchase(cell):
	return tile_is_white(cell) or tile_owned_by_current_player(cell)

func tile_is_white(cell:Vector2):
	return int(cell.x+cell.y)%2==1
	
func tile_owned_by_current_player(cell:Vector2):
	return current_board[cell][4]== ("black" if turn_index%2==0 else "white")
	
func _on_click_buymode():
	if multijump_mode:
		return
	buy_mode = true
	selecting_destination = false
	clear_move_markers()

func _on_click_movemode():
	buy_mode = false
	
func _on_purchase_cancel():
	trading_cell = null
func _on_purchase_complete():
	var directions_to_check = [Vector2(1,1), Vector2(-1,1), Vector2(1,-1), Vector2(-1,-1)]
	var neighbour
	var rank = 0
	handle_leave_income_decrement(trading_cell)
	for x in directions_to_check: 
		neighbour = current_board[trading_cell+x]
		if neighbour[4]!="":
			rank+=1
			if neighbour[1]!=null:
				handle_leave_income_decrement(neighbour)
				neighbour[5]+=1
				handle_arrival_income_increment(neighbour)
			else:
				neighbour[5]+=1
	current_board[trading_cell][5]=rank
	current_board[trading_cell][4]= ("black" if turn_index%2==0 else "white")
	handle_arrival_income_increment(trading_cell)
	trading_cell = null
	end_turn()
	
func investCursorPressed(cell):
	if current_board[cell][4] != "":
		return
	
	var building
	if turn_index%2:
		building = white_building.instance()
	else:
		building = black_building.instance()
	
	var coord: Vector2 = $Board.map_to_world(cell)
	building.position.x = coord.x + 144
	building.position.y = coord.y + 64
	
	building_team_ref.add_child(building) 
	current_board[cell][6] = building
	
	#TODO: update level of current building and others
	current_board[cell][5] = 1
	building.get_node("Level1").visible = true
	
	end_turn()


func _on_MoveButton_pressed():
	buy_mode = false
	for child in black_team_ref.get_children():
		child.get_node("InvestView").visible = false
		child.get_node("MoveView").visible = true
	for child in white_team_ref.get_children():
		child.get_node("InvestView").visible = false
		child.get_node("MoveView").visible = true
	for tile in current_board.values():
		if tile[6] != null:
			tile[6].get_node("Border").visible = true
			tile[6].get_node("Level1").visible = false
			tile[6].get_node("Level2").visible = false
			tile[6].get_node("Level3").visible = false
			tile[6].get_node("Level4").visible = false


func _on_InvestButton_pressed():
	buy_mode = true
	for child in black_team_ref.get_children():
		child.get_node("MoveView").visible = false
		child.get_node("InvestView").visible = true
	for child in white_team_ref.get_children():
		child.get_node("MoveView").visible = false
		child.get_node("InvestView").visible = true
	for tile in current_board.values():
		if tile[6] != null:
			tile[6].get_node("Border").visible = false
			tile[6].get_node("Level"+str(tile[5])).visible = true