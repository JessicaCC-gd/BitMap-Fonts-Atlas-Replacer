@tool
extends EditorPlugin

var scene: Node = preload("res://addons/bitmap_fonts_atlas_replacer/replacer.tscn").instantiate()


const text_types : PackedStringArray = [".tscn", ".tres", ".gd", ".import"]
const font_types : PackedStringArray = [".fnt", ".font"]
const img_types : PackedStringArray = [".svg", ".png", ".jpg", ".jpeg", ".webp", ".bmp", ".tres"]
const atlas_types : PackedStringArray = [".tres", ".res"]

var button : Button
var atlas_path_node : TextEdit
var reorganize_button : CheckButton
var compare_button : CheckButton
var export_button : CheckButton
var utils : Node

var img_files : PackedStringArray = []
var text_files : PackedStringArray = []
var atlas_files : PackedStringArray = []
var font_files : PackedStringArray = []
var files_to_delete : PackedStringArray = []

var godot_version : float

var atlas_path : String
var atlas_dir : DirAccess

func _enter_tree():
	EditorInterface.get_editor_main_screen().add_child(scene)
	button = scene.get_node("VBoxContainer/replace")
	atlas_path_node = scene.get_node("VBoxContainer/atlas_path")
	utils = scene.get_node("VBoxContainer")
	reorganize_button = scene.get_node("VBoxContainer/toggles/reorganize_files")
	compare_button = scene.get_node("VBoxContainer/toggles/compare_size")
	export_button = scene.get_node("VBoxContainer/toggles/export_log")
	button.button_up.connect(start_replacing)
	_make_visible(false)

func _exit_tree():
	if scene:
		scene.queue_free()

func _has_main_screen():
	return true

func _make_visible(visible):
	if scene:
		scene.visible = visible

func _get_plugin_name():
	return "Font Atlas Replacer"

func _get_plugin_icon():
	return EditorInterface.get_editor_theme().get_icon("Image", "EditorIcons")


func start_replacing():
	reset()
	atlas_path = atlas_path_node.get_text()
	atlas_dir = DirAccess.open(atlas_path)
	if !atlas_dir or atlas_path == "":
		utils.console_print("Invalid path")
		return
	utils.console_print("Valid path")
	get_files()
	find_matches()
	if reorganize_button.button_pressed: delete_files()
	utils.console_print("Execution complete!", Color.DARK_GREEN)
	if export_button.button_pressed: export_log()

func reset():
	utils.clear_console()
	img_files = []
	text_files = []
	atlas_files = []
	font_files = []
	files_to_delete = []

func get_files():
	get_atlas_res()
	get_images()
	get_text_files()
	get_font_files()
	
func get_text_files():
	utils.console_print("Searching for text files")
	for text_type in text_types:
		text_files = utils.get_type_files("res://", atlas_path, text_type, text_files)
	utils.console_print("Search for text files completed. Found %d files" %text_files.size())
	#utils.console_print("Filtering for AtlasTexture files")
	#for file in text_files:
		#if file.ends_with(".tres"):
			#var resource = ResourceLoader.load(file)
			#if resource is AtlasTexture:
				#text_files.remove_at(text_files.find(file))
	#utils.console_print("Filtering for AtlasTexture files completed. Text files: %d" % text_files.size())

func get_font_files():
	utils.console_print("Searching for font files")
	for font_type in font_types:
		font_files = utils.get_type_files("res://", atlas_path, font_type, font_files)
	utils.console_print("Search for font files completed. Found %d files" %font_files.size())
	if font_files.size() > 1:
		font_files = utils.find_dups(font_files, "font")

func get_images():
	utils.console_print("Searching for image files")
	for img_type in img_types:
		img_files = utils.get_type_files("res://", atlas_path, img_type, img_files)
	utils.console_print("Search for image files completed. Found %d files" %img_files.size())


func get_atlas_res():
	utils.console_print("Searching for AtlasTexture files")
	for type in atlas_types:
		atlas_files = utils.get_type_files(atlas_path, atlas_path, type, atlas_files)
	utils.console_print("Search for AtlasTexture files completed. Found %d files" % atlas_files.size())
	if atlas_files.size() > 1:
		atlas_files = utils.find_dups(atlas_files, "atlas file")


func find_matches():
	utils.console_print("Searching for font and atlas file matches")
	var matches := 0
	for a in atlas_files.size():
		var atlas_name =  atlas_files[a].get_file().trim_suffix("." + atlas_files[a].get_extension())
		var found_match := false
		for i in font_files.size():
			var font_name =  font_files[i].get_file().trim_suffix("." + font_files[i].get_extension())
			if atlas_name == font_name:
				if replace_font_coords(font_files[i], atlas_files[a]) == OK:
					if reorganize_button.button_pressed:
						replace(font_files[i], atlas_files[a])
					matches += 1
					found_match = true
				else:
					utils.console_print("Found name matches, but dimentions didn't match. File \"%s\" not replaced" %font_files[i].get_file(), Color.DARK_GOLDENROD)
				break
		if !found_match:
			utils.console_print("Didn't find a match for AtlasTexture \"%s\"" % atlas_files[a], Color.DARK_RED)
	utils.console_print("Search for font and atlas file matches completed. Matched %d pairs" %matches)
	

func replace_font_coords(font_path : String, res_path : String):
	
	var font_file = FileAccess.open(font_path, FileAccess.READ)
	if !font_file:
		utils.console_print("Failed to open \"%s\"" %font_path, Color.DARK_RED)
		return 1
		
	var content = font_file.get_as_text()
	font_file.close()
	
	if content.count(font_path.get_file().trim_suffix("." + font_path.get_extension())) < 2:
		utils.console_print("Image name inside fnt file does not correspond to font name. Font file: \"%s\" has not been adjusted" %font_path, Color.DARK_RED)
		return 1
		
	var img_name : String
	for type in img_types:
		if content.contains(type):
			img_name = font_path.get_file().trim_suffix("." + font_path.get_extension()) + type
			break
	if !img_name:
		utils.console_print("Image name inside font file is not of an accepted extension. Font file: \"%s\" has not been adjusted" %font_path, Color.DARK_RED)
		return 1
		
	var res_file : AtlasTexture = ResourceLoader.load(res_path)
	
	if size_compare_reorganize(img_name, font_path, res_file.get_size()) != OK: return 1
	
	content = content.replace(img_name, res_file.atlas.resource_path.get_file())
	
	var x_offset : int = res_file.region.position.x
	var y_offset : int = res_file.region.position.y
	var separator : String = find_separator(content)
	var x_coords : PackedStringArray = find_coordinate("x=", content, separator)
	var y_coords : PackedStringArray = find_coordinate("y=", content, separator)
	
	var idx := 0
	for n in x_coords.size():
		var place = content.find(x_coords[n], idx)
		var new_coord : String = x_coords[n].replace(str(x_coords[n].to_int()), str(x_coords[n].to_int() + x_offset))
		content = content.erase(place, x_coords[n].length())
		content = content.insert(place, new_coord)
		
		place = content.find(y_coords[n], idx)
		new_coord = y_coords[n].replace(str(y_coords[n].to_int()), str(y_coords[n].to_int() + y_offset))
		content = content.erase(place, y_coords[n].length())
		content = content.insert(place, new_coord)
		idx = place
	
	font_file = FileAccess.open(font_path, FileAccess.WRITE)
	font_file.store_string(content)
	
	return OK

func find_coordinate(coord : String, content : String, separator : String):
	var coords : PackedStringArray = []
	var idx := 0
	for x in content.countn(coord):
		var start := content.findn(coord, idx)
		var end := content.find(separator, start)
		if separator == "\"":
			end = content.find(separator, end + 1)
		coords.append(content.substr(start, end - start))
		idx = end
	return coords

func find_separator(content : String):
	var start : int = content.findn("x=")
	
	var space : int = content.find(" ", start)
	var semicolon : int = content.find(";", start)
	var quotes : int = content.find("\"", start)
	
	var idxs := [space, semicolon, quotes]
	var s_idx = content.length()
	for i in 3:
		if idxs[i] >= 0 and idxs[i] < s_idx:
			s_idx = idxs[i]
	
	return content[s_idx]
	

func size_compare_reorganize(img_name : String, font_path : String, res_size : Vector2):
	if compare_button.button_pressed or reorganize_button.button_pressed:
		var img_file : String
		for file in img_files:
			if file.contains(img_name):
				img_file = file
				break
		if compare_button.button_pressed:
			if !img_file:
				utils.console_print("Didn't find image from font file to compare dimensions. Font file: \"%s\" has not been adjusted" %font_path, Color.DARK_RED)
				return 1
			var tmp_img := ResourceLoader.load(img_file)
			if tmp_img.get_size() != res_size:
				utils.console_print("Found name matches, but dimentions didn't match. Font file: \"%s\" has not been adjusted" %font_path, Color.DARK_RED)
				return 1
		if reorganize_button.button_pressed:
			files_to_delete.append(img_file)
	return OK


	
#func REORGANIZE():
	#utils.console_print("Searching for image and atlas file matches")
	#var matches := 0
	#for res : AtlasTexture in atlas_data:
		#var found_match := false
		#for i in img_files.size():
			#var img_name =  img_files[i].get_file().trim_suffix("." + img_files[i].get_extension())
			#if res.resource_name == img_name:
				#var img = img_data[i]
				#if compare_button.button_pressed:
					#if Vector2i(img.get_size()) != Vector2i(res.get_size()):
						#utils.console_print("Found name matches, but dimentions didn't match. File \"%s\" not replaced" %img_files[i].get_file(), Color.DARK_GOLDENROD)
						#break
				#matches += 1
				#replace(img, res.resource_path)
				#found_match = true
				#break
		#if !found_match:
			#utils.console_print("Didn't find a match for AtlasTexture \"%s\"" % res.resource_path, Color.DARK_RED)
	#utils.console_print("Search for image and atlas file matches completed. Matched %d pairs" %matches)


func replace(font_path : String, atlas_file : String):
	var dir := DirAccess.open("res://")
	var new_path := atlas_path + font_path.get_file()
	var uid = ResourceLoader.get_resource_uid(font_path)
	dir.rename(font_path, new_path)
	ResourceUID.set_id(uid, new_path)
	
	var edited_files : PackedStringArray = []
	for text_file in text_files:
		var is_font_import := false
		for type in font_types:
			if text_file.contains(type + ".import"):
				is_font_import = true
				break
		if is_font_import: continue
		var file := FileAccess.open(text_file, FileAccess.READ)
		if !file:
			utils.console_print("Failed to open \"%s\"" %text_file, Color.DARK_RED)
			continue
		var content = file.get_as_text()
		var edits := 0
		if content.contains(font_path):
			content = content.replace(font_path, new_path)
			edits += 1
		file.close()
		if edits:
			file = FileAccess.open(text_file, FileAccess.WRITE)
			file.store_string(content)
			file.close()
			edited_files.append(text_file)
	
	if dir.file_exists(font_path + ".import"):
		dir.rename(font_path + ".import", new_path + ".import")
	if edited_files:
		utils.console_print("Moved %s to %s. Replaced paths in the following files: %s" %[font_path, new_path, edited_files], Color.TEAL)
	files_to_delete.append(atlas_file)

func delete_files():
	var dir = DirAccess.open("res://")
	
	for file in files_to_delete:
		if dir.remove(file) == OK:
			utils.console_print("Deleted " + file, Color.DARK_SLATE_BLUE)
		else: utils.console_print("Failed to delete " + file, Color.DARK_GOLDENROD)
		
		if dir.file_exists(file + ".import"):
			if dir.remove(file + ".import") == OK:
				utils.console_print("Deleted " + file + ".import", Color.DARK_SLATE_BLUE)
			else: utils.console_print("Failed to delete " + file, Color.DARK_GOLDENROD)
			
		if dir.file_exists(file + ".uid"):
			if dir.remove(file + ".uid") == OK:
				utils.console_print("Deleted " + file + ".uid", Color.DARK_SLATE_BLUE)
			else: utils.console_print("Failed to delete " + file, Color.DARK_GOLDENROD)
		

func export_log():
	var content = utils.get_text()
	var save_path = "user://godot_font_replacer_log.txt"
	var file : FileAccess
	file = FileAccess.open(save_path, FileAccess.WRITE)
	if !file:
		utils.console_print("Failed to overwrite log file " + save_path, Color.DARK_RED)
		return
	file.store_string(content)
	file.close()
	DirAccess.make_dir_absolute(save_path)
	utils.console_print("Log file saved at " + OS.get_user_data_dir() + "/" + save_path.trim_prefix("user://"), Color.DARK_GREEN)
