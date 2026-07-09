extends Node
class_name Updater
## Самообновление игры (без внешнего лаунчера/батника). При старте игра сама
## сверяет version.txt рядом с exe с последним playtest-релизом на GitHub и,
## если вышло новое, качает bullit_win.zip, распаковывает во временную папку и
## запускает служебный .cmd, который дожидается выхода игры, копирует новые
## файлы поверх и перезапускает bullit.exe. Пользователь просто открывает игру.
##
## В редакторе и без сети — тихо пропускается (играем на текущем билде).

signal status(text: String)          # строка для UI меню
signal finished(updated: bool)       # проверка завершена (updated=false → играем)

const REPO := "Fijekronk/bullit"
const ZIP_NAME := "bullit_win.zip"

var _http: HTTPRequest
var _dl: HTTPRequest
var _release: Dictionary
var _busy := false


func check_and_update() -> void:
	# В редакторе обновляться нечему — сразу отдаём управление меню.
	if OS.has_feature("editor"):
		finished.emit(false)
		return
	_busy = true
	status.emit("Проверка обновлений…")
	_http = HTTPRequest.new()
	add_child(_http)
	_http.request_completed.connect(_on_release_info)
	# playtest публикуются как prerelease — берём первый из общего списка.
	var url := "https://api.github.com/repos/%s/releases?per_page=1" % REPO
	var err := _http.request(url, ["User-Agent: bullit-game"])
	if err != OK:
		_give_up("Нет сети — играем на текущей версии.")


func _on_release_info(result: int, code: int, _headers, body: PackedByteArray) -> void:
	if result != HTTPRequest.RESULT_SUCCESS or code != 200:
		_give_up("GitHub недоступен — играем на текущей версии.")
		return
	var data = JSON.parse_string(body.get_string_from_utf8())
	if typeof(data) != TYPE_ARRAY or data.is_empty():
		_give_up("Релизов пока нет — играем на текущей версии.")
		return
	_release = data[0]
	var remote := String(_release.get("tag_name", "")).replace("playtest-", "")
	var local := _local_version()
	if remote == "" or remote == local:
		_give_up("Версия актуальна.")
		return
	# Есть обновление — качаем zip.
	status.emit("Обновление до %s — качаю…" % remote)
	var asset := _find_asset(_release)
	if asset.is_empty():
		_give_up("В релизе нет %s — играем на текущей." % ZIP_NAME)
		return
	_dl = HTTPRequest.new()
	add_child(_dl)
	_dl.download_file = _tmp("bullit_update.zip")
	_dl.request_completed.connect(_on_zip_done.bind(remote))
	var err := _dl.request(String(asset["browser_download_url"]), ["User-Agent: bullit-game"])
	if err != OK:
		_give_up("Скачивание не началось — играем на текущей.")


func _on_zip_done(result: int, code: int, _headers, _body: PackedByteArray, remote: String) -> void:
	if result != HTTPRequest.RESULT_SUCCESS or code != 200:
		_give_up("Не докачалось — играем на текущей версии.")
		return
	var stage := _tmp("bullit_stage")
	if not _extract_zip(_tmp("bullit_update.zip"), stage):
		_give_up("Архив повреждён — играем на текущей версии.")
		return
	status.emit("Устанавливаю %s и перезапускаю…" % remote)
	var exe_dir := OS.get_executable_path().get_base_dir()
	var helper := _write_helper(stage, exe_dir, OS.get_process_id())
	if helper == "":
		_give_up("Не удалось подготовить обновление — играем на текущей.")
		return
	# Запускаем служебный скрипт (он ждёт выхода игры) и выходим.
	OS.create_process("cmd.exe", ["/c", helper])
	finished.emit(true)
	get_tree().quit()


# --- Вспомогательное ---
func _give_up(msg: String) -> void:
	status.emit(msg)
	_busy = false
	finished.emit(false)


func _local_version() -> String:
	var p := OS.get_executable_path().get_base_dir().path_join("version.txt")
	if FileAccess.file_exists(p):
		return FileAccess.get_file_as_string(p).strip_edges()
	return ""


func _find_asset(rel: Dictionary) -> Dictionary:
	for a in rel.get("assets", []):
		if String(a.get("name", "")) == ZIP_NAME:
			return a
	return {}


func _tmp(name: String) -> String:
	var base := OS.get_environment("TEMP")
	if base == "":
		base = OS.get_cache_dir()
	return base.path_join(name)


## Распаковать zip в dest (очистив её). true при успехе.
func _extract_zip(zip_path: String, dest: String) -> bool:
	var reader := ZIPReader.new()
	if reader.open(zip_path) != OK:
		return false
	# Пересоздать staging.
	_rmtree(dest)
	DirAccess.make_dir_recursive_absolute(dest)
	for entry in reader.get_files():
		var target := dest.path_join(entry)
		if entry.ends_with("/"):
			DirAccess.make_dir_recursive_absolute(target)
			continue
		DirAccess.make_dir_recursive_absolute(target.get_base_dir())
		var bytes := reader.read_file(entry)
		var f := FileAccess.open(target, FileAccess.WRITE)
		if f == null:
			reader.close()
			return false
		f.store_buffer(bytes)
		f.close()
	reader.close()
	return true


## Служебный .cmd: ждёт выхода игры (по PID), копирует staging поверх exe-папки,
## перезапускает игру и самоудаляется. Возвращает путь или "" при ошибке.
func _write_helper(stage: String, dest: String, pid: int) -> String:
	var path := _tmp("bullit_update.cmd")
	var win_stage := stage.replace("/", "\\")
	var win_dest := dest.replace("/", "\\")
	var lines := [
		"@echo off",
		"setlocal",
		":wait",
		"tasklist /fi \"PID eq %d\" | find \"%d\" >nul && (timeout /t 1 /nobreak >nul & goto wait)" % [pid, pid],
		"robocopy \"%s\" \"%s\" /e /nfl /ndl /njh /njs /nc /ns /np >nul" % [win_stage, win_dest],
		"rmdir /s /q \"%s\"" % win_stage,
		"start \"\" \"%s\\bullit.exe\"" % win_dest,
		"del \"%%~f0\"",
	]
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return ""
	f.store_string("\r\n".join(lines) + "\r\n")
	f.close()
	return path


func _rmtree(dir: String) -> void:
	if not DirAccess.dir_exists_absolute(dir):
		return
	var d := DirAccess.open(dir)
	if d == null:
		return
	d.list_dir_begin()
	var name := d.get_next()
	while name != "":
		var full := dir.path_join(name)
		if d.current_is_dir():
			_rmtree(full)
		else:
			DirAccess.remove_absolute(full)
		name = d.get_next()
	d.list_dir_end()
	DirAccess.remove_absolute(dir)
