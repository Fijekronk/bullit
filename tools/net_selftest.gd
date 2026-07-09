extends SceneTree
## Headless-самопроверка новых сетевых утилит:
##   (без аргументов)  — распаковка zip в Updater + генерация .cmd-хелпера
##   --lan-host        — маячит в локалку 8 c и выходит
##   --lan-client      — слушает локалку, при находке пишет dump и выходит
## Запуск: godot --headless --path <proj> --script res://tools/net_selftest.gd -- <arg>

func _init() -> void:
	var args := OS.get_cmdline_user_args()
	if args.has("--lan-host"):
		_lan_host()
	elif args.has("--lan-client"):
		_lan_client()
	else:
		_updater_selftest()


func _updater_selftest() -> void:
	var tmp := OS.get_environment("TEMP")
	if tmp == "":
		tmp = OS.get_cache_dir()
	var zip_path := tmp.path_join("bullit_selftest.zip")
	# Пакуем тестовый zip (эмулируем bullit_win.zip).
	var packer := ZIPPacker.new()
	assert(packer.open(zip_path) == OK, "ZIPPacker open")
	packer.start_file("version.txt")
	packer.write_file("playtest-1234".to_utf8_buffer())
	packer.close_file()
	packer.start_file("bullit.exe")
	packer.write_file(PackedByteArray([1, 2, 3, 4, 5]))
	packer.close_file()
	packer.close()

	var up := Updater.new()
	var dest := tmp.path_join("bullit_selftest_stage")
	var ok := up._extract_zip(zip_path, dest)
	var v := ""
	if FileAccess.file_exists(dest.path_join("version.txt")):
		v = FileAccess.get_file_as_string(dest.path_join("version.txt")).strip_edges()
	var exe_ok := FileAccess.file_exists(dest.path_join("bullit.exe"))
	var helper := up._write_helper(dest, "C:\\Games\\bullit", 4242)
	var helper_txt := ""
	if helper != "" and FileAccess.file_exists(helper):
		helper_txt = FileAccess.get_file_as_string(helper)

	var pass_ext := ok and v == "playtest-1234" and exe_ok
	var pass_help := helper_txt.contains("4242") and helper_txt.contains("robocopy") \
			and helper_txt.contains("bullit.exe")
	print("EXTRACT: ", "OK" if pass_ext else "FAIL", " (version=", v, " exe=", exe_ok, ")")
	print("HELPER: ", "OK" if pass_help else "FAIL")
	print("SELFTEST RESULT: ", "PASS" if (pass_ext and pass_help) else "FAIL")
	quit(0 if (pass_ext and pass_help) else 1)


func _lan_host() -> void:
	var lan := LanDiscovery.new()
	get_root().add_child(lan)
	lan.advertise(9050, "host-selftest")
	print("LAN host: маячу…")
	var frames := 0
	while frames < 480:
		await process_frame
		frames += 1
	quit(0)


func _lan_client() -> void:
	var lan := LanDiscovery.new()
	get_root().add_child(lan)
	var found := {"hit": false}
	lan.host_found.connect(func(ip, port, nick):
		if not found["hit"]:
			found["hit"] = true
			print("LAN FOUND: ", ip, " ", port, " ", nick))
	lan.listen()
	print("LAN client: слушаю…")
	var frames := 0
	while frames < 420 and not found["hit"]:
		await process_frame
		frames += 1
	print("LAN CLIENT RESULT: ", "PASS" if found["hit"] else "FAIL")
	quit(0 if found["hit"] else 1)
