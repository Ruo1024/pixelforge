class_name PFEditHistory
extends RefCounted

## Editor-local snapshot history, intentionally isolated from the infinite-canvas UndoService.

var _undo: Array = []
var _redo: Array = []
var _limit := 32


func capture(document: PFEditDoc) -> void:
	_undo.append(document.snapshot())
	if _undo.size() > _limit:
		_undo.pop_front()
	_redo.clear()


func undo(document: PFEditDoc) -> bool:
	if _undo.is_empty():
		return false
	_redo.append(document.snapshot())
	document.restore(_undo.pop_back())
	return true


func redo(document: PFEditDoc) -> bool:
	if _redo.is_empty():
		return false
	_undo.append(document.snapshot())
	document.restore(_redo.pop_back())
	return true
