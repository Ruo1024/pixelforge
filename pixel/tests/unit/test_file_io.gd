extends "res://addons/gut/test.gd"

const FileIOScript := preload("res://infra/file_io.gd")
const ImageMath := preload("res://core/util/image_math.gd")


func before_all() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("user://tests"))


func test_png_round_trip_keeps_pixels() -> void:
	var image := _make_test_image()
	var path := "user://tests/file_io_roundtrip.png"

	assert_eq(FileIOScript.save_png(image, path), OK)
	var loaded: Image = FileIOScript.load_png(path)

	assert_not_null(loaded)
	assert_eq(loaded.get_size(), image.get_size())
	assert_eq(ImageMath.color_set(loaded), ImageMath.color_set(image))


func test_zip_pack_and_unpack_keeps_content() -> void:
	var bytes := PackedByteArray()
	bytes.append(1)
	bytes.append(2)
	bytes.append(3)

	var path := "user://tests/file_io_zip.pxproj"
	var pack := {
		"manifest.json": {"name": "zip-test"},
		"nested/data.bin": bytes,
		"readme.txt": "hello",
	}

	assert_eq(FileIOScript.zip_pack(pack, path), OK)
	var unpacked: Dictionary = FileIOScript.zip_unpack(path)

	assert_true(unpacked["ok"])
	assert_eq(FileIOScript.bytes_to_json(unpacked["files"]["manifest.json"])["name"], "zip-test")
	assert_eq(unpacked["files"]["nested/data.bin"], bytes)
	assert_eq(unpacked["files"]["readme.txt"].get_string_from_utf8(), "hello")


func test_atomic_write_tmp_does_not_damage_original() -> void:
	var path := "user://tests/atomic_write.txt"
	assert_eq(FileIOScript.atomic_write(path, "old".to_utf8_buffer()), OK)

	var interrupted_tmp := FileAccess.open(path + ".manual-tmp", FileAccess.WRITE)
	interrupted_tmp.store_string("new")
	interrupted_tmp.close()

	var original := FileAccess.open(path, FileAccess.READ)
	assert_eq(original.get_as_text(), "old")

	assert_eq(FileIOScript.atomic_write(path, "new".to_utf8_buffer()), OK)
	var updated := FileAccess.open(path, FileAccess.READ)
	assert_eq(updated.get_as_text(), "new")


func test_logger_creates_date_file() -> void:
	var logger := get_tree().root.get_node("Logger")
	logger.info("test logger file creation")
	assert_true(FileAccess.file_exists(logger.get_current_log_path()))


func test_logger_prunes_logs_older_than_retention_days() -> void:
	var logger := get_tree().root.get_node("Logger")
	var old_path := "user://logs/app_2026-06-01.log"
	var recent_path := "user://logs/app_2026-06-10.log"
	assert_eq(FileIOScript.atomic_write(old_path, "old".to_utf8_buffer()), OK)
	assert_eq(FileIOScript.atomic_write(recent_path, "recent".to_utf8_buffer()), OK)

	var now := (
		Time
		. get_unix_time_from_datetime_dict(
			{
				"year": 2026,
				"month": 6,
				"day": 12,
				"hour": 0,
				"minute": 0,
				"second": 0,
			}
		)
	)
	logger.cleanup_old_logs(now)

	assert_false(FileAccess.file_exists(old_path))
	assert_true(FileAccess.file_exists(recent_path))


func _make_test_image() -> Image:
	var image := Image.create(2, 2, false, Image.FORMAT_RGBA8)
	image.set_pixel(0, 0, Color.RED)
	image.set_pixel(1, 0, Color.GREEN)
	image.set_pixel(0, 1, Color.BLUE)
	image.set_pixel(1, 1, Color.TRANSPARENT)
	return image
